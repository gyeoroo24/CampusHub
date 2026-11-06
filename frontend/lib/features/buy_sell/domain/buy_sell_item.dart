import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';

enum ListingStatus {
  available('Available'),
  reserved('Reserved'),
  sold('Sold');

  /// The one name used for this status everywhere: filters, cards and dialogs.
  final String label;
  const ListingStatus(this.label);

  static ListingStatus fromString(String val) {
    switch (val.toLowerCase()) {
      case 'reserved':
        return ListingStatus.reserved;
      case 'sold':
        return ListingStatus.sold;
      default:
        return ListingStatus.available;
    }
  }
}

/// Domain entity representing a Buy & Sell listing (FR-4, FR-5, FR-6).
class ListingItem {
  final String id;
  final String title;
  final String description;
  final double price;
  final ListingStatus status;
  final String location;
  final CategoryRef category;
  final UserRef seller;
  /// 'negative' or 'blocked', from moderator-confirmed removals against this seller (future plan
  /// §1.5). Null for everyone else - there is no positive badge, only this warning.
  final String? sellerTrustTag;
  final bool sellerDeactivated;
  /// Seller marked the price as open to offers (future plan §2.3).
  final bool negotiable;
  /// Flagged automatically as a possible prohibited item and hidden from others until a moderator
  /// decides (future plan §1.6). Only the seller and moderators ever see it true.
  final bool heldForReview;
  /// The signed-in viewer is watching it for price changes (detail view only).
  final bool watching;
  final String? coverPhotoUrl;
  final List<Photo> photos;
  final Contact? sellerContact;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ListingItem({
    required this.id,
    required this.title,
    this.description = '',
    required this.price,
    this.status = ListingStatus.available,
    this.location = '',
    required this.category,
    required this.seller,
    this.sellerTrustTag,
    this.sellerDeactivated = false,
    this.negotiable = false,
    this.heldForReview = false,
    this.watching = false,
    this.coverPhotoUrl,
    this.photos = const [],
    this.sellerContact,
    required this.createdAt,
    this.updatedAt,
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

  ListingItem copyWith({
    String? id,
    String? title,
    String? description,
    double? price,
    ListingStatus? status,
    String? location,
    CategoryRef? category,
    UserRef? seller,
    String? sellerTrustTag,
    bool? sellerDeactivated,
    bool? negotiable,
    bool? heldForReview,
    bool? watching,
    String? coverPhotoUrl,
    List<Photo>? photos,
    Contact? sellerContact,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ListingItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      status: status ?? this.status,
      location: location ?? this.location,
      category: category ?? this.category,
      seller: seller ?? this.seller,
      sellerTrustTag: sellerTrustTag ?? this.sellerTrustTag,
      sellerDeactivated: sellerDeactivated ?? this.sellerDeactivated,
      negotiable: negotiable ?? this.negotiable,
      heldForReview: heldForReview ?? this.heldForReview,
      watching: watching ?? this.watching,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      photos: photos ?? this.photos,
      sellerContact: sellerContact ?? this.sellerContact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
