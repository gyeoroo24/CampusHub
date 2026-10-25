import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/academics_repository.dart';
import '../domain/academics_models.dart';

final academicsRepositoryProvider = Provider<IAcademicsRepository>((ref) {
  if (AppConfig.useMockData) {
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
  return ref.watch(academicsRepositoryProvider).fetchFeedback(courseId);
});
