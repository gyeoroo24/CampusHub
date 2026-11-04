/// Academic Help read models: departments, courses, feedback and the course survival guide.
library;

int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
double _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class Department {
  final String id;
  final String name;
  final int courseCount;

  const Department({required this.id, required this.name, this.courseCount = 0});

  factory Department.fromJson(Map<String, dynamic> json) =>
      Department(id: json['id'].toString(), name: json['name']?.toString() ?? '', courseCount: _int(json['course_count']));
}

class Course {
  final String id;
  final String departmentId;
  final String code;
  final String name;
  final int materialCount;
  final int feedbackCount;

  /// The viewer follows the course (new materials, feedback and forum posts notify them).
  final bool following;
  final int followerCount;

  const Course({
    required this.id,
    required this.departmentId,
    required this.code,
    required this.name,
    this.materialCount = 0,
    this.feedbackCount = 0,
    this.following = false,
    this.followerCount = 0,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'].toString(),
        departmentId: json['department_id'].toString(),
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        materialCount: _int(json['material_count']),
        feedbackCount: _int(json['feedback_count']),
        following: json['following'] == true,
        followerCount: _int(json['follower_count']),
      );
}

class CourseFeedback {
  final String id;

  /// null when the author chose to stay anonymous, or the viewer is a guest.
  final String? authorName;
  final bool isAnonymous;

  /// The viewer wrote it, so they may edit or delete it.
  final bool isMine;

  /// The viewer may remove it: its author, or a moderator of this course (or its department).
  final bool canRemove;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CourseFeedback({
    required this.id,
    this.authorName,
    this.isAnonymous = false,
    this.isMine = false,
    this.canRemove = false,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  factory CourseFeedback.fromJson(Map<String, dynamic> json) => CourseFeedback(
        id: json['id'].toString(),
        authorName: (json['author'] as Map?)?['name']?.toString(),
        isAnonymous: json['is_anonymous'] as bool? ?? false,
        isMine: json['is_mine'] as bool? ?? false,
        canRemove: json['can_remove'] as bool? ?? false,
        content: json['content']?.toString() ?? '',
        createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${json['updated_at']}'),
      );

  /// What to show as the author: their name, or a neutral label.
  String get displayAuthor => isAnonymous ? 'Anonymous student' : (authorName ?? 'A student');

  bool get wasEdited => updatedAt != null && updatedAt!.difference(createdAt).inSeconds > 5;

  CourseFeedback copyWith({String? content, bool? isAnonymous}) => CourseFeedback(
        id: id,
        authorName: authorName,
        isAnonymous: isAnonymous ?? this.isAnonymous,
        isMine: isMine,
        canRemove: canRemove,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// positive / mixed / negative
enum SentimentLabel {
  positive,
  mixed,
  negative;

  static SentimentLabel fromString(String? v) =>
      SentimentLabel.values.firstWhere((l) => l.name == v, orElse: () => SentimentLabel.mixed);
}

class Sentiment {
  /// -1 (negative) to +1 (positive).
  final double score;
  final SentimentLabel label;
  final double positiveShare;
  final double negativeShare;

  const Sentiment({required this.score, required this.label, this.positiveShare = 0, this.negativeShare = 0});

  factory Sentiment.fromJson(Map<String, dynamic> json) => Sentiment(
        score: _double(json['score']),
        label: SentimentLabel.fromString(json['label']?.toString()),
        positiveShare: _double(json['positive_share']),
        negativeShare: _double(json['negative_share']),
      );
}

class GuideTheme {
  final String theme;
  final int mentions;
  final double score;
  final SentimentLabel label;

  const GuideTheme({required this.theme, required this.mentions, required this.score, required this.label});

  factory GuideTheme.fromJson(Map<String, dynamic> json) => GuideTheme(
        theme: json['theme']?.toString() ?? '',
        mentions: _int(json['mentions']),
        score: _double(json['score']),
        label: SentimentLabel.fromString(json['label']?.toString()),
      );
}

class GuideSemester {
  /// e.g. "Aug 2025"
  final String term;
  final bool inProgress;
  final int feedbackCount;
  final Sentiment sentiment;
  final List<GuideTheme> topThemes;
  final String? positiveQuote;
  final String? negativeQuote;

  const GuideSemester({
    required this.term,
    this.inProgress = false,
    required this.feedbackCount,
    required this.sentiment,
    this.topThemes = const [],
    this.positiveQuote,
    this.negativeQuote,
  });

  factory GuideSemester.fromJson(Map<String, dynamic> json) {
    final highlights = (json['highlights'] as Map?)?.cast<String, dynamic>() ?? const {};
    return GuideSemester(
      term: json['term']?.toString() ?? '',
      inProgress: json['in_progress'] as bool? ?? false,
      feedbackCount: _int(json['feedback_count']),
      sentiment: Sentiment.fromJson(json['sentiment'] as Map<String, dynamic>),
      topThemes: (json['top_themes'] as List<dynamic>? ?? [])
          .map((t) => GuideTheme.fromJson(t as Map<String, dynamic>))
          .toList(),
      positiveQuote: highlights['positive']?.toString(),
      negativeQuote: highlights['negative']?.toString(),
    );
  }
}

/// `improving`, `declining`, `steady` or `not_enough_data`.
enum GuideTrend {
  improving('Improving'),
  declining('Declining'),
  steady('Steady'),
  notEnoughData('Not enough data');

  final String label;
  const GuideTrend(this.label);

  static GuideTrend fromString(String? v) => switch (v) {
        'improving' => GuideTrend.improving,
        'declining' => GuideTrend.declining,
        'steady' => GuideTrend.steady,
        _ => GuideTrend.notEnoughData,
      };
}

/// One-page summary of a course's feedback (`GET /courses/{id}/survival-guide`).
class SurvivalGuide {
  final String courseCode;
  final String courseName;
  final String departmentName;
  final int feedbackCount;
  final String summary;
  final Sentiment? overall;
  final GuideTrend trend;
  final List<GuideTheme> themes;
  final List<String> advice;

  /// Oldest first.
  final List<GuideSemester> semesters;

  const SurvivalGuide({
    required this.courseCode,
    required this.courseName,
    required this.departmentName,
    required this.feedbackCount,
    required this.summary,
    this.overall,
    this.trend = GuideTrend.notEnoughData,
    this.themes = const [],
    this.advice = const [],
    this.semesters = const [],
  });

  factory SurvivalGuide.fromJson(Map<String, dynamic> json) {
    final course = (json['course'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SurvivalGuide(
      courseCode: course['code']?.toString() ?? '',
      courseName: course['name']?.toString() ?? '',
      departmentName: course['department_name']?.toString() ?? '',
      feedbackCount: _int(json['feedback_count']),
      summary: json['summary']?.toString() ?? '',
      overall: json['overall'] is Map<String, dynamic> ? Sentiment.fromJson(json['overall'] as Map<String, dynamic>) : null,
      trend: GuideTrend.fromString(json['trend']?.toString()),
      themes: (json['themes'] as List<dynamic>? ?? [])
          .map((t) => GuideTheme.fromJson(t as Map<String, dynamic>))
          .toList(),
      advice: (json['advice'] as List<dynamic>? ?? []).map((a) => a.toString()).toList(),
      semesters: (json['semesters'] as List<dynamic>? ?? [])
          .map((s) => GuideSemester.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
