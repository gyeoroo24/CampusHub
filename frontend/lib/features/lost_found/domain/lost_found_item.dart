import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';

enum PostType { lost, found }

enum ReportStatus {
  open,
  matched,
  closed;

  static ReportStatus fromString(String val) {
    switch (val.toLowerCase()) {
      case 'matched':
        return ReportStatus.matched;
      case 'closed':
      case 'resolved':
        return ReportStatus.closed;
      default:
        return ReportStatus.open;
    }
  }
}

/// Domain entity representing a Lost or Found report (FR-7, FR-8, FR-9).
/// Note: Reports do not have titles; the item is identified by [category] (what it is)
/// and [description] (distinguishing marks / details).
class LostFoundItem {
  final String id;
  final PostType kind;
  final String description;
  final CategoryRef category;
  final DateTime occurredAt;
  final String location;
  final ReportStatus status;
  final UserRef reporter;
  final String? coverPhotoUrl;
  final List<Photo> photos;
  final Contact? reporterContact;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<LostFoundItem>? possibleMatches;

  const LostFoundItem({
    required this.id,
    required this.kind,
    required this.description,
    required this.category,
    required this.occurredAt,
    this.location = '',
    this.status = ReportStatus.open,
    required this.reporter,
    this.coverPhotoUrl,
    this.photos = const [],
    this.reporterContact,
    required this.createdAt,
    this.updatedAt,
    this.possibleMatches,
  });

  /// Primary cover image URL or first photo.
  String get imageUrl =>
      coverPhotoUrl ?? (photos.isNotEmpty ? photos.first.url : '');

  /// List of all photo URLs.
  List<String> get photoUrls => photos.isNotEmpty
      ? photos.map((p) => p.url).toList()
      : (coverPhotoUrl != null && coverPhotoUrl!.isNotEmpty
          ? [coverPhotoUrl!]
          : const []);

  LostFoundItem copyWith({
    String? id,
    PostType? kind,
    String? description,
    CategoryRef? category,
    DateTime? occurredAt,
    String? location,
    ReportStatus? status,
    UserRef? reporter,
    String? coverPhotoUrl,
    List<Photo>? photos,
    Contact? reporterContact,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<LostFoundItem>? possibleMatches,
  }) {
    return LostFoundItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      description: description ?? this.description,
      category: category ?? this.category,
      occurredAt: occurredAt ?? this.occurredAt,
      location: location ?? this.location,
      status: status ?? this.status,
      reporter: reporter ?? this.reporter,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      photos: photos ?? this.photos,
      reporterContact: reporterContact ?? this.reporterContact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      possibleMatches: possibleMatches ?? this.possibleMatches,
    );
  }
}
