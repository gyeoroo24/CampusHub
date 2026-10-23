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

/// Unified domain entity representing a Buy & Sell listing (FR-4, FR-5).
class ListingItem {
  final String id;
  final String title;
  final String description;
  final double price;
  final ListingStatus status;
  final String location;
  final CategoryRef categoryRef;
  final UserRef seller;
  final String? coverPhotoUrl;
  final List<Photo> photos;
  final Contact? sellerContact;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ListingItem({
    required this.id,
    required this.title,
    this.description = '',
    double? price,
    double? sellingPrice,
    double? costPrice,
    this.status = ListingStatus.available,
    this.location = '',
    CategoryRef? categoryRef,
    String? category,
    UserRef? seller,
    String? sellerId,
    String? sellerName,
    String? sellerEmail,
    this.coverPhotoUrl,
    List<Photo>? photos,
    List<String>? imageUrls,
    Contact? sellerContact,
    required this.createdAt,
    this.updatedAt,
  })  : price = price ?? sellingPrice ?? costPrice ?? 0.0,
        categoryRef = categoryRef ??
            CategoryRef(id: 1, name: category ?? 'Other'),
        seller = seller ??
            UserRef(
              id: sellerId ?? '',
              name: sellerName ?? sellerEmail ?? 'Seller',
            ),
        sellerContact = sellerContact ??
            (sellerEmail != null ? Contact(email: sellerEmail) : null),
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
  String get category => categoryRef.name;
  double get sellingPrice => price;
  double get costPrice => price;
  String get sellerId => seller.id;
  String get sellerName => seller.name;
  String get sellerEmail => sellerContact?.email ?? seller.name;

  List<String> get imageUrls => photos.isNotEmpty
      ? photos.map((p) => p.url).toList()
      : (coverPhotoUrl != null && coverPhotoUrl!.isNotEmpty
          ? [coverPhotoUrl!]
          : const []);

  String get imageUrl =>
      coverPhotoUrl ?? (photos.isNotEmpty ? photos.first.url : '');

  ListingItem copyWith({
    String? id,
    String? title,
    String? description,
    double? price,
    ListingStatus? status,
    String? location,
    CategoryRef? categoryRef,
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
      categoryRef: categoryRef ?? this.categoryRef,
      seller: seller ?? this.seller,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      photos: photos ?? this.photos,
      sellerContact: sellerContact ?? this.sellerContact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
