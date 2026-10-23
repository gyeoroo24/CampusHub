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

  /// Backward-compatibility alias
  static const resolved = ReportStatus.closed;
}

/// Unified domain entity representing a Lost or Found report (FR-7, FR-8, FR-9).
class LostFoundItem {
  final String id;
  final PostType kind;
  final String description;
  final CategoryRef categoryRef;
  final DateTime occurredAt;
  final String location;
  final ReportStatus status;
  final UserRef reporter;
  final String? coverPhotoUrl;
  final List<Photo> photos;
  final Contact? contact;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<LostFoundItem>? possibleMatches;

  LostFoundItem({
    required this.id,
    PostType? kind,
    PostType? type,
    String? description,
    String? title,
    CategoryRef? categoryRef,
    String? category,
    DateTime? occurredAt,
    String? eventTime,
    DateTime? dateReported,
    this.location = '',
    this.status = ReportStatus.open,
    UserRef? reporter,
    String? reporterId,
    String? reporterContact,
    this.coverPhotoUrl,
    List<Photo>? photos,
    List<String>? imageUrls,
    Contact? contact,
    DateTime? createdAt,
    this.updatedAt,
    this.possibleMatches,
  })  : kind = kind ?? type ?? PostType.lost,
        description = description ?? title ?? '',
        categoryRef = categoryRef ??
            CategoryRef(id: 1, name: category ?? 'Other'),
        occurredAt = occurredAt ?? dateReported ?? DateTime.now(),
        reporter = reporter ??
            UserRef(
              id: reporterId ?? '',
              name: reporterContact ?? 'Reporter',
            ),
        contact = contact ??
            (reporterContact != null ? Contact(email: reporterContact) : null),
        createdAt = createdAt ?? dateReported ?? DateTime.now(),
        photos = photos ??
            (imageUrls != null
                ? imageUrls
                    .asMap()
                    .entries
                    .map(
                      (e) => Photo(
                        s3Key: '',
                        url: e.value,
                        sortOrder: e.key,
                      ),
                    )
                    .toList()
                : const []);

  // --- Backwards-compatible accessors for existing UI widgets ---
  PostType get type => kind;
  String get category => categoryRef.name;
  String get title => categoryRef.name;
  String get reporterId => reporter.id;
  String get reporterContact =>
      contact?.email ?? (contact?.phone ?? reporter.name);
  String get eventTime =>
      '${occurredAt.day}/${occurredAt.month}/${occurredAt.year}';
  DateTime get dateReported => createdAt;

  List<String> get imageUrls => photos.isNotEmpty
      ? photos.map((p) => p.url).toList()
      : (coverPhotoUrl != null && coverPhotoUrl!.isNotEmpty
          ? [coverPhotoUrl!]
          : const []);

  String get imageUrl =>
      coverPhotoUrl ?? (photos.isNotEmpty ? photos.first.url : '');

  LostFoundItem copyWith({
    String? id,
    PostType? kind,
    String? description,
    CategoryRef? categoryRef,
    DateTime? occurredAt,
    String? location,
    ReportStatus? status,
    UserRef? reporter,
    String? coverPhotoUrl,
    List<Photo>? photos,
    Contact? contact,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<LostFoundItem>? possibleMatches,
  }) {
    return LostFoundItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      description: description ?? this.description,
      categoryRef: categoryRef ?? this.categoryRef,
      occurredAt: occurredAt ?? this.occurredAt,
      location: location ?? this.location,
      status: status ?? this.status,
      reporter: reporter ?? this.reporter,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      photos: photos ?? this.photos,
      contact: contact ?? this.contact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      possibleMatches: possibleMatches ?? this.possibleMatches,
    );
  }
}
