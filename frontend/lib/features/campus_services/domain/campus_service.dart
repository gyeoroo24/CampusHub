/// Groups on the campus services card, in display order (matches the backend enum order).
enum CampusServiceCategory {
  health('Health'),
  wellbeing('Wellbeing'),
  grievance('Grievances'),
  safety('Safety'),
  other('Other');

  final String label;
  const CampusServiceCategory(this.label);

  static CampusServiceCategory fromString(String? value) =>
      CampusServiceCategory.values.firstWhere((c) => c.name == value, orElse: () => CampusServiceCategory.other);
}

/// A Health Centre / Wellness Centre / grievance link or phone number for the landing page.
class CampusService {
  final String id;
  final String name;
  final String? description;
  final CampusServiceCategory category;

  /// At least one of [url] and [phone] is set.
  final String? url;
  final String? phone;
  final int sortOrder;
  final bool isActive;

  const CampusService({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.url,
    this.phone,
    this.sortOrder = 100,
    this.isActive = true,
  });

  factory CampusService.fromJson(Map<String, dynamic> json) {
    return CampusService(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      category: CampusServiceCategory.fromString(json['category']?.toString()),
      url: json['url']?.toString(),
      phone: json['phone']?.toString(),
      sortOrder: json['sort_order'] is int ? json['sort_order'] as int : 100,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Body for create and edit. Empty url / phone / description are sent as null (cleared).
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': (description == null || description!.isEmpty) ? null : description,
        'category': category.name,
        'url': (url == null || url!.isEmpty) ? null : url,
        'phone': (phone == null || phone!.isEmpty) ? null : phone,
        'sort_order': sortOrder,
        'is_active': isActive,
      };

  CampusService copyWith({
    String? id,
    String? name,
    String? description,
    CampusServiceCategory? category,
    String? url,
    String? phone,
    int? sortOrder,
    bool? isActive,
  }) {
    return CampusService(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      url: url ?? this.url,
      phone: phone ?? this.phone,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
