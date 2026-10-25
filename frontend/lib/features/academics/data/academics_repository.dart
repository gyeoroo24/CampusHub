import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/academics_models.dart';

/// The parts of Academic Help the course survival guide needs: browse departments and courses,
/// read the guide and recent feedback, and post feedback.
abstract class IAcademicsRepository {
  Future<List<Department>> fetchDepartments();

  Future<List<Course>> fetchCourses(String departmentId);

  Future<Course?> getCourse(String courseId);

  Future<SurvivalGuide> fetchSurvivalGuide(String courseId);

  /// Newest first.
  Future<List<CourseFeedback>> fetchFeedback(String courseId, {int limit = 20});

  Future<CourseFeedback> postFeedback(String courseId, String content);
}

class ApiAcademicsRepository implements IAcademicsRepository {
  final ApiClient apiClient;

  ApiAcademicsRepository(this.apiClient);

  @override
  Future<List<Department>> fetchDepartments() async {
    final response = await apiClient.get(ApiEndpoints.departments);
    return (response.data as List<dynamic>).map((j) => Department.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Course>> fetchCourses(String departmentId) async {
    final response = await apiClient.get(ApiEndpoints.departmentCourses(departmentId));
    return (response.data as List<dynamic>).map((j) => Course.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<Course?> getCourse(String courseId) async {
    final response = await apiClient.get(ApiEndpoints.course(courseId));
    return Course.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<SurvivalGuide> fetchSurvivalGuide(String courseId) async {
    final response = await apiClient.get(ApiEndpoints.courseSurvivalGuide(courseId));
    return SurvivalGuide.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<CourseFeedback>> fetchFeedback(String courseId, {int limit = 20}) async {
    final response = await apiClient.get(ApiEndpoints.courseFeedback(courseId), queryParameters: {'limit': limit});
    final items = (response.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? [];
    return items.map((j) => CourseFeedback.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<CourseFeedback> postFeedback(String courseId, String content) async {
    final response = await apiClient.post(ApiEndpoints.courseFeedback(courseId), data: {'content': content});
    return CourseFeedback.fromJson(response.data as Map<String, dynamic>);
  }
}

/// In-memory version for mock mode: two departments, a few courses, and one full guide (DS 252).
class MockAcademicsRepository implements IAcademicsRepository {
  static const _departments = [
    Department(id: 'd_cds', name: 'Computational and Data Sciences', courseCount: 4),
    Department(id: 'd_csa', name: 'Computer Science and Automation', courseCount: 2),
  ];

  static const _courses = [
    Course(id: 'c_252', departmentId: 'd_cds', code: 'DS 252', name: 'Cloud Computing', feedbackCount: 6),
    Course(id: 'c_221', departmentId: 'd_cds', code: 'DS 221', name: 'Introduction to Scalable Systems'),
    Course(id: 'c_211', departmentId: 'd_cds', code: 'DS 211', name: 'Numerical Optimization'),
    Course(id: 'c_265', departmentId: 'd_cds', code: 'DS 265', name: 'Deep Learning for Computer Vision'),
    Course(id: 'c_e0243', departmentId: 'd_csa', code: 'E0 243', name: 'Computer Architecture'),
    Course(id: 'c_e0270', departmentId: 'd_csa', code: 'E0 270', name: 'Machine Learning'),
  ];

  static final List<CourseFeedback> _feedback = [
    CourseFeedback(
      id: 'f_1',
      authorName: 'Ananya Rao',
      content: 'Yogesh Simmhan explains the CAP theorem really clearly. Start the project early.',
      createdAt: DateTime(2025, 11, 30),
    ),
    CourseFeedback(
      id: 'f_2',
      authorName: 'Rohan Sharma',
      content: 'Content is great but the workload is heavy. Expect 12+ hours a week.',
      createdAt: DateTime(2024, 12, 5),
    ),
    CourseFeedback(
      id: 'f_3',
      authorName: 'Priya Iyer',
      content: 'The pace was brutal, especially around serverless execution models.',
      createdAt: DateTime(2023, 12, 1),
    ),
  ];

  static const _ds252Guide = SurvivalGuide(
    courseCode: 'DS 252',
    courseName: 'Cloud Computing',
    departmentName: 'Computational and Data Sciences',
    feedbackCount: 21,
    summary: 'Students are mostly positive about DS 252 (62% positive, 10% negative across 21 reviews from '
        'Aug 2023 to Aug 2026). Sentiment is improving: mixed in Aug 2023, positive in Aug 2025. Most discussed: '
        'assignments and projects (mixed), workload (mixed), teaching (positive). Common advice: “Start the project early.”',
    overall: Sentiment(score: 0.34, label: SentimentLabel.positive, positiveShare: 0.62, negativeShare: 0.1),
    trend: GuideTrend.improving,
    themes: [
      GuideTheme(theme: 'assignments and projects', mentions: 11, score: 0.12, label: SentimentLabel.mixed),
      GuideTheme(theme: 'workload', mentions: 9, score: -0.05, label: SentimentLabel.mixed),
      GuideTheme(theme: 'teaching', mentions: 7, score: 0.61, label: SentimentLabel.positive),
      GuideTheme(theme: 'exams', mentions: 5, score: 0.3, label: SentimentLabel.positive),
    ],
    advice: ['Start the project early.', 'Expect 12+ hours a week; the assignments are long.'],
    semesters: [
      GuideSemester(
        term: 'Aug 2023',
        feedbackCount: 7,
        sentiment: Sentiment(score: 0.2, label: SentimentLabel.mixed, positiveShare: 0.43, negativeShare: 0.29),
        topThemes: [GuideTheme(theme: 'workload', mentions: 4, score: -0.4, label: SentimentLabel.negative)],
        negativeQuote: 'The pace was brutal, especially around serverless execution models.',
      ),
      GuideSemester(
        term: 'Aug 2024',
        feedbackCount: 8,
        sentiment: Sentiment(score: 0.42, label: SentimentLabel.positive, positiveShare: 0.63, negativeShare: 0.12),
        positiveQuote: 'Great course if you want a solid base in virtualization.',
      ),
      GuideSemester(
        term: 'Aug 2025',
        feedbackCount: 4,
        sentiment: Sentiment(score: 0.4, label: SentimentLabel.positive, positiveShare: 0.75, negativeShare: 0),
        positiveQuote: 'Yogesh Simmhan explains the CAP theorem really clearly.',
      ),
      GuideSemester(
        term: 'Aug 2026',
        inProgress: true,
        feedbackCount: 2,
        sentiment: Sentiment(score: 0.28, label: SentimentLabel.positive, positiveShare: 0.5, negativeShare: 0),
      ),
    ],
  );

  @override
  Future<List<Department>> fetchDepartments() async => _departments;

  @override
  Future<List<Course>> fetchCourses(String departmentId) async =>
      _courses.where((c) => c.departmentId == departmentId).toList();

  @override
  Future<Course?> getCourse(String courseId) async {
    final match = _courses.where((c) => c.id == courseId);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<SurvivalGuide> fetchSurvivalGuide(String courseId) async {
    if (courseId == 'c_252') return _ds252Guide;
    final course = await getCourse(courseId);
    return SurvivalGuide(
      courseCode: course?.code ?? '',
      courseName: course?.name ?? '',
      departmentName: '',
      feedbackCount: 0,
      summary: 'No feedback on ${course?.code ?? 'this course'} yet. Be the first to share how it went.',
    );
  }

  @override
  Future<List<CourseFeedback>> fetchFeedback(String courseId, {int limit = 20}) async =>
      courseId == 'c_252' ? List.of(_feedback) : [];

  @override
  Future<CourseFeedback> postFeedback(String courseId, String content) async {
    final feedback = CourseFeedback(
      id: 'f_${DateTime.now().microsecondsSinceEpoch}',
      authorName: 'You',
      content: content,
      createdAt: DateTime.now(),
    );
    _feedback.insert(0, feedback);
    return feedback;
  }
}
