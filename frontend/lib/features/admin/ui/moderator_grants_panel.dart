import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/validators.dart';
import '../../academics/domain/academics_models.dart';
import '../../academics/providers/academics_providers.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/admin_providers.dart';

const moduleLabels = {
  'buy_sell': 'Buy & Sell',
  'lost_found': 'Lost & Found',
  'academic_help': 'Academic Help',
  'placement_hub': 'Placement Hub',
  'events': 'Events',
};

/// The modules an admin can appoint moderators for. Academic Help is appointed per department or per
/// course, so the admin also picks the scope (see _level).
const _appointableModules = ['buy_sell', 'lost_found', 'academic_help', 'placement_hub', 'events'];

/// Grant and revoke moderator roles (FR-3), by the rules the API enforces:
/// - the admin grants module-wide roles for Buy & Sell, Lost & Found, Placement Hub and Events, and
///   department or course roles for Academic Help;
/// - a department moderator grants and revokes course moderators for courses in their department.
/// The person must have signed in to CampusHub once, so their account exists.
class ModeratorGrantsPanel extends ConsumerStatefulWidget {
  const ModeratorGrantsPanel({super.key});

  @override
  ConsumerState<ModeratorGrantsPanel> createState() => _ModeratorGrantsPanelState();
}

class _ModeratorGrantsPanelState extends ConsumerState<ModeratorGrantsPanel> {
  final _emailController = TextEditingController();
  String _module = 'buy_sell';
  String _level = 'department'; // Academic Help only: department or course
  String? _departmentId;
  String? _courseId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _grant(User me) async {
    final email = _emailController.text.trim();
    final module = me.isAdmin ? _module : 'academic_help';
    final level = me.isAdmin ? _level : 'course';
    String? problem;
    if (!isIiscEmail(email)) {
      problem = 'Enter their IISc email address.';
    } else if (module == 'academic_help' && _departmentId == null) {
      problem = 'Pick a department.';
    } else if (module == 'academic_help' && level == 'course' && _courseId == null) {
      problem = 'Pick a course.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final isAcademic = module == 'academic_help';
      await ref.read(adminRepositoryProvider).grantModerator(
            email: email,
            module: module,
            scopeType: isAcademic ? level : 'module',
            departmentId: isAcademic && level == 'department' ? _departmentId : null,
            courseId: isAcademic && level == 'course' ? _courseId : null,
          );
      _emailController.clear();
      ref.invalidate(moderatorGrantsProvider);
      _toast('$email is now a moderator.');
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revoke(ModeratorGrant grant, String scope) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this moderator role?'),
        content: Text('${grant.userName ?? grant.userEmail} will no longer moderate $scope.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove role'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepositoryProvider).revokeModerator(grant.id);
      ref.invalidate(moderatorGrantsProvider);
      _toast('Role removed.');
    } catch (e) {
      _toast(errorText(e), error: true);
    }
  }

