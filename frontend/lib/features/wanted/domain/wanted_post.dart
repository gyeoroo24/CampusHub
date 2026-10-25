import '../../../core/models/category_ref.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/user_ref.dart';
import '../../buy_sell/data/buy_sell_dto.dart';
import '../../buy_sell/domain/buy_sell_item.dart';

enum WantedStatus {
  open('Looking'),
  fulfilled('Found it'),
  closed('Closed');

  final String label;
  const WantedStatus(this.label);

  static WantedStatus fromString(String? value) =>
      WantedStatus.values.firstWhere((s) => s.name == value, orElse: () => WantedStatus.open);
}

/// "Need a cycle, budget ₹3,000": what a buyer is looking for (`/wanted`).
class WantedPost {
  final String id;
  final String title;
  final String? description;
  final CategoryRef category;

  /// Budget in rupees; null means open to offers.
  final double? maxPrice;
  final WantedStatus status;
  final UserRef author;

  /// Only for signed-in viewers.
  final Contact? authorContact;
  final DateTime createdAt;

  /// Only filled in the reply to creating a post: listings that already match.
  final List<ListingItem> possibleMatches;

  const WantedPost({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    this.maxPrice,
    this.status = WantedStatus.open,
    required this.author,
    this.authorContact,
    required this.createdAt,
    this.possibleMatches = const [],
  });

  factory WantedPost.fromJson(Map<String, dynamic> json) {
    return WantedPost(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      category: CategoryRef.fromJson(json['category'] as Map<String, dynamic>),
      maxPrice: json['max_price'] == null ? null : double.tryParse(json['max_price'].toString()),
      status: WantedStatus.fromString(json['status']?.toString()),
      author: UserRef.fromJson(json['author'] as Map<String, dynamic>),
      authorContact: json['author_contact'] is Map<String, dynamic>
          ? Contact.fromJson(json['author_contact'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
      possibleMatches: (json['possible_matches'] as List<dynamic>? ?? [])
          .map((j) => BuySellListingDto.fromJson(j as Map<String, dynamic>).toDomain())
          .toList(),
    );
  }

  WantedPost copyWith({String? title, String? description, double? maxPrice, WantedStatus? status}) {
    return WantedPost(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category,
      maxPrice: maxPrice ?? this.maxPrice,
      status: status ?? this.status,
      author: author,
      authorContact: authorContact,
      createdAt: createdAt,
    );
  }

  String get budgetLabel => maxPrice == null ? 'Open to offers' : 'Up to ₹${maxPrice!.toStringAsFixed(0)}';
}
