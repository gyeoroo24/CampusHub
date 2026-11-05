import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../domain/lost_found_item.dart';

/// Data Transfer Object for Lost & Found reports matching FastAPI schemas
/// (`ReportSummary` and `ReportDetail`).
class LostFoundReportDto {
  final String id;
  final String? title;
  final String kind;
  final String description;
  final CategoryRef category;
  final DateTime occurredAt;
  final String? location;
  final String status;
  final UserRef reporter;
  final bool reporterDeactivated;
  final String? coverPhotoUrl;
  final List<Photo> photos;
  final Contact? reporterContact;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<LostFoundReportDto>? possibleMatches;

  const LostFoundReportDto({
    required this.id,
    this.title,
    required this.kind,
    required this.description,
    required this.category,
    required this.occurredAt,
    this.location,
    required this.status,
    required this.reporter,
    this.reporterDeactivated = false,
    this.coverPhotoUrl,
    this.photos = const [],
    this.reporterContact,
    required this.createdAt,
    this.updatedAt,
    this.possibleMatches,
  });

  factory LostFoundReportDto.fromJson(Map<String, dynamic> json) {
    // 1. Kind / Type parsing
    final rawKind = json['kind']?.toString() ??
        json['type']?.toString() ??
        'lost';

    // 2. Category parsing
    CategoryRef parsedCategory;
    if (json['category'] is Map<String, dynamic>) {
      parsedCategory = CategoryRef.fromJson(json['category'] as Map<String, dynamic>);
    } else {
      final catId = json['category_id'] is int
          ? json['category_id'] as int
          : int.tryParse(json['category_id']?.toString() ?? '1') ?? 1;
      final catName = json['category']?.toString() ?? 'Other';
      parsedCategory = CategoryRef(id: catId, name: catName);
    }

    // 3. Reporter parsing
    UserRef parsedReporter;
    if (json['reporter'] is Map<String, dynamic>) {
      parsedReporter = UserRef.fromJson(json['reporter'] as Map<String, dynamic>);
    } else {
      final rId = json['reporter_id']?.toString() ?? '';
      final rName = json['reporter_name']?.toString() ??
          json['reporter_contact']?.toString() ??
          'Reporter';
      parsedReporter = UserRef(id: rId, name: rName);
    }

    // 4. Contact parsing: null for guests
    Contact? parsedContact;
    if (json['reporter_contact'] is Map<String, dynamic>) {
      parsedContact = Contact.fromJson(json['reporter_contact'] as Map<String, dynamic>);
    } else if (json['reporter_contact'] is String &&
        (json['reporter_contact'] as String).contains('@')) {
      parsedContact = Contact(email: json['reporter_contact'] as String);
    } else if (json['reporter_email'] != null) {
      parsedContact = Contact(
        email: json['reporter_email'].toString(),
        phone: json['reporter_phone']?.toString(),
      );
    }

    // 5. Photos parsing
    List<Photo> parsedPhotos = [];
    if (json['photos'] is List) {
      parsedPhotos = (json['photos'] as List<dynamic>)
          .map((p) => Photo.fromJson(p as Map<String, dynamic>))
          .toList();
    } else if (json['photo_urls'] is List || json['image_urls'] is List) {
      final rawUrls = (json['photo_urls'] as List<dynamic>?) ??
          (json['image_urls'] as List<dynamic>?) ??
          [];
      parsedPhotos = rawUrls
          .asMap()
          .entries
          .map(
            (e) => Photo(
              s3Key: 'mock_${e.key}',
              url: e.value.toString(),
              sortOrder: e.key,
            ),
          )
          .toList();
    }

    final coverUrl = json['cover_photo_url']?.toString() ??
        (parsedPhotos.isNotEmpty ? parsedPhotos.first.url : null);

    // 6. OccurredAt parsing (occurred_at or legacy lost_found_time)
    DateTime parsedOccurredAt = DateTime.now();
    if (json['occurred_at'] != null) {
      parsedOccurredAt = DateTime.tryParse(json['occurred_at'].toString()) ?? DateTime.now();
    } else if (json['lost_found_time'] != null) {
      parsedOccurredAt = DateTime.tryParse(json['lost_found_time'].toString()) ?? DateTime.now();
    }

    // 7. Possible matches parsing (if returned on create)
    List<LostFoundReportDto>? matches;
    if (json['possible_matches'] is List) {
      matches = (json['possible_matches'] as List<dynamic>)
          .map((m) => LostFoundReportDto.fromJson(m as Map<String, dynamic>))
          .toList();
    }

    return LostFoundReportDto(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString(),
      kind: rawKind,
      description: json['description']?.toString() ?? '',
      category: parsedCategory,
      occurredAt: parsedOccurredAt,
      location: json['location']?.toString() ??
          json['lost_found_location']?.toString(),
      status: json['status']?.toString() ?? 'open',
      reporter: parsedReporter,
      reporterDeactivated: json['reporter_deactivated'] == true,
      coverPhotoUrl: coverUrl,
      photos: parsedPhotos,
      reporterContact: parsedContact,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : (json['date_reported'] != null
              ? DateTime.tryParse(json['date_reported'].toString()) ?? DateTime.now()
              : DateTime.now()),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      possibleMatches: matches,
    );
  }

  LostFoundItem toDomain() {
    return LostFoundItem(
      id: id,
      title: title,
      kind: kind.toLowerCase() == 'found' ? PostType.found : PostType.lost,
      description: description,
      category: category,
      occurredAt: occurredAt,
      location: location ?? '',
      status: ReportStatus.fromString(status),
      reporter: reporter,
      reporterDeactivated: reporterDeactivated,
      coverPhotoUrl: coverPhotoUrl,
      photos: photos,
      reporterContact: reporterContact,
      createdAt: createdAt,
      updatedAt: updatedAt,
      possibleMatches: possibleMatches?.map((m) => m.toDomain()).toList(),
    );
  }

  factory LostFoundReportDto.fromDomain(LostFoundItem item) {
    return LostFoundReportDto(
      id: item.id,
      title: item.title,
      kind: item.kind.name,
      description: item.description,
      category: item.category,
      occurredAt: item.occurredAt,
      location: item.location,
      status: item.status.name,
      reporter: item.reporter,
      coverPhotoUrl: item.coverPhotoUrl,
      photos: item.photos,
      reporterContact: item.reporterContact,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      possibleMatches: item.possibleMatches
          ?.map((m) => LostFoundReportDto.fromDomain(m))
          .toList(),
    );
  }

  Map<String, dynamic> toCreateJson({List<String> photoKeys = const []}) {
    return {
      if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
      'description': description,
      'category_id': category.id,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'location': location?.isNotEmpty == true ? location : null,
      'photo_keys': photoKeys.isNotEmpty
          ? photoKeys
          : photos.map((p) => p.s3Key).where((k) => k.isNotEmpty).toList(),
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
      'description': description,
      'category_id': category.id,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'location': location,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'description': description,
      'category': category.toJson(),
      'occurred_at': occurredAt.toIso8601String(),
      'location': location,
      'status': status,
      'reporter': reporter.toJson(),
      'cover_photo_url': coverPhotoUrl,
      'photos': photos.map((p) => p.toJson()).toList(),
      if (reporterContact != null) 'reporter_contact': reporterContact!.toJson(),
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (possibleMatches != null)
        'possible_matches': possibleMatches!.map((m) => m.toJson()).toList(),
    };
  }
}
