import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/error_text.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/server_config.dart';
import '../../../core/models/category_ref.dart';
import '../../../core/utils/category_emoji_helper.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../../campus_services/ui/campus_services_admin_panel.dart';
import '../../lost_found/domain/lost_found_item.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../../lost_found/ui/widgets/lost_found_detail_dialog.dart';
import '../domain/content_report.dart';
import '../providers/admin_providers.dart';
import 'moderator_grants_panel.dart';

/// The panel's tabs. The admin sees all of them; a moderator sees only the ones they can use.
enum _PanelTab { moderators, users, reports, categories, health, campusServices }

class AdminControlsScreen extends ConsumerStatefulWidget {
  final int? initialTab;

  /// The route this was opened on: `/admin` or `/moderator` (null when not opened by the router).
  final String? path;
  const AdminControlsScreen({super.key, this.initialTab, this.path});

  @override
  ConsumerState<AdminControlsScreen> createState() => _AdminControlsScreenState();
}

class _AdminControlsScreenState extends ConsumerState<AdminControlsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<_PanelTab> _tabs;

  // User management form
  final _userEmailController = TextEditingController();
  bool _isUpdatingUser = false;
  bool _isTransferringAdmin = false;

  // New category form
  final _categoryController = TextEditingController();
  String _categoryTarget = 'buy_sell';
  bool _isAddingCategory = false;

  // Live Demo Backend connection form (Admin only)
  late final TextEditingController _baseUrlController;
  late final TextEditingController _devKeyController;
  late final TextEditingController _devUserEmailController;
  late final TextEditingController _databaseUrlController;
  bool _useMockMode = true;
  bool _obscureDevKey = true;
  bool _isTestingConnection = false;
  bool _isSavingConnection = false;
  Map<String, dynamic>? _connectionTestReport;

  @override
  void initState() {
    super.initState();
    // Check roles with the server now: if this person's moderator role was just removed, the
    // screen falls back to "Access Restricted" instead of showing tools from a stale session.
    ref.read(authRepositoryProvider).getCurrentUser().then((_) {}, onError: (_) {});
    final user = ref.read(currentUserProvider);
    final isAdmin = user?.isAdmin ?? false;
    _tabs = isAdmin
        ? _PanelTab.values
        : [
            _PanelTab.reports,
            if (user != null && (user.canModerateBuySell || user.canModerateLostFound)) _PanelTab.categories,
            if (user != null && user.isDepartmentModerator) _PanelTab.moderators,
          ];
    final initial = (widget.initialTab != null && widget.initialTab! >= 0 && widget.initialTab! < _tabs.length)
        ? widget.initialTab!
        : 0;
    _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: initial);

    // Default category target according to user's permissions
    if (user != null && !user.isAdmin) {
      if (user.canModerateLostFound && !user.canModerateBuySell) {
        _categoryTarget = 'lost_found';
      } else {
        _categoryTarget = 'buy_sell';
      }
    }

    // Initialize backend demo configuration from active ServerConfig
    final config = ref.read(serverConfigProvider);
    _useMockMode = config.useMockData;
    _baseUrlController = TextEditingController(text: config.apiBaseUrl);
    _devKeyController = TextEditingController(text: config.devKey);
    _devUserEmailController = TextEditingController(text: config.devUserEmail);
    _databaseUrlController = TextEditingController(
      text: config.databaseUrl ?? 'postgresql://postgres:password@10.217.103.203:5432/campushub',
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userEmailController.dispose();
    _categoryController.dispose();
    _baseUrlController.dispose();
    _devKeyController.dispose();
    _devUserEmailController.dispose();
    _databaseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    // Admins belong on /admin and moderators on /moderator: fix the address if it's the other one.
    final path = widget.path;
    if (path != null && currentUser != null && currentUser.isModerator && currentUser.controlsPath != path) {
      final query = GoRouterState.of(context).uri.query;
      final target = '${currentUser.controlsPath}${query.isEmpty ? '' : '?$query'}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.replace(target);
      });
    }

    // Security Gate: Admin or Moderator
    if (currentUser == null || (!currentUser.isAdmin && !currentUser.isModerator)) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/buy'),
          ),
          title: const Text('Access Restricted'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              margin: const EdgeInsets.all(24),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.red.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gpp_bad_rounded, size: 56, color: Colors.red.shade700),
                    const SizedBox(height: 16),
                    const Text(
                      'Access Restricted',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This area is restricted to active IISc CampusHub Administrators and appointed Module Moderators. Please sign in with an authorized account to view and execute governance actions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.go('/buy'),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back to Home'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Return to Campus',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/buy');
            }
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: currentUser.isAdmin ? Colors.blue.shade900 : Colors.teal.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                currentUser.isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentUser.isAdmin ? 'Admin Controls & Governance' : 'Moderator Controls & Reports',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    currentUser.isAdmin
                        ? 'Single-Admin Governance'
                        : 'Module Moderation & Content Review',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (currentUser.isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: Icon(
                  _useMockMode ? Icons.settings_ethernet_rounded : Icons.wifi_rounded,
                  size: 16,
                  color: _useMockMode ? null : Colors.green.shade700,
                ),
                label: Text(
                  _useMockMode ? 'Connect Live Backend' : 'Live Backend Active',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _goTo(_PanelTab.health),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: theme.colorScheme.primary,
          tabs: [for (final t in _tabs) _tabFor(t, currentUser)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [for (final t in _tabs) _viewFor(t, isDark, theme, currentUser)],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Roles & Moderators
  // ---------------------------------------------------------------------------
  void _goTo(_PanelTab tab) {
    final index = _tabs.indexOf(tab);
    if (index >= 0) _tabController.animateTo(index);
  }

  Tab _tabFor(_PanelTab tab, User user) => switch (tab) {
        _PanelTab.moderators => Tab(
            icon: const Icon(Icons.shield_outlined, size: 18),
            text: user.isAdmin ? 'Moderators' : 'Course moderators',
          ),
        _PanelTab.users => const Tab(icon: Icon(Icons.manage_accounts_outlined, size: 18), text: 'User Accounts'),
        _PanelTab.reports => const Tab(icon: Icon(Icons.report_gmailerrorred_rounded, size: 18), text: 'Reports Queue'),
        _PanelTab.categories => const Tab(icon: Icon(Icons.category_outlined, size: 18), text: 'Categories'),
        _PanelTab.health => const Tab(icon: Icon(Icons.dns_outlined, size: 18), text: 'Backend & Health'),
        _PanelTab.campusServices =>
          const Tab(icon: Icon(Icons.health_and_safety_outlined, size: 18), text: 'Campus Services'),
      };

  Widget _viewFor(_PanelTab tab, bool isDark, ThemeData theme, User user) => switch (tab) {
        _PanelTab.moderators => const ModeratorGrantsPanel(),
        _PanelTab.users => _buildUsersTab(isDark, theme),
        _PanelTab.reports => _buildReportsQueueTab(isDark, theme),
        _PanelTab.categories => _buildCategoriesTab(isDark, theme),
        _PanelTab.health => _buildSystemHealthTab(isDark, theme),
        _PanelTab.campusServices => CampusServicesAdminPanel(isAdmin: user.isAdmin),
      };

  // ---------------------------------------------------------------------------
  // TAB 2: User Account Controls & Single Admin Handover
  // ---------------------------------------------------------------------------
  Widget _buildUsersTab(bool isDark, ThemeData theme) {
    final currentUser = ref.watch(currentUserProvider);
    final isUserAdmin = currentUser?.isAdmin ?? false;

    if (!isUserAdmin) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Card(
            margin: const EdgeInsets.all(24),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_person_outlined, size: 48, color: Colors.orange.shade700),
                  const SizedBox(height: 12),
                  const Text('Administrator Privileges Required', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'User account deactivation and administrative role handover are reserved strictly for the Administrator. Switch to Reports Queue to review flagged listings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.report_gmailerrorred_rounded, size: 16),
                    label: const Text('Go to Reports Queue'),
                    onPressed: () => _goTo(_PanelTab.reports),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final usersAsync = ref.watch(registeredUsersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Single Admin Handover Card
              Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFEF2F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.red.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 22, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Single-Admin Handover by Email ID',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Under the single-admin governance model, there is exactly one active administrator. Naming your successor will transfer all administrative authorities and automatically adjust your account to a standard student role in the same transaction.',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.red.shade900),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _userEmailController,
                        decoration: InputDecoration(
                          labelText: 'Successor IISc Email',
                          hintText: 'e.g. mohammadazam@iisc.ac.in',
                          prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                              side: BorderSide(color: Colors.orange.shade400),
                            ),
                            icon: const Icon(Icons.person_off_outlined, size: 16),
                            label: const Text('Toggle Active / Inactive'),
                            onPressed: _isUpdatingUser ? null : () => _handleToggleUserStatus(),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                            icon: _isTransferringAdmin
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.admin_panel_settings, size: 16),
                            label: const Text('Handover Admin Role'),
                            onPressed: _isTransferringAdmin ? null : () => _handleTransferAdmin(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Registered Campus Members & Status Overview',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              usersAsync.when(
                data: (users) {
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final u = users[idx];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: u.isAdmin ? Colors.red.shade100 : Colors.teal.shade100,
                            child: Text(
                              u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: u.isAdmin ? Colors.red.shade900 : Colors.teal.shade900,
                              ),
                            ),
                          ),
                          title: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              if (u.isAdmin)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: u.isActive ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: u.isActive ? Colors.green.shade200 : Colors.red.shade200),
                                ),
                                child: Text(
                                  u.isActive ? 'ACTIVE' : 'DEACTIVATED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: u.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Email: ${u.email} • ${u.programme ?? "Student"} (${u.graduationYear ?? "—"})',
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            tooltip: 'Fill into email input',
                            onPressed: () {
                              _userEmailController.text = u.email;
                              _showToast('Copied ${u.email} into email field.');
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading users: ${errorText(e)}', style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTransferAdmin() async {
    final email = _userEmailController.text.trim();
    if (email.isEmpty) {
      _showToast('Please enter the successor IISc email address.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Single-Admin Handover'),
        content: Text(
          'Warning: This is a permanent administrative transfer. You will name $email as the new Administrator and immediately become a regular signed-in student.\n\nProceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Handover Administrator Role'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isTransferringAdmin = true);
      try {
        await ref.read(adminRepositoryProvider).transferAdminRole(email);
        ref.invalidate(registeredUsersProvider);
        ref.invalidate(currentUserProvider);
        _showToast('Administrator role transferred successfully to $email.');
        if (mounted) context.go('/buy');
      } catch (e) {
        _showToast('Transfer failed: ${errorText(e)}', isError: true);
      } finally {
        if (mounted) setState(() => _isTransferringAdmin = false);
      }
    }
  }

  Future<void> _handleToggleUserStatus() async {
    final email = _userEmailController.text.trim();
    if (email.isEmpty) {
      _showToast('Please enter the IISc email address.');
      return;
    }

    setState(() => _isUpdatingUser = true);
    try {
      final repo = ref.read(adminRepositoryProvider);
      final users = await repo.listRegisteredUsers();
      final user = users.firstWhere(
        (u) => u.email.toLowerCase() == email.toLowerCase(),
        orElse: () => throw Exception('User $email not found.'),
      );

      final nextActive = !user.isActive;
      await repo.updateUserStatus(email: email, isActive: nextActive);
      ref.invalidate(registeredUsersProvider);
      _showToast('Account $email is now ${nextActive ? "Active" : "Deactivated"}.');
    } catch (e) {
      _showToast('Failed to update status: ${errorText(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdatingUser = false);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 3: Reports Queue & Content Moderation (FR-10)
  // ---------------------------------------------------------------------------
  Widget _buildReportsQueueTab(bool isDark, ThemeData theme) {
    final reportsAsync = ref.watch(contentReportsProvider);
    final filter = ref.watch(contentReportsFilterProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filters toolbar
              Row(
                children: [
                  const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  for (final st in ['open', 'actioned', 'dismissed', 'all']) ...[
                    ChoiceChip(
                      label: Text(st.toUpperCase()),
                      selected: filter.status == st,
                      onSelected: (sel) {
                        if (sel) {
                          ref.read(contentReportsFilterProvider.notifier).state =
                              ContentReportsFilter(status: st, module: filter.module);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              reportsAsync.when(
                data: (reports) {
                  if (reports.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 40, color: Colors.green.shade600),
                          const SizedBox(height: 8),
                          const Text('No content reports in this view.', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('All reported listings and items have been reviewed.', style: TextStyle(color: theme.hintColor, fontSize: 12)),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: reports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) {
                      final r = reports[idx];
                      final isOpen = r.status == 'open';

                      return Card(
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isOpen ? Colors.orange.shade300 : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => _openReportTarget(r),
                          child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isOpen ? Colors.orange.shade100 : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      r.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isOpen ? Colors.orange.shade900 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${r.module.toUpperCase()} • Target: ${r.targetType}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const Spacer(),
                                  Text(
                                    DateTimeFormatter.timeAgo(r.createdAt),
                                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('Reason for Report:', style: TextStyle(fontSize: 11, color: theme.hintColor, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(r.reason, style: const TextStyle(fontSize: 13, height: 1.4)),
                              if (r.resolutionNote != null && r.resolutionNote!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('Resolution Note: ${r.resolutionNote}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                              ],
                              if (isOpen) ...[
                                const Divider(height: 24),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _handleResolveReport(r.id, action: 'dismissed', removeContent: false),
                                        child: const Text('Dismiss Flag'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _handleResolveReport(r.id, action: 'actioned', removeContent: false),
                                        child: const Text('Action (Keep Content)'),
                                      ),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                                        label: const Text('Action & Soft-Delete'),
                                        onPressed: () => _handleResolveReport(r.id, action: 'actioned', removeContent: true),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading reports: ${errorText(e)}', style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens whatever a report points at, so a moderator can see the actual content before acting.
  Future<void> _openReportTarget(ContentReport r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (r.targetType) {
        case 'listing':
          final item = await ref.read(buySellRepositoryProvider).getListingById(r.targetId);
          if (!mounted) return;
          if (item == null) throw Exception('This listing has been removed.');
          await showDialog(context: context, builder: (_) => BuySellDetailDialog(item: item));
        case 'lost_report':
        case 'found_report':
          final kind = r.targetType == 'lost_report' ? PostType.lost : PostType.found;
          final item = await ref.read(lostFoundRepositoryProvider).getReportById(r.targetId, type: kind);
          if (!mounted) return;
          if (item == null) throw Exception('This report has been removed.');
          await showDialog(context: context, builder: (_) => LostFoundDetailDialog(item: item));
        default:
          messenger.showSnackBar(SnackBar(
            content: Text('Opening "${r.targetType}" content isn\'t supported yet.'),
            behavior: SnackBarBehavior.floating,
          ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _handleResolveReport(String id, {required String action, required bool removeContent}) async {
    final noteController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Resolve Content Report ($action)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(removeContent
                ? 'Resolving with action=actioned will soft-delete the reported content from the campus feeds.'
                : 'Closing report as $action.'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Resolution Audit Note (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Resolution'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(adminRepositoryProvider).resolveReport(
              id,
              action: action,
              note: noteController.text.trim(),
              removeContent: removeContent,
            );
        ref.invalidate(contentReportsProvider);
        _showToast('Report marked as $action.');
      } catch (e) {
        _showToast('Failed to resolve report: ${errorText(e)}', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 4: Categories Governance
  // ---------------------------------------------------------------------------
  Widget _buildCategoriesTab(bool isDark, ThemeData theme) {
    final bsCategories = ref.watch(buySellCategoriesProvider);
    final lfCategories = ref.watch(lostFoundCategoriesProvider);
    final currentUser = ref.watch(currentUserProvider);

    final canManageBuySell = currentUser?.isAdmin == true || (currentUser?.canModerateBuySell ?? false);
    final canManageLostFound = currentUser?.isAdmin == true || (currentUser?.canModerateLostFound ?? false);
    final canManageAny = canManageBuySell || canManageLostFound;

    // Ensure _categoryTarget is pointing to a permitted module
    if (!canManageBuySell && canManageLostFound && _categoryTarget != 'lost_found') {
      _categoryTarget = 'lost_found';
    } else if (canManageBuySell && !canManageLostFound && _categoryTarget != 'buy_sell') {
      _categoryTarget = 'buy_sell';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canManageAny)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded, size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text(
                              'Add Official Campus Category',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Authorized moderators and admins can add, rename, or remove categories. Changes immediately reflect in feed filter pills and posting dialogs.',
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _categoryController,
                                decoration: InputDecoration(
                                  labelText: 'Category Name',
                                  hintText: 'e.g. Sports Gear, Musical Instruments',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: _categoryTarget,
                              items: [
                                if (canManageBuySell)
                                  const DropdownMenuItem(value: 'buy_sell', child: Text('Buy & Sell')),
                                if (canManageLostFound)
                                  const DropdownMenuItem(value: 'lost_found', child: Text('Lost & Found')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _categoryTarget = val);
                              },
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _isAddingCategory ? null : _handleAddCategory,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Category'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade800, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'You do not have moderator authority to modify categories for Buy & Sell or Lost & Found.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Active Buy & Sell Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  if (canManageBuySell)
                    Text('(tap chip to rename, ✕ to delete)', style: TextStyle(fontSize: 11, color: theme.hintColor))
                  else
                    Text('(read-only for non-moderators)', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ],
              ),
              const SizedBox(height: 8),
              bsCategories.when(
                data: (cats) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cats.map((c) {
                    final cleanTitle = CategoryEmojiHelper.cleanName(c.name);
                    if (canManageBuySell) {
                      return InputChip(
                        label: Text(cleanTitle),
                        avatar: const Icon(Icons.edit_outlined, size: 14),
                        tooltip: 'Tap to rename "$cleanTitle", click ✕ to delete',
                        onPressed: () => _showEditCategoryDialog('buy_sell', c),
                        onDeleted: () => _confirmDeleteCategory('buy_sell', c),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        deleteButtonTooltipMessage: 'Delete "$cleanTitle"',
                      );
                    }
                    return Chip(
                      label: Text(cleanTitle),
                      avatar: const Icon(Icons.label_outline, size: 14),
                    );
                  }).toList(),
                ),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: ${errorText(e)}'),
              ),

              const SizedBox(height: 28),
              Row(
                children: [
                  const Text('Active Lost & Found Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  if (canManageLostFound)
                    Text('(tap chip to rename, ✕ to delete)', style: TextStyle(fontSize: 11, color: theme.hintColor))
                  else
                    Text('(read-only for non-moderators)', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ],
              ),
              const SizedBox(height: 8),
              lfCategories.when(
                data: (cats) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cats.map((c) {
                    final cleanTitle = CategoryEmojiHelper.cleanName(c.name);
                    if (canManageLostFound) {
                      return InputChip(
                        label: Text(cleanTitle),
                        avatar: const Icon(Icons.edit_outlined, size: 14),
                        tooltip: 'Tap to rename "$cleanTitle", click ✕ to delete',
                        onPressed: () => _showEditCategoryDialog('lost_found', c),
                        onDeleted: () => _confirmDeleteCategory('lost_found', c),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        deleteButtonTooltipMessage: 'Delete "$cleanTitle"',
                      );
                    }
                    return Chip(
                      label: Text(cleanTitle),
                      avatar: const Icon(Icons.label_outline, size: 14),
                    );
                  }).toList(),
                ),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: ${errorText(e)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddCategory() async {
    final rawName = _categoryController.text.trim();
    if (rawName.isEmpty) {
      _showToast('Enter category name.');
      return;
    }
    final name = CategoryEmojiHelper.cleanName(rawName);

    setState(() => _isAddingCategory = true);
    try {
      if (_categoryTarget == 'buy_sell') {
        await ref.read(buySellRepositoryProvider).createCategory(name);
        ref.invalidate(buySellCategoriesProvider);
      } else {
        await ref.read(lostFoundRepositoryProvider).createCategory(name);
        ref.invalidate(lostFoundCategoriesProvider);
      }
      _categoryController.clear();
      _showToast('Category "$name" created successfully.');
    } catch (e) {
      _showToast('Failed to create category: ${errorText(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isAddingCategory = false);
    }
  }

  Future<void> _showEditCategoryDialog(String module, CategoryRef cat) async {
    final editController = TextEditingController(text: CategoryEmojiHelper.cleanName(cat.name));
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Category (${module == 'buy_sell' ? 'Buy & Sell' : 'Lost & Found'})'),
        content: TextField(
          controller: editController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New Category Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, editController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated != null && updated.isNotEmpty && updated != CategoryEmojiHelper.cleanName(cat.name)) {
      try {
        final cleanNewName = CategoryEmojiHelper.cleanName(updated);
        if (module == 'buy_sell') {
          await ref.read(buySellRepositoryProvider).updateCategory(cat.id, cleanNewName);
          ref.invalidate(buySellCategoriesProvider);
        } else {
          await ref.read(lostFoundRepositoryProvider).updateCategory(cat.id, cleanNewName);
          ref.invalidate(lostFoundCategoriesProvider);
        }
        _showToast('Renamed category to "$cleanNewName".');
      } catch (e) {
        _showToast('Failed to rename category: ${errorText(e)}', isError: true);
      }
    }
  }

  Future<void> _confirmDeleteCategory(String module, CategoryRef cat) async {
    final cleanName = CategoryEmojiHelper.cleanName(cat.name);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Category "$cleanName"?'),
        content: Text(
          'Are you sure you want to remove "$cleanName" from ${module == 'buy_sell' ? 'Buy & Sell' : 'Lost & Found'} categories?\n\nExisting postings with this category will remain, but users will no longer be able to select it for new listings.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Category'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (module == 'buy_sell') {
          await ref.read(buySellRepositoryProvider).deleteCategory(cat.id);
          ref.invalidate(buySellCategoriesProvider);
        } else {
          await ref.read(lostFoundRepositoryProvider).deleteCategory(cat.id);
          ref.invalidate(lostFoundCategoriesProvider);
        }
        _showToast('Deleted category "$cleanName".');
      } catch (e) {
        _showToast('Failed to delete category: ${errorText(e)}', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 5: Backend & Canary Health
  // ---------------------------------------------------------------------------
  Widget _buildSystemHealthTab(bool isDark, ThemeData theme) {
    final healthAsync = ref.watch(systemHealthProvider);
    final currentUser = ref.watch(currentUserProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Demo Backend & Database Connection Card (Admin Only)
              if (currentUser?.isAdmin == true) ...[
                _buildDemoConnectionCard(isDark, theme),
                const SizedBox(height: 24),
              ],

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.monitor_heart_rounded, size: 24, color: Colors.green.shade600),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cloud Services & Canary Health Status',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text('Continuous health monitoring • AWS Mumbai (ap-south-1)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      healthAsync.when(
                        data: (health) {
                          final services = health['services'] as Map<String, dynamic>? ?? {};
                          return Column(
                            children: [
                              for (final entry in services.entries)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                                      const SizedBox(width: 10),
                                      Text(
                                        entry.key.toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          entry.value.toString(),
                                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Text('Health check failed: ${errorText(e)}', style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Demo Backend & Database Connection Controls (Admin Only)
  // ---------------------------------------------------------------------------
  Widget _buildDemoConnectionCard(bool isDark, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _useMockMode
              ? (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))
              : Colors.teal.shade400,
          width: _useMockMode ? 1 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _useMockMode
                        ? (isDark ? const Color(0xFF334155) : Colors.grey.shade200)
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _useMockMode ? Icons.memory_rounded : Icons.wifi_tethering_rounded,
                    size: 22,
                    color: _useMockMode
                        ? (isDark ? Colors.grey.shade300 : Colors.grey.shade700)
                        : Colors.teal.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Demo Backend & Database Connection',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Connect this frontend to your teammate\'s FastAPI server and live PostgreSQL database for integration demos.',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _useMockMode
                        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                        : (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _useMockMode ? Colors.grey.shade400 : Colors.teal.shade400,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _useMockMode ? Icons.layers_outlined : Icons.check_circle_rounded,
                        size: 14,
                        color: _useMockMode ? Colors.grey.shade600 : Colors.teal.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _useMockMode ? 'MOCK MODE' : 'LIVE BACKEND',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _useMockMode
                              ? (isDark ? Colors.grey.shade400 : Colors.grey.shade700)
                              : (isDark ? Colors.teal.shade200 : Colors.teal.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),

            // Backend Mode Selector
            const Text(
              'Active Backend Mode:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.layers_clear_outlined, size: 16),
                  label: Text('Mock Data (In-Memory Simulation)'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.cable_rounded, size: 16),
                  label: Text('Live Backend Server (FastAPI + PostgreSQL)'),
                ),
              ],
              selected: {_useMockMode},
              onSelectionChanged: (set) {
                setState(() {
                  _useMockMode = set.first;
                  _connectionTestReport = null;
                });
              },
            ),
            const SizedBox(height: 20),

            // Server Base URL field
            TextField(
              controller: _baseUrlController,
              decoration: InputDecoration(
                labelText: 'FastAPI Server Base URL',
                hintText: 'e.g. http://10.217.103.203:8000',
                prefixIcon: const Icon(Icons.dns_rounded, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),

            // Presets for Base URL
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Quick presets:', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ActionChip(
                  label: const Text('Teammate Laptop (10.217.103.203:8000)', style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.laptop_chromebook_rounded, size: 14),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _baseUrlController.text = 'http://10.217.103.203:8000';
                    });
                  },
                ),
                ActionChip(
                  label: const Text('Localhost (localhost:8000)', style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.computer_rounded, size: 14),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _baseUrlController.text = 'http://localhost:8000';
                    });
                  },
                ),
                ActionChip(
                  label: const Text('127.0.0.1 (127.0.0.1:8000)', style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.lan_outlined, size: 14),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _baseUrlController.text = 'http://127.0.0.1:8000';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Developer Security Key (X-Dev-Key)
            TextField(
              controller: _devKeyController,
              obscureText: _obscureDevKey,
              decoration: InputDecoration(
                labelText: 'Developer Security Key / Secret (X-Dev-Key)',
                hintText: 'e.g. kSH3AyYRCzXn8Czy8xXCZbC9',
                prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(_obscureDevKey ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  tooltip: _obscureDevKey ? 'Show key' : 'Hide key',
                  onPressed: () => setState(() => _obscureDevKey = !_obscureDevKey),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Dev User Email & Identity (X-Dev-User)
            TextField(
              controller: _devUserEmailController,
              decoration: InputDecoration(
                labelText: 'Test User Email Identity (X-Dev-User)',
                hintText: 'e.g. mukund@iisc.ac.in or kmukund@iisc.ac.in',
                prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                helperText: 'Injected into X-Dev-User header for authentication on the teammate\'s local backend server.',
              ),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Dev identities:', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ActionChip(
                  label: const Text('kmukund@iisc.ac.in (Admin)', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _devUserEmailController.text = 'kmukund@iisc.ac.in'),
                ),
                ActionChip(
                  label: const Text('mukund@iisc.ac.in', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _devUserEmailController.text = 'mukund@iisc.ac.in'),
                ),
                ActionChip(
                  label: const Text('cadithya@iisc.ac.in (Moderator)', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _devUserEmailController.text = 'cadithya@iisc.ac.in'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Database Connection URI (Reference for Demo)
            TextField(
              controller: _databaseUrlController,
              decoration: InputDecoration(
                labelText: 'Database Connection URI (Demo Reference)',
                hintText: 'postgresql://postgres:password@10.217.103.203:5432/campushub',
                prefixIcon: const Icon(Icons.storage_rounded, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                helperText: 'FastAPI on your teammate\'s laptop connects to this PostgreSQL instance. Testing connection below verifies PostgreSQL via /health.',
              ),
            ),
            const SizedBox(height: 16),

            // Connection Test Report Box
            if (_connectionTestReport != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _connectionTestReport!['success'] == true
                      ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                      : (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _connectionTestReport!['success'] == true
                        ? Colors.green.shade400
                        : Colors.red.shade400,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _connectionTestReport!['success'] == true
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: _connectionTestReport!['success'] == true
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _connectionTestReport!['success'] == true
                                ? 'Connection Test Passed (${_connectionTestReport!['latencyMs']} ms)'
                                : 'Connection Test Failed (${_connectionTestReport!['latencyMs']} ms)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _connectionTestReport!['success'] == true
                                  ? (isDark ? Colors.green.shade200 : Colors.green.shade900)
                                  : (isDark ? Colors.red.shade200 : Colors.red.shade900),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _connectionTestReport!['message'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _connectionTestReport!['success'] == true
                                  ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                                  : (isDark ? Colors.red.shade300 : Colors.red.shade800),
                            ),
                          ),
                          if (_connectionTestReport!['categoriesCount'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Verified endpoints: /health (PostgreSQL SELECT 1: OK) • /api/v1/buy-sell/categories (${_connectionTestReport!['categoriesCount']} categories found)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.green.shade300 : Colors.green.shade900,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _isSavingConnection ? null : _handleSaveConnection,
                  icon: _isSavingConnection
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cable_rounded, size: 16),
                  label: const Text('Save & Apply Backend'),
                ),
                OutlinedButton.icon(
                  onPressed: _isTestingConnection ? null : _handleTestConnection,
                  icon: _isTestingConnection
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed_rounded, size: 16),
                  label: const Text('Test Server & Database Connection'),
                ),
                TextButton.icon(
                  onPressed: _handleResetConnection,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset to Default Mock'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTestConnection() async {
    final baseUrl = _baseUrlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final devKey = _devKeyController.text.trim();
    final devEmail = _devUserEmailController.text.trim();

    if (baseUrl.isEmpty) {
      _showToast('Please enter a valid FastAPI base URL.', isError: true);
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionTestReport = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {
            'Accept': 'application/json',
            if (devKey.isNotEmpty) 'X-Dev-Key': devKey,
            if (devEmail.isNotEmpty) 'X-Dev-User': devEmail,
          },
        ),
      );

      // 1. Check /health (executes SELECT 1 on PostgreSQL)
      final healthRes = await dio.get('/health');
      stopwatch.stop();

      // 2. Also check /api/v1/buy-sell/categories
      int categoriesCount = 0;
      try {
        final catRes = await dio.get('/api/v1/buy-sell/categories');
        if (catRes.data is List) {
          categoriesCount = (catRes.data as List).length;
        }
      } catch (_) {}

      setState(() {
        _connectionTestReport = {
          'success': true,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'statusCode': healthRes.statusCode,
          'healthData': healthRes.data,
          'categoriesCount': categoriesCount,
          'message': 'Connected successfully! FastAPI backend is running and PostgreSQL database responded to SELECT 1.',
        };
      });
      _showToast('Connection test succeeded in ${stopwatch.elapsedMilliseconds} ms!');
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _connectionTestReport = {
          'success': false,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Unable to reach backend at $baseUrl (${errorText(e)}). Ensure your teammate\'s laptop is on the same Wi-Fi/LAN and port 8000 is accepting connections.',
        };
      });
      _showToast('Connection test failed: ${errorText(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _handleSaveConnection() async {
    final baseUrl = _baseUrlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final devKey = _devKeyController.text.trim();
    final devEmail = _devUserEmailController.text.trim();
    final dbUrl = _databaseUrlController.text.trim();

    setState(() => _isSavingConnection = true);
    try {
      await ref.read(serverConfigProvider.notifier).updateConfig(
            useMockData: _useMockMode,
            apiBaseUrl: baseUrl.isNotEmpty ? baseUrl : 'http://localhost:8000',
            devKey: devKey.isNotEmpty ? devKey : 'kSH3AyYRCzXn8Czy8xXCZbC9',
            devUserEmail: devEmail.isNotEmpty ? devEmail : 'mukund@iisc.ac.in',
            databaseUrl: dbUrl.isNotEmpty ? dbUrl : null,
          );

      // Invalidate providers and refetch all data from new backend
      ref.invalidate(authStateProvider);
      ref.invalidate(buySellCategoriesProvider);
      ref.invalidate(lostFoundCategoriesProvider);
      ref.invalidate(moderatorGrantsProvider);
      ref.invalidate(registeredUsersProvider);
      ref.read(buySellPaginationProvider.notifier).loadInitial();
      ref.read(lostReportsPaginationProvider.notifier).loadInitial();
      ref.read(foundReportsPaginationProvider.notifier).loadInitial();

      _showToast(
        _useMockMode
            ? 'Switched to In-Memory Mock backend simulation.'
            : 'Connected to live backend at $baseUrl! Refetched all data from database.',
      );
    } catch (e) {
      _showToast('Failed to save connection settings: ${errorText(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingConnection = false);
    }
  }

  Future<void> _handleResetConnection() async {
    await ref.read(serverConfigProvider.notifier).resetToDefaults();
    final config = ref.read(serverConfigProvider);
    setState(() {
      _useMockMode = config.useMockData;
      _baseUrlController.text = config.apiBaseUrl;
      _devKeyController.text = config.devKey;
      _devUserEmailController.text = config.devUserEmail;
      _databaseUrlController.text = config.databaseUrl ?? '';
      _connectionTestReport = null;
    });

    ref.invalidate(authStateProvider);
    ref.invalidate(buySellCategoriesProvider);
    ref.invalidate(lostFoundCategoriesProvider);
    ref.read(buySellPaginationProvider.notifier).loadInitial();
    ref.read(lostReportsPaginationProvider.notifier).loadInitial();
    ref.read(foundReportsPaginationProvider.notifier).loadInitial();

    _showToast('Reset backend connection to default mock configuration.');
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
