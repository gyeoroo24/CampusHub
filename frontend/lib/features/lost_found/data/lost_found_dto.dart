import '../domain/lost_found_item.dart';

/// Data Transfer Object for Lost & Found reports matching FastAPI/Pydantic schemas.
class LostFoundReportDto {
  final String id;
  final String reporterId;
  final String reporterContact;
  final String type;
  final String title;
  final String description;
  final String category;
  final String location;
  final List<String> photoUrls;
  final String eventTime;
  final String status;
  final DateTime dateReported;
  final DateTime? updatedAt;

  const LostFoundReportDto({
    required this.id,
    required this.reporterId,
    required this.reporterContact,
    required this.type,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    required this.photoUrls,
    required this.eventTime,
    required this.status,
    required this.dateReported,
    this.updatedAt,
  });

  factory LostFoundReportDto.fromJson(Map<String, dynamic> json) {
    return LostFoundReportDto(
      id: json['id']?.toString() ?? '',
      reporterId: json['reporter_id']?.toString() ?? '',
      reporterContact: json['reporter_contact']?.toString() ??
          json['reporter_email']?.toString() ??
          json['contact']?.toString() ??
          '',
      type: json['type']?.toString() ?? 'lost',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? json['category_id']?.toString() ?? 'Other',
      location: json['location']?.toString() ??
          json['lost_found_location']?.toString() ??
          '',
      photoUrls: (json['photo_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      eventTime: json['event_time']?.toString() ??
          json['lost_found_time']?.toString() ??
          'Recent',
      status: json['status']?.toString() ?? 'open',
      dateReported: json['date_reported'] != null
          ? DateTime.tryParse(json['date_reported'].toString()) ?? DateTime.now()
          : (json['timestamp'] != null
              ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
              : (json['created_at'] != null
                  ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
                  : DateTime.now())),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reporter_id': reporterId,
      'reporter_contact': reporterContact,
      'type': type,
      'title': title,
      'description': description,
      'category': category,
      'location': location,
      'photo_urls': photoUrls,
      'event_time': eventTime,
      'status': status,
      'date_reported': dateReported.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  LostFoundItem toDomain() {
    return LostFoundItem(
      id: id,
      reporterId: reporterId,
      reporterContact: reporterContact,
      title: title,
      description: description,
      category: category,
      location: location,
      imageUrls: photoUrls,
      type: type.toLowerCase() == 'found' ? PostType.found : PostType.lost,
      eventTime: eventTime,
      status: status.toLowerCase() == 'resolved' ? ReportStatus.resolved : ReportStatus.open,
      dateReported: dateReported,
      updatedAt: updatedAt,
    );
  }

  factory LostFoundReportDto.fromDomain(LostFoundItem item) {
    return LostFoundReportDto(
      id: item.id,
      reporterId: item.reporterId,
      reporterContact: item.reporterContact,
      title: item.title,
      description: item.description,
      category: item.category,
      location: item.location,
      photoUrls: item.imageUrls,
      type: item.type.name,
      eventTime: item.eventTime,
      status: item.status.name,
      dateReported: item.dateReported,
      updatedAt: item.updatedAt,
    );
  }
}
