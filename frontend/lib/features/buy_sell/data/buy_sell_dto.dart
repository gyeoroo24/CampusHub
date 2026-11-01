import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../domain/buy_sell_item.dart';

/// Data Transfer Object for Buy & Sell listings matching FastAPI schemas
/// (`ListingSummary` and `ListingDetail`).
class BuySellListingDto {
  final String id;
  final String title;
  final String? description;
  final double price;
  final String status;
  final String? location;
  final CategoryRef category;
  final UserRef seller;
  final String? sellerTrustTag;
  final bool negotiable;
  final bool heldForReview;
  final bool watching;
  final String? coverPhotoUrl;
  final List<Photo> photos;
  final Contact? sellerContact;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BuySellListingDto({
    required this.id,
    required this.title,
    this.description,
    required this.price,
    required this.status,
    this.location,
    required this.category,
    required this.seller,
    this.sellerTrustTag,
    this.negotiable = false,
    this.heldForReview = false,
    this.watching = false,
    this.coverPhotoUrl,
    this.photos = const [],
    this.sellerContact,
    required this.createdAt,
    this.updatedAt,
  });

  factory BuySellListingDto.fromJson(Map<String, dynamic> json) {
    // 1. Price parsing: handles Decimal string or number
    double parsedPrice = 0.0;
    if (json['price'] != null) {
      parsedPrice = double.tryParse(json['price'].toString()) ?? 0.0;
    } else if (json['selling_price'] != null) {
      parsedPrice = double.tryParse(json['selling_price'].toString()) ?? 0.0;
    }

    // 2. Category parsing: structured CategoryRef or ID/String
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

    // 3. Seller parsing: structured UserRef
    UserRef parsedSeller;
    if (json['seller'] is Map<String, dynamic>) {
      parsedSeller = UserRef.fromJson(json['seller'] as Map<String, dynamic>);
    } else {
      final sId = json['seller_id']?.toString() ?? '';
      final sName = json['seller_name']?.toString() ??
          json['seller_email']?.toString() ??
          'Seller';
      parsedSeller = UserRef(id: sId, name: sName);
    }

    // 4. Contact parsing: null for guests
    Contact? parsedContact;
    if (json['seller_contact'] is Map<String, dynamic>) {
      parsedContact = Contact.fromJson(json['seller_contact'] as Map<String, dynamic>);
    } else if (json['seller_email'] != null) {
      parsedContact = Contact(
        email: json['seller_email'].toString(),
        phone: json['seller_phone']?.toString(),
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

    return BuySellListingDto(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      price: parsedPrice,
      status: json['status']?.toString() ?? 'available',
      location: json['location']?.toString(),
      category: parsedCategory,
      seller: parsedSeller,
      sellerTrustTag: json['seller_trust_tag']?.toString(),
      negotiable: json['negotiable'] == true,
      heldForReview: json['held_for_review'] == true,
      watching: json['watching'] == true,
      coverPhotoUrl: coverUrl,
      photos: parsedPhotos,
      sellerContact: parsedContact,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  ListingItem toDomain() {
    return ListingItem(
      id: id,
      title: title,
      description: description ?? '',
      price: price,
      status: ListingStatus.fromString(status),
      location: location ?? '',
      category: category,
      seller: seller,
      sellerTrustTag: sellerTrustTag,
      negotiable: negotiable,
      heldForReview: heldForReview,
      watching: watching,
      coverPhotoUrl: coverPhotoUrl,
      photos: photos,
      sellerContact: sellerContact,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory BuySellListingDto.fromDomain(ListingItem item) {
    return BuySellListingDto(
      id: item.id,
      title: item.title,
      description: item.description,
      price: item.price,
      status: item.status.name,
      location: item.location,
      category: item.category,
      seller: item.seller,
      sellerTrustTag: item.sellerTrustTag,
      negotiable: item.negotiable,
      heldForReview: item.heldForReview,
      watching: item.watching,
      coverPhotoUrl: item.coverPhotoUrl,
      photos: item.photos,
      sellerContact: item.sellerContact,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }

  Map<String, dynamic> toCreateJson({List<String> photoKeys = const []}) {
    return {
      'title': title,
      'description': description?.isNotEmpty == true ? description : null,
      'price': price,
      'category_id': category.id,
      'location': location?.isNotEmpty == true ? location : null,
      'negotiable': negotiable,
      'photo_keys': photoKeys.isNotEmpty
          ? photoKeys
          : photos.map((p) => p.s3Key).where((k) => k.isNotEmpty).toList(),
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'title': title,
      'description': description,
      'price': price,
      'category_id': category.id,
      'location': location,
      'negotiable': negotiable,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'status': status,
      'location': location,
      'category': category.toJson(),
      'seller': seller.toJson(),
      if (sellerTrustTag != null) 'seller_trust_tag': sellerTrustTag,
      'negotiable': negotiable,
      'held_for_review': heldForReview,
      'watching': watching,
      'cover_photo_url': coverPhotoUrl,
      'photos': photos.map((p) => p.toJson()).toList(),
      if (sellerContact != null) 'seller_contact': sellerContact!.toJson(),
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