  /// "Buy & Sell", "Academic Help · Computational and Data Sciences", "Academic Help · DS 252".
  String _scope(ModeratorGrant g, List<Department> departments, List<CourseWithDepartment> courses) {
    final module = moduleLabels[g.module] ?? g.module;
    if (g.courseId != null) {
      final c = courses.where((c) => c.course.id == g.courseId);
      return '$module · ${c.isEmpty ? 'a course' : '${c.first.course.code} ${c.first.course.name}'}';
    }
    if (g.departmentId != null) {
      final d = departments.where((d) => d.id == g.departmentId);
      return '$module · ${d.isEmpty ? 'a department' : d.first.name}';
    }
    return module;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    if (me == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    final allCourses = ref.watch(allCoursesProvider).valueOrNull ?? const <CourseWithDepartment>[];
    // A department moderator may only pick their own departments.
    final myDepartmentIds = {
      for (final g in me.moderatorGrants)
        if (g.module == 'academic_help' && g.scopeType == 'department' && g.departmentId != null) g.departmentId!,
    };
    final pickableDepartments =
        me.isAdmin ? departments : departments.where((d) => myDepartmentIds.contains(d.id)).toList();
    final isAcademic = !me.isAdmin || _module == 'academic_help';
    final showCourse = !me.isAdmin || _level == 'course';
    final coursesInDepartment = _departmentId == null
        ? const <CourseWithDepartment>[]
        : allCourses.where((c) => c.course.departmentId == _departmentId).toList();
    final grantsAsync = ref.watch(moderatorGrantsProvider);

    InputDecoration box(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.isAdmin ? 'Appoint a moderator' : 'Appoint a course moderator',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          me.isAdmin
                              ? 'Buy & Sell, Lost & Found, Placement Hub and Events moderators cover the whole module: '
                                  'they handle its reports and can remove anyone\'s posts there. Placement Hub moderators '
                                  'also add companies, dates and placement sheets; Events moderators manage event tags. '
                                  'Academic Help moderators cover one department (all its courses) or one course: they can '
                                  'remove its materials, feedback and forum posts. Removing these creates no seller strike. '
                                  'The person must have signed in to CampusHub once.'
                              : 'As a department moderator you can appoint moderators for courses in your department. '
                                  'The person must have signed in to CampusHub once.',
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: box('Their IISc email').copyWith(
                            prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (me.isAdmin)
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _module,
                                  decoration: box('Module'),
                                  items: [
                                    for (final m in _appointableModules)
                                      DropdownMenuItem(value: m, child: Text(moduleLabels[m]!)),
                                  ],
                                  onChanged: (v) => setState(() => _module = v ?? _module),
                                ),
                              ),
                            if (me.isAdmin && isAcademic)
                              SizedBox(
                                width: 200,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _level,
                                  decoration: box('Covers'),
                                  items: const [
                                    DropdownMenuItem(value: 'department', child: Text('A whole department')),
                                    DropdownMenuItem(value: 'course', child: Text('One course')),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _level = v ?? _level;
                                    _courseId = null;
                                  }),
                                ),
                              ),
                            if (isAcademic)
                              SizedBox(
                                width: 320,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _departmentId,
                                  isExpanded: true,
                                  decoration: box('Department'),
                                  items: [
                                    for (final d in pickableDepartments)
                                      DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _departmentId = v;
                                    _courseId = null;
                                  }),
                                ),
                              ),
                            if (isAcademic && showCourse)
                              SizedBox(
                                width: 320,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(_departmentId),
                                  initialValue: _courseId,
                                  isExpanded: true,
                                  decoration: box(_departmentId == null ? 'Course (pick a department first)' : 'Course'),
                                  items: [
                                    for (final c in coursesInDepartment)
                                      DropdownMenuItem(
                                        value: c.course.id,
                                        child: Text('${c.course.code} · ${c.course.name}', overflow: TextOverflow.ellipsis),
                                      ),
                                  ],
                                  onChanged: _departmentId == null ? null : (v) => setState(() => _courseId = v),
                                ),
                              ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                        ],
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : () => _grant(me),
                            icon: _saving
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('Appoint'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(me.isAdmin ? 'Active moderators' : 'Course moderators in your department',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                grantsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(errorText(e), style: TextStyle(color: theme.colorScheme.error)),
                  data: (grants) {
                    if (grants.isEmpty) {
                      return Text('No moderators yet.', style: TextStyle(color: theme.hintColor));
                    }
                    return Column(
                      children: [
                        for (final g in grants)
                          Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.shield_outlined),
                              title: Text(g.userName ?? g.userEmail ?? 'Moderator',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${_scope(g, departments, allCourses)}\n'
                                '${g.userEmail ?? ''} · appointed ${DateTimeFormatter.timeAgo(g.grantedAt)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              isThreeLine: true,
                              trailing: TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                                onPressed: () => _revoke(g, _scope(g, departments, allCourses)),
                                icon: const Icon(Icons.remove_circle_outline, size: 16),
                                label: const Text('Remove'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
