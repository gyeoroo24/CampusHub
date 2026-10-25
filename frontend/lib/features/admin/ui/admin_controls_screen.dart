import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../campus_services/ui/campus_services_admin_panel.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../providers/admin_providers.dart';

class AdminControlsScreen extends ConsumerStatefulWidget {
  const AdminControlsScreen({super.key});

  @override
  ConsumerState<AdminControlsScreen> createState() => _AdminControlsScreenState();
}

class _AdminControlsScreenState extends ConsumerState<AdminControlsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Promote moderator form
  final _modEmailController = TextEditingController();
  String _selectedModule = 'buy_sell';
  String _selectedScope = 'module';
  bool _isPromotingMod = false;

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
    final user = ref.read(currentUserProvider);
    final initialIndex = (user != null && !user.isAdmin && user.isModerator) ? 2 : 0;
    _tabController = TabController(length: 6, vsync: this, initialIndex: initialIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _modEmailController.dispose();
    _userEmailController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    // Security Gate: Admin or Moderator
    if (currentUser == null || (!currentUser.isAdmin && !currentUser.isModerator)) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/app'),
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
                      onPressed: () => context.go('/app'),
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
              context.go('/app');
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentUser.isAdmin ? 'Admin Controls & Governance' : 'Moderator Controls & Reports',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  currentUser.isAdmin
                      ? 'Single-Admin Architecture • PRD §3.1 & FR-3'
                      : 'Module Moderation • PRD §3.1 & FR-10',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.shield_outlined, size: 18), text: 'Moderators (FR-3)'),
            Tab(icon: Icon(Icons.manage_accounts_outlined, size: 18), text: 'User Accounts'),
            Tab(icon: Icon(Icons.report_gmailerrorred_rounded, size: 18), text: 'Reports Queue (FR-10)'),
            Tab(icon: Icon(Icons.category_outlined, size: 18), text: 'Categories'),
            Tab(icon: Icon(Icons.dns_outlined, size: 18), text: 'System & Health'),
            Tab(icon: Icon(Icons.health_and_safety_outlined, size: 18), text: 'Campus Services'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildModeratorsTab(isDark, theme),
          _buildUsersTab(isDark, theme),
          _buildReportsQueueTab(isDark, theme),
          _buildCategoriesTab(isDark, theme),
          _buildSystemHealthTab(isDark, theme),
          CampusServicesAdminPanel(isAdmin: currentUser.isAdmin),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: Roles & Moderators (FR-3)
  // ---------------------------------------------------------------------------
  Widget _buildModeratorsTab(bool isDark, ThemeData theme) {
    final grantsAsync = ref.watch(moderatorGrantsProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isUserAdmin = currentUser?.isAdmin ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Promote form card (Admin only) or Informative card (Moderator)
              if (isUserAdmin)
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
                            Icon(Icons.person_add_alt_1_rounded, size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text(
                              'Promote User to Moderator by IISc Email',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Admins can grant module-scoped review authority to any IISc student or faculty by their email address.',
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _modEmailController,
                          decoration: InputDecoration(
                            labelText: 'IISc Email Address',
                            hintText: 'e.g. cadithya@iisc.ac.in',
                            prefixIcon: const Icon(Icons.email_outlined, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedModule,
                                decoration: InputDecoration(
                                  labelText: 'Target Module',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'buy_sell', child: Text('Buy & Sell')),
                                  DropdownMenuItem(value: 'lost_found', child: Text('Lost & Found')),
                                  DropdownMenuItem(value: 'academic_help', child: Text('Academic Help')),
                                  DropdownMenuItem(value: 'placement_hub', child: Text('Placement Hub')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedModule = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedScope,
                                decoration: InputDecoration(
                                  labelText: 'Scope Type',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'module', child: Text('Module-wide')),
                                  DropdownMenuItem(value: 'department', child: Text('Department-scoped')),
                                  DropdownMenuItem(value: 'course', child: Text('Course-scoped')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedScope = val);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _isPromotingMod ? null : _handlePromoteModerator,
                            icon: _isPromotingMod
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('Promote to Moderator'),
                          ),
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
                    side: BorderSide(color: Colors.blue.shade200),
                  ),
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined, color: Colors.blue.shade700, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Moderator View: Only the Administrator can assign or demote moderators. To review and action reported content, switch to Reports Queue.',
                            style: TextStyle(fontSize: 13, color: isDark ? Colors.blue.shade200 : Colors.blue.shade900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () => _tabController.animateTo(2),
                          child: const Text('Reports Queue'),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),
              const Text(
                'Active Moderator Assignments',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              // Grants list
              grantsAsync.when(
                data: (grants) {
                  if (grants.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('No active moderator grants yet.'),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: grants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final grant = grants[idx];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Icon(Icons.security_rounded, color: Colors.blue.shade900, size: 20),
                          ),
                          title: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                grant.userName ?? grant.userEmail?.split('@').first ?? 'Moderator',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Text(
                                  grant.module.toUpperCase().replaceAll('_', ' '),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Email: ${grant.userEmail ?? "—"} • Scope: ${grant.scopeType} • Granted: ${DateTimeFormatter.timeAgo(grant.grantedAt)}',
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                          trailing: isUserAdmin
                              ? OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(color: Colors.red.shade300),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.remove_circle_outline, size: 14),
                                  label: const Text('Revoke / Demote', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _handleRevokeModerator(grant),
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading moderators: $e', style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handlePromoteModerator() async {
    final email = _modEmailController.text.trim();
    if (email.isEmpty) {
      _showToast('Please enter an IISc email address.');
      return;
    }
    setState(() => _isPromotingMod = true);
    try {
      await ref.read(adminRepositoryProvider).grantModerator(
            email: email,
            module: _selectedModule,
            scopeType: _selectedScope,
          );
      _modEmailController.clear();
      ref.invalidate(moderatorGrantsProvider);
      _showToast('Successfully granted moderator role to $email for $_selectedModule.');
    } catch (e) {
      _showToast('Failed to grant role: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPromotingMod = false);
    }
  }

  Future<void> _handleRevokeModerator(ModeratorGrant grant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Moderator Role?'),
        content: Text(
          'Are you sure you want to demote ${grant.userEmail} from their active moderator assignment in ${grant.module}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Demote / Revoke'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(adminRepositoryProvider).revokeModerator(grant.id);
        ref.invalidate(moderatorGrantsProvider);
        _showToast('Revoked moderator role for ${grant.userEmail}.');
      } catch (e) {
        _showToast('Error revoking role: $e', isError: true);
      }
    }
  }

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
                    onPressed: () => _tabController.animateTo(2),
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
                        'Under the single-admin model (PRD & backend), there is exactly one active administrator. Naming your successor will automatically downgrade your account to a standard student role in the same transaction.',
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
                error: (e, _) => Text('Error loading users: $e', style: const TextStyle(color: Colors.red)),
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
        if (mounted) context.go('/app');
      } catch (e) {
        _showToast('Transfer failed: $e', isError: true);
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
      _showToast('Failed to update status: $e', isError: true);
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isOpen ? Colors.orange.shade300 : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
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
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading reports: $e', style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
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
        _showToast('Failed to resolve report: $e', isError: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 4: Categories Governance
  // ---------------------------------------------------------------------------
  Widget _buildCategoriesTab(bool isDark, ThemeData theme) {
    final bsCategories = ref.watch(buySellCategoriesProvider);
    final lfCategories = ref.watch(lostFoundCategoriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        'Categories added here immediately populate the feed filter scrollbars and create-listing modals across the entire app.',
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
                            items: const [
                              DropdownMenuItem(value: 'buy_sell', child: Text('Buy & Sell')),
                              DropdownMenuItem(value: 'lost_found', child: Text('Lost & Found')),
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
              ),

              const SizedBox(height: 24),
              const Text('Active Buy & Sell Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              bsCategories.when(
                data: (cats) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cats
                      .map((c) => Chip(
                            label: Text(c.name),
                            avatar: const Icon(Icons.label_outline, size: 16),
                          ))
                      .toList(),
                ),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
              ),

              const SizedBox(height: 24),
              const Text('Active Lost & Found Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              lfCategories.when(
                data: (cats) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cats
                      .map((c) => Chip(
                            label: Text(c.name),
                            avatar: const Icon(Icons.label_outline, size: 16),
                          ))
                      .toList(),
                ),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddCategory() async {
    final name = _categoryController.text.trim();
    if (name.isEmpty) {
      _showToast('Enter category name.');
      return;
    }

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
      _showToast('Failed to create category: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isAddingCategory = false);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 5: System Telemetry & Canary Health
  // ---------------------------------------------------------------------------
  Widget _buildSystemHealthTab(bool isDark, ThemeData theme) {
    final healthAsync = ref.watch(systemHealthProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                              Text('Continuous monitoring (NFR-4) • AWS Mumbai (ap-south-1)', style: TextStyle(fontSize: 11, color: Colors.grey)),
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
                        error: (e, _) => Text('Health check failed: $e', style: const TextStyle(color: Colors.red)),
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
