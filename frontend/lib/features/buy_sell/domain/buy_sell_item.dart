import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';

enum ListingStatus {
  available,
  reserved,
  sold;

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
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      photos: photos ?? this.photos,
      sellerContact: sellerContact ?? this.sellerContact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
