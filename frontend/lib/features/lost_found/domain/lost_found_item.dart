enum PostType { lost, found }

enum ReportStatus { open, resolved }

class LostFoundItem {
  final String id;
  final String reporterId;
  final String reporterContact;
  final String title;
  final String description;
  final String category;
  final String location;
  final List<String> imageUrls;
  final PostType type;
  final String eventTime;
  final ReportStatus status;
  final DateTime dateReported;
  final DateTime? updatedAt;

  /// Primary thumbnail — first element of [imageUrls].
  String get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';

  const LostFoundItem({
    required this.id,
    this.reporterId = '',
    required this.reporterContact,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    required this.imageUrls,
    required this.type,
    required this.eventTime,
    this.status = ReportStatus.open,
    required this.dateReported,
    this.updatedAt,
  });

  LostFoundItem copyWith({
    String? id,
    String? reporterId,
    String? reporterContact,
    String? title,
    String? description,
    String? category,
    String? location,
    List<String>? imageUrls,
    PostType? type,
    String? eventTime,
    ReportStatus? status,
    DateTime? dateReported,
    DateTime? updatedAt,
  }) {
    return LostFoundItem(
      id: id ?? this.id,
      reporterId: reporterId ?? this.reporterId,
      reporterContact: reporterContact ?? this.reporterContact,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      location: location ?? this.location,
      imageUrls: imageUrls ?? this.imageUrls,
      type: type ?? this.type,
      eventTime: eventTime ?? this.eventTime,
      status: status ?? this.status,
      dateReported: dateReported ?? this.dateReported,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
