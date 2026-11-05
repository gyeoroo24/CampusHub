import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/utils/error_text.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/category_ref.dart';
import '../../../core/utils/category_emoji_helper.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../academics/domain/academics_models.dart';
import '../../academics/ui/course_materials.dart' show CourseMaterial, formatBytes;
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../../campus_services/ui/campus_services_admin_panel.dart';
import '../../forums/providers/forum_providers.dart';
import '../../lost_found/domain/lost_found_item.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../../lost_found/ui/widgets/lost_found_detail_dialog.dart';
import '../../placement/providers/placement_providers.dart';
import '../../seller_trust/domain/seller_strike.dart';
import '../../seller_trust/providers/seller_trust_providers.dart';
import '../../wanted/providers/wanted_providers.dart';
import '../../wanted/ui/wanted_detail_dialog.dart';
import '../domain/content_report.dart';
import '../providers/admin_providers.dart';
import 'moderator_grants_panel.dart';

/// The panel's tabs. The admin sees all of them; a moderator sees only the ones they can use.
enum _PanelTab { moderators, users, reports, sellerStrikes, categories, campusServices }

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
            if (user != null && user.canModerateBuySell) _PanelTab.sellerStrikes,
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

  }

  @override
  void dispose() {
    _tabController.dispose();
    _userEmailController.dispose();
    _categoryController.dispose();
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
        _PanelTab.sellerStrikes => const Tab(icon: Icon(Icons.gavel_outlined, size: 18), text: 'Seller Strikes'),
        _PanelTab.categories => const Tab(icon: Icon(Icons.category_outlined, size: 18), text: 'Categories'),
        _PanelTab.campusServices =>
          const Tab(icon: Icon(Icons.health_and_safety_outlined, size: 18), text: 'Campus Services'),
      };

  Widget _viewFor(_PanelTab tab, bool isDark, ThemeData theme, User user) => switch (tab) {
        _PanelTab.moderators => const ModeratorGrantsPanel(),
        _PanelTab.users => _buildUsersTab(isDark, theme),
        _PanelTab.reports => _buildReportsQueueTab(isDark, theme),
        _PanelTab.sellerStrikes => _buildSellerStrikesTab(isDark, theme),
        _PanelTab.categories => _buildCategoriesTab(isDark, theme),
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
                                  if (r.source == 'system') ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Flagged automatically, not by a person',
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('AUTO',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${_moduleLabel(r.module)} • ${r.targetTitle ?? r.targetType}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                                        onPressed: () => _handleResolveReport(r, action: 'dismissed', removeContent: false),
                                        child: const Text('Dismiss Flag'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _handleResolveReport(r, action: 'actioned', removeContent: false),
                                        child: const Text('Action (Keep Content)'),
                                      ),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                                        label: const Text('Action & Soft-Delete'),
                                        onPressed: () => _handleResolveReport(r, action: 'actioned', removeContent: true),
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

  static String _moduleLabel(String module) => switch (module) {
        'buy_sell' => 'BUY & SELL',
        'lost_found' => 'LOST & FOUND',
        'academic_help' => 'ACADEMIC HELP',
        'placement_hub' => 'PLACEMENT HUB',
        _ => module.toUpperCase(),
      };

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
        case 'wanted_post':
          final post = await ref.read(wantedRepositoryProvider).getWanted(r.targetId);
          if (!mounted) return;
          if (post == null) throw Exception('This Wanted post has been removed.');
          await showDialog(context: context, builder: (_) => WantedDetailDialog(post: post));
        case 'course_feedback':
          final response = await ref.read(apiClientProvider).get(ApiEndpoints.feedback(r.targetId));
          final feedback = CourseFeedback.fromJson(response.data as Map<String, dynamic>);
          if (!mounted) return;
          await _showContentPreview(
            title: 'Course review',
            author: feedback.authorName ?? (feedback.isAnonymous ? 'Anonymous' : null),
            when: feedback.createdAt,
            body: feedback.content,
          );
        case 'course_material':
          final response = await ref.read(apiClientProvider).get(ApiEndpoints.material(r.targetId));
          final material = CourseMaterial.fromJson(response.data as Map<String, dynamic>);
          if (!mounted) return;
          await _showContentPreview(
            title: 'Course material',
            author: material.uploaderName,
            when: material.createdAt,
            body: material.description?.trim().isNotEmpty == true ? material.description! : '(No description.)',
            subtitle: '${material.title} · ${material.kindLabel}'
                '${material.sizeBytes != null ? " · ${formatBytes(material.sizeBytes)}" : ""}',
          );
        case 'thread':
          final thread = await ref.read(forumRepositoryProvider).getThread(r.targetId);
          if (!mounted) return;
          await _showContentPreview(
            title: 'Forum thread',
            author: thread.authorName,
            when: thread.createdAt,
            body: thread.openingPost?.content ?? '(No opening post.)',
            subtitle: thread.title,
          );
        case 'comment':
          final found = await ref.read(forumRepositoryProvider).getComment(r.targetId);
          if (!mounted) return;
          await _showContentPreview(
            title: 'Forum comment',
            author: found.comment.authorName,
            when: found.comment.createdAt,
            body: found.comment.content ?? '(This comment was removed.)',
            subtitle: 'In thread: ${found.threadTitle}',
          );
        case 'interview_experience':
          final interview = await ref.read(placementRepositoryProvider).getInterview(r.targetId);
          if (!mounted) return;
          await _showContentPreview(
            title: 'Interview experience',
            author: interview.authorName ?? (interview.isAnonymous ? 'Anonymous' : null),
            when: interview.createdAt,
            body: interview.content,
            subtitle: [interview.companyName, if (interview.roleTitle != null) interview.roleTitle!].join(' · '),
          );
        default:
          messenger.showSnackBar(SnackBar(
            content: Text('Opening "${r.targetType}" content isn\'t supported yet.'),
            behavior: SnackBarBehavior.floating,
          ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
    } finally {
      // The owner may have edited or deleted the post from its dialog (deleting it removes its reports),
      // so reload the queue.
      if (mounted) ref.invalidate(contentReportsProvider);
    }
  }

  /// A read-only look at reported content that has no detail dialog of its own (course feedback and
  /// materials, forum threads and comments, interview experiences): just enough for the moderator to
  /// judge the report, not the full editing UI those content types have on their own pages.
  Future<void> _showContentPreview({
    required String title,
    String? author,
    required DateTime when,
    required String body,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                ],
                Text('${author ?? 'Unknown'} · ${DateTimeFormatter.fullDateTime(when)}',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
                const SizedBox(height: 12),
                SelectableText(body),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _handleResolveReport(ContentReport r, {required String action, required bool removeContent}) async {
    final noteController = TextEditingController();
    // Removing a listing needs a severity call for the seller trust score (future plan §1.5):
    // severe (illegal item) blocks the seller immediately; non-severe builds toward a strike ladder.
    final needsSeverity = removeContent && r.targetType == 'listing';
    String severity = 'non_severe';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Resolve Content Report ($action)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(removeContent
                  ? 'Resolving with action=actioned will soft-delete the reported content from the campus feeds.'
                  : 'Closing report as $action.'),
              if (needsSeverity) ...[
                const SizedBox(height: 12),
                const Text('Seller trust severity (future plan §1.5):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                _SeverityOption(
                  title: 'Non-severe — builds toward the strike ladder',
                  subtitle: 'Prohibited-but-not-dangerous, scammy, duplicate, misleading',
                  selected: severity == 'non_severe',
                  onTap: () => setDialogState(() => severity = 'non_severe'),
                ),
                _SeverityOption(
                  title: 'Severe — blocks the seller immediately',
                  subtitle: 'Illegal items: drugs, weapons, anything law-enforcement-relevant',
                  selected: severity == 'severe',
                  onTap: () => setDialogState(() => severity = 'severe'),
                ),
              ],
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
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(adminRepositoryProvider).resolveReport(
              r.id,
              action: action,
              note: noteController.text.trim(),
              removeContent: removeContent,
              severity: needsSeverity ? severity : null,
            );
        ref.invalidate(contentReportsProvider);
        _showToast('Report marked as $action.');
      } catch (e) {
        _showToast('Failed to resolve report: ${errorText(e)}', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TAB: Seller Strikes (future plan §1.5) - the contested-appeal queue, plus the full history.
  // ---------------------------------------------------------------------------
  Widget _buildSellerStrikesTab(bool isDark, ThemeData theme) {
    final strikesAsync = ref.watch(moderatedSellerStrikesProvider);
    final filter = ref.watch(sellerStrikesFilterProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Appeal:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  for (final f in const ['pending', 'resolved', 'all']) ...[
                    ChoiceChip(
                      label: Text(f.toUpperCase()),
                      selected: filter == f,
                      onSelected: (sel) {
                        if (sel) ref.read(sellerStrikesFilterProvider.notifier).state = f;
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                filter == 'pending'
                    ? 'Strikes a seller has contested that nobody has reviewed yet.'
                    : 'Every strike matching this filter, newest first.',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
              const SizedBox(height: 16),
              strikesAsync.when(
                data: (strikes) {
                  if (strikes.isEmpty) {
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
                          Text(
                            filter == 'pending' ? 'No strikes need your attention.' : 'Nothing in this view.',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: strikes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) => _SellerStrikeCard(strike: strikes[idx], isDark: isDark),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading strikes: ${errorText(e)}', style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
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
                  Flexible(
                    child: Text(
                      canManageBuySell ? '(tap chip to rename, ✕ to delete)' : '(read-only for non-moderators)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                    ),
                  ),
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
                  Flexible(
                    child: Text(
                      canManageLostFound ? '(tap chip to rename, ✕ to delete)' : '(read-only for non-moderators)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                    ),
                  ),
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
    final isBuySell = module == 'buy_sell';
    final others = ((isBuySell ? ref.read(buySellCategoriesProvider) : ref.read(lostFoundCategoriesProvider))
                .valueOrNull ??
            const <CategoryRef>[])
        .where((c) => c.id != cat.id)
        .toList();
    int? moveTo;
    // Posts can't be left without a category: if any use this one, the server asks where to move
    // them (409), so the moderator picks a destination here up front.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Delete Category "$cleanName"?'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"$cleanName" will be removed from ${isBuySell ? 'Buy & Sell' : 'Lost & Found'} categories. '
                    'If any posts or saved searches use it, they are moved to the category you pick below.'),
                const SizedBox(height: 14),
                DropdownButtonFormField<int?>(
                  initialValue: moveTo,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(
                    labelText: 'Move its posts to',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— Only if nothing uses it —')),
                    for (final c in others)
                      DropdownMenuItem<int?>(value: c.id, child: Text(CategoryEmojiHelper.cleanName(c.name))),
                  ],
                  onChanged: (v) => setDialogState(() => moveTo = v),
                ),
              ],
            ),
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
      ),
    );

    if (confirm == true) {
      try {
        if (isBuySell) {
          await ref.read(buySellRepositoryProvider).deleteCategory(cat.id, moveTo: moveTo);
          ref.invalidate(buySellCategoriesProvider);
        } else {
          await ref.read(lostFoundRepositoryProvider).deleteCategory(cat.id, moveTo: moveTo);
          ref.invalidate(lostFoundCategoriesProvider);
        }
        _showToast(moveTo == null
            ? 'Deleted category "$cleanName".'
            : 'Deleted "$cleanName" and moved its posts to '
                '"${CategoryEmojiHelper.cleanName(others.firstWhere((c) => c.id == moveTo).name)}".');
      } catch (e) {
        _showToast('Could not delete "$cleanName": ${errorText(e)}', isError: true);
      }
    }
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

/// A tappable severity choice for the seller-trust strike dialog, in place of the deprecated
/// RadioListTile group-value API.
class _SeverityOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SeverityOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18, color: selected ? primary : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One strike in the moderator's Seller Strikes tab: what was removed, the seller's appeal if
/// any, and the two actions that resolve it (future plan §1.5).
class _SellerStrikeCard extends ConsumerStatefulWidget {
  final SellerStrike strike;
  final bool isDark;
  const _SellerStrikeCard({required this.strike, required this.isDark});

  @override
  ConsumerState<_SellerStrikeCard> createState() => _SellerStrikeCardState();
}

class _SellerStrikeCardState extends ConsumerState<_SellerStrikeCard> {
  bool _isBusy = false;

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isBusy = true);
    try {
      await action();
      ref.invalidate(moderatedSellerStrikesProvider);
      messenger.showSnackBar(SnackBar(content: Text(successMessage), behavior: SnackBarBehavior.floating));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed: ${errorText(e)}'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openListing() async {
    final messenger = ScaffoldMessenger.of(context);
    final listingId = widget.strike.listingId;
    if (listingId == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('The seller deleted this listing.'), behavior: SnackBarBehavior.floating));
      return;
    }
    try {
      final item = await ref.read(buySellRepositoryProvider).getListingById(listingId);
      if (!mounted) return;
      if (item == null) throw Exception('This listing could not be found.');
      await showDialog(context: context, builder: (_) => BuySellDetailDialog(item: item));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
    }
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.strike;
    final theme = Theme.of(context);
    final severityColor = s.isSevere ? Colors.red.shade700 : Colors.orange.shade800;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _openListing,
                    child: Text(s.listingTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14, decoration: TextDecoration.underline)),
                  ),
                ),
                Text(DateTimeFormatter.timeAgo(s.createdAt), style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Seller: ${s.seller.name}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(s.isSevere ? 'Severe' : 'Non-severe', severityColor),
                if (s.listingHidden) _chip('Listing hidden', Colors.grey.shade700),
                if (s.excluded) _chip('Overturned', Colors.green.shade700),
              ],
            ),
            if (s.moderatorNote != null && s.moderatorNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Moderator note: ${s.moderatorNote}', style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ],
            if (s.appealMessage != null) ...[
              const Divider(height: 20),
              Text("Seller's appeal:",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.hintColor)),
              const SizedBox(height: 2),
              Text(s.appealMessage!, style: const TextStyle(fontSize: 13)),
            ],
            if (!s.excluded) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (s.appealStatus == AppealStatus.pending)
                      OutlinedButton(
                        onPressed: _isBusy
                            ? null
                            : () => _run(() => ref.read(sellerTrustRepositoryProvider).rejectAppeal(s.id),
                                'Appeal rejected; the strike stands.'),
                        child: const Text('Reject appeal'),
                      ),
                    FilledButton.icon(
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Overturn (restore listing)'),
                      onPressed: _isBusy
                          ? null
                          : () => _run(() => ref.read(sellerTrustRepositoryProvider).overturnStrike(s.id),
                              'Strike overturned; the listing is visible again.'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
