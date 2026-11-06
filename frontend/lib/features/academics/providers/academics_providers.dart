import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/academics_repository.dart';
import '../domain/academics_models.dart';

final academicsRepositoryProvider = Provider<IAcademicsRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockAcademicsRepository();
  }
  return ApiAcademicsRepository(ref.watch(apiClientProvider));
});

final departmentsProvider = FutureProvider<List<Department>>((ref) {
  return ref.watch(academicsRepositoryProvider).fetchDepartments();
});

/// The department picked on the Courses tab; null until the departments load (then the one
/// with the most courses is shown).
final selectedDepartmentIdProvider = StateProvider<String?>((ref) => null);

final departmentCoursesProvider = FutureProvider.family<List<Course>, String>((ref, departmentId) {
  return ref.watch(academicsRepositoryProvider).fetchCourses(departmentId);
});

final courseProvider = FutureProvider.family<Course?, String>((ref, courseId) {
  return ref.watch(academicsRepositoryProvider).getCourse(courseId);
});

final survivalGuideProvider = FutureProvider.family<SurvivalGuide, String>((ref, courseId) {
  return ref.watch(academicsRepositoryProvider).fetchSurvivalGuide(courseId);
});

final courseFeedbackProvider = FutureProvider.family<List<CourseFeedback>, String>((ref, courseId) {
  ref.watch(currentUserProvider); // names and "mine" depend on who is viewing
  return ref.watch(academicsRepositoryProvider).fetchFeedback(courseId);
});

/// The signed-in user's own review of a course (null for guests, or if they haven't written one).
final myCourseFeedbackProvider = FutureProvider.family<CourseFeedback?, String>((ref, courseId) async {
  if (ref.watch(isGuestUserProvider)) return null;
  return ref.watch(academicsRepositoryProvider).fetchMyFeedback(courseId);
});

/// Follows / unfollows the viewer made in this session, by course id, shown at once and kept, so the
/// course page and the Following tab agree without reloading every department's courses. Cleared when
/// someone else signs in.
final courseFollowOverridesProvider = StateProvider<Map<String, bool>>((ref) {
  ref.watch(currentUserProvider);
  return const {};
});

/// A course with its department's name, for search across departments.
typedef CourseWithDepartment = ({Course course, String departmentName});

/// Every course in every department (for the super search and the Courses tab search box).
final allCoursesProvider = FutureProvider<List<CourseWithDepartment>>((ref) async {
  final departments = await ref.watch(departmentsProvider.future);
  final lists = await Future.wait(departments.map((d) async {
    final courses = await ref.watch(academicsRepositoryProvider).fetchCourses(d.id);
    return [for (final c in courses) (course: c, departmentName: d.name)];
  }));
  return [for (final l in lists) ...l];
});

/// Courses the signed-in viewer follows, across every department (the Courses tab's "Following" tab).
final followingCoursesProvider = FutureProvider<List<CourseWithDepartment>>((ref) async {
  ref.watch(currentUserProvider); // refetch when who's signed in changes
  final all = await ref.watch(allCoursesProvider.future);
  final overrides = ref.watch(courseFollowOverridesProvider);
  return all.where((c) => overrides[c.course.id] ?? c.course.following).toList();
});

String _squash(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_.]'), '');

/// Course search: the code matches ignoring spaces, dashes and case ("ds252", "DS-252" and
/// "ds 252" all find "DS 252"); the name and department match as plain text.
bool courseMatches(CourseWithDepartment c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final squashed = _squash(q);
  return (squashed.isNotEmpty && _squash(c.course.code).contains(squashed)) ||
      c.course.name.toLowerCase().contains(q) ||
      c.departmentName.toLowerCase().contains(q);
}
