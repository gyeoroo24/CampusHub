enum ListingStatus { available, reserved, sold }

class ListingItem {
  final String id;
  final String sellerId;
  final String sellerEmail;
  final String title;
  final String description;
  final double costPrice;
  final double sellingPrice;
  final String category;
  final String location;
  final List<String> imageUrls;
  final ListingStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Display name for seller (strictly the student's IISc email)
  String get sellerName => sellerEmail;

  /// Primary thumbnail — first element of [imageUrls] (kept for card display).
  String get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';

  const ListingItem({
    required this.id,
    this.sellerId = '',
    required this.sellerEmail,
    String? sellerName, // Kept for backwards compatibility if passed
    required this.title,
    required this.description,
    required this.costPrice,
    required this.sellingPrice,
    required this.category,
    required this.location,
    required this.imageUrls,
    this.status = ListingStatus.available,
    required this.createdAt,
    this.updatedAt,
  });

  ListingItem copyWith({
    String? id,
    String? sellerId,
    String? sellerEmail,
    String? sellerName,
    String? title,
    String? description,
    double? costPrice,
    double? sellingPrice,
    String? category,
    String? location,
    List<String>? imageUrls,
    ListingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ListingItem(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerEmail: sellerEmail ?? this.sellerEmail,
      title: title ?? this.title,
      description: description ?? this.description,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      category: category ?? this.category,
      location: location ?? this.location,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
