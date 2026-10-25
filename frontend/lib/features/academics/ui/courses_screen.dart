import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../domain/academics_models.dart';
import '../providers/academics_providers.dart';

/// Courses tab: pick a department, find a course, open its survival guide.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final departmentsAsync = ref.watch(departmentsProvider);
    final selectedId = ref.watch(selectedDepartmentIdProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                          for (final d in shown)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${d.name} (${d.courseCount})'),
                                selected: d.id == department.id,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) => ref.read(selectedDepartmentIdProvider.notifier).state = d.id,
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
                    hintText: 'Find a course by code or name, e.g. DS 252',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
            ),
            coursesAsync.when(
              loading: () => const SliverToBoxAdapter(child: SkeletonList(itemCount: 6)),
              error: (e, _) => SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(errorText(e)),
              )),
              data: (courses) {
                final filtered = courses
                    .where((c) => _search.isEmpty || '${c.code} ${c.name}'.toLowerCase().contains(_search))
                    .toList();
                if (filtered.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No courses match.')),
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
                      (context, i) => _CourseTile(course: filtered[i]),
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

  const _CourseTile({required this.course});

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
        onTap: () => context.push('/courses/${course.id}'),
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
                      course.feedbackCount == 0 ? 'No feedback yet' : '${course.feedbackCount} reviews',
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
