import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/academics_models.dart';
import '../providers/academics_providers.dart';

/// Courses tab: pick a department, find a course, open its survival guide — or see just the ones
/// you follow (the "Following" chip), instead of having to open each course to check.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String _search = '';
  bool _showFollowing = false;

  @override
  Widget build(BuildContext context) {
    final departmentsAsync = ref.watch(departmentsProvider);
    final selectedId = ref.watch(selectedDepartmentIdProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isGuest = ref.watch(isGuestUserProvider);

    return departmentsAsync.when(
      loading: () => const SkeletonList(itemCount: 6),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (departments) {
        if (departments.isEmpty) {
          return const Center(child: Text('No departments yet.'));
        }
        final withCourses = departments.where((d) => d.courseCount > 0).toList();
        final shown = withCourses.isEmpty ? departments : withCourses;
        final busiest = shown.reduce((a, b) => b.courseCount > a.courseCount ? b : a);
        final department = shown.firstWhere((d) => d.id == selectedId, orElse: () => busiest);
        final coursesAsync = ref.watch(departmentCoursesProvider(department.id));

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                color: theme.cardColor,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Course survival guides',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('What past students said about each course, semester by semester.',
                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (!isGuest)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                avatar: Icon(Icons.bookmark_rounded,
                                    size: 16, color: _showFollowing ? null : theme.colorScheme.primary),
                                label: const Text('Following'),
                                selected: _showFollowing,
                                visualDensity: VisualDensity.compact,
                                onSelected: (v) => setState(() => _showFollowing = v),
                              ),
                            ),
                          for (final d in shown)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${d.name} (${d.courseCount})'),
                                selected: !_showFollowing && d.id == department.id,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => setState(() {
                                  _showFollowing = false;
                                  ref.read(selectedDepartmentIdProvider.notifier).state = d.id;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: Border(
                    bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Search all departments by code or name, e.g. DS252',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
            ),
            // Following shows just the courses you follow; typing searches every department;
            // otherwise the picked department is listed.
            (_showFollowing
                    ? ref.watch(followingCoursesProvider).whenData(
                        (cs) => _search.isEmpty ? cs : cs.where((c) => courseMatches(c, _search)).toList())
                    : _search.isNotEmpty
                        ? ref.watch(allCoursesProvider).whenData((all) => all.where((c) => courseMatches(c, _search)).toList())
                        : coursesAsync.whenData((cs) => [for (final c in cs) (course: c, departmentName: department.name)]))
                .when(
              loading: () => const SliverToBoxAdapter(child: SkeletonList(itemCount: 6)),
              error: (e, _) => SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(errorText(e)),
              )),
              data: (filtered) {
                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(_showFollowing
                          ? "You're not following any courses yet. Open a course and tap Follow to get updates here."
                          : 'No courses match.'),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 108,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _CourseTile(
                        course: filtered[i].course,
                        departmentName: (_search.isNotEmpty || _showFollowing) ? filtered[i].departmentName : null,
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _CourseTile extends StatelessWidget {
  final Course course;

  /// Shown when the tile comes from a search across departments.
  final String? departmentName;

  const _CourseTile({required this.course, this.departmentName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        // go() (not push()) so the browser URL actually changes to /courses/:id —
        // push() only updates go_router's internal imperative stack, so a reload
        // would land back on the course list instead of this detail page.
        onTap: () => context.go('/courses/${course.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(course.code,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    const SizedBox(height: 2),
                    Text(course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (departmentName != null) departmentName!,
                        course.feedbackCount == 0 ? 'No feedback yet' : '${course.feedbackCount} reviews',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
