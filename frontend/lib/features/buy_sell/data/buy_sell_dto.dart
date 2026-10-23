import '../domain/buy_sell_item.dart';

/// Data Transfer Object for Buy & Sell listings matching FastAPI/Pydantic schemas.
class BuySellListingDto {
  final String id;
  final String sellerId;
  final String sellerEmail;
  final String title;
  final String description;
  final double costPrice;
  final double sellingPrice;
  final String category;
  final String location;
  final List<String> photoUrls;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BuySellListingDto({
    required this.id,
    required this.sellerId,
    required this.sellerEmail,
    required this.title,
    required this.description,
    required this.costPrice,
    required this.sellingPrice,
    required this.category,
    required this.location,
    required this.photoUrls,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory BuySellListingDto.fromJson(Map<String, dynamic> json) {
    return BuySellListingDto(
      id: json['id']?.toString() ?? '',
      sellerId: json['seller_id']?.toString() ?? '',
      sellerEmail: json['seller_email']?.toString() ?? json['email']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      category: json['category']?.toString() ?? json['category_id']?.toString() ?? 'Other',
      location: json['location']?.toString() ?? '',
      photoUrls: (json['photo_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      status: json['status']?.toString() ?? 'available',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : (json['timestamp'] != null
              ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
              : DateTime.now()),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seller_id': sellerId,
      'seller_email': sellerEmail,
      'title': title,
      'description': description,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'category': category,
      'location': location,
      'photo_urls': photoUrls,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Converts DTO to Domain Entity
  ListingItem toDomain() {
    ListingStatus domainStatus = ListingStatus.available;
    switch (status.toLowerCase()) {
      case 'reserved':
        domainStatus = ListingStatus.reserved;
        break;
      case 'sold':
        domainStatus = ListingStatus.sold;
        break;
      default:
        domainStatus = ListingStatus.available;
    }

    return ListingItem(
      id: id,
      sellerId: sellerId,
      sellerEmail: sellerEmail,
      title: title,
      description: description,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      category: category,
      location: location,
      imageUrls: photoUrls,
      status: domainStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Creates DTO from Domain Entity
  factory BuySellListingDto.fromDomain(ListingItem item) {
    return BuySellListingDto(
      id: item.id,
      sellerId: item.sellerId,
      sellerEmail: item.sellerEmail,
      title: item.title,
      description: item.description,
      costPrice: item.costPrice,
      sellingPrice: item.sellingPrice,
      category: item.category,
      location: item.location,
      photoUrls: item.imageUrls,
      status: item.status.name,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );
  }
}
