import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/error_text.dart';
import '../../academics/providers/academics_providers.dart';
import '../../admin/providers/admin_providers.dart';
import '../../admin/ui/moderator_grants_panel.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';

/// "Your role" on the profile: the admin's tools, or each moderator role with its scope and a way
/// to step down. Students see nothing here.
class RoleCard extends ConsumerWidget {
  final User user;

  const RoleCard({super.key, required this.user});

  Future<void> _stepDown(BuildContext context, WidgetRef ref, ModeratorGrant grant, String scope) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Step down as moderator?'),
        content: Text('You will stop moderating $scope. The admin can appoint you again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Step down'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).revokeModerator(grant.id);
      await ref.read(authRepositoryProvider).getCurrentUser(); // refresh roles from the server
      ref.invalidate(moderatorGrantsProvider);
      messenger.showSnackBar(SnackBar(content: Text('You stepped down from $scope.'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700));
    }
  }

  String _scope(WidgetRef ref, ModeratorGrant g) {
    final module = moduleLabels[g.module] ?? g.module;
    if (g.courseId != null) {
      final courses = ref.watch(allCoursesProvider).valueOrNull ?? const [];
      final c = courses.where((c) => c.course.id == g.courseId);
      return '$module · ${c.isEmpty ? 'one course' : c.first.course.code}';
    }
    if (g.departmentId != null) {
      final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
      final d = departments.where((d) => d.id == g.departmentId);
      return '$module · ${d.isEmpty ? 'one department' : d.first.name}';
    }
    return module;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!user.isAdmin && user.moderatorGrants.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(user.isAdmin ? Icons.admin_panel_settings_outlined : Icons.shield_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(user.isAdmin ? 'Your role: Admin' : 'Your role: Moderator',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.push(user.controlsPath),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(user.isAdmin ? 'Admin panel' : 'Moderation tools'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (user.isAdmin)
              Text(
                'You manage moderators, accounts, categories and campus services. CampusHub has exactly one admin: '
                'to leave the role, hand it over to someone else from the admin panel (User Accounts).',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            for (final g in user.moderatorGrants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.verified_user_outlined, size: 20),
                title: Text(_scope(ref, g), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  g.module == 'academic_help'
                      ? (g.courseId != null
                          ? 'You manage this course\'s materials and remove its feedback.'
                          : 'You manage this department\'s courses, materials, feedback and course moderators.')
                      : 'You remove posts that break the rules and handle reports in this module.',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: () => _stepDown(context, ref, g, _scope(ref, g)),
                  child: const Text('Step down'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
