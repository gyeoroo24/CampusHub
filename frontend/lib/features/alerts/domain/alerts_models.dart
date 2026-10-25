/// Saved searches and in-app notifications (`/me/saved-searches`, `/me/notifications`).
library;

/// Which feed a saved search watches: new listings or new found reports.
enum SavedSearchModule {
  buySell('buy_sell', 'Buy & Sell'),
  lostFound('lost_found', 'Found items');

  final String apiValue;
  final String label;
  const SavedSearchModule(this.apiValue, this.label);

  static SavedSearchModule fromApi(String? value) =>
      value == 'lost_found' ? SavedSearchModule.lostFound : SavedSearchModule.buySell;
}

double? _toDouble(dynamic value) => value == null ? null : double.tryParse(value.toString());

/// "Tell me when a cycle under ₹3,000 appears."
class SavedSearch {
  final String id;
  final SavedSearchModule module;
  final String name;
  final String? query;
  final int? categoryId;
  final String? categoryName;
  final double? minPrice;
  final double? maxPrice;
  final bool alertsEnabled;

  /// Matching items posted since [lastSeenAt] (the "N new" badge).
  final int newCount;
  final DateTime lastSeenAt;
  final DateTime createdAt;

  const SavedSearch({
    required this.id,
    required this.module,
    required this.name,
    this.query,
    this.categoryId,
    this.categoryName,
    this.minPrice,
    this.maxPrice,
    this.alertsEnabled = true,
    this.newCount = 0,
    required this.lastSeenAt,
    required this.createdAt,
  });

  factory SavedSearch.fromJson(Map<String, dynamic> json) {
    return SavedSearch(
      id: json['id'].toString(),
      module: SavedSearchModule.fromApi(json['module']?.toString()),
      name: json['name']?.toString() ?? '',
      query: json['q']?.toString(),
      categoryId: json['category_id'] is int ? json['category_id'] as int : int.tryParse('${json['category_id']}'),
      categoryName: json['category_name']?.toString(),
      minPrice: _toDouble(json['min_price']),
      maxPrice: _toDouble(json['max_price']),
      alertsEnabled: json['alerts_enabled'] as bool? ?? true,
      newCount: json['new_count'] is int ? json['new_count'] as int : 0,
      lastSeenAt: DateTime.tryParse('${json['last_seen_at']}') ?? DateTime.now(),
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
    );
  }

  SavedSearch copyWith({String? name, bool? alertsEnabled, int? newCount, DateTime? lastSeenAt}) {
    return SavedSearch(
      id: id,
      module: module,
      name: name ?? this.name,
      query: query,
      categoryId: categoryId,
      categoryName: categoryName,
      minPrice: minPrice,
      maxPrice: maxPrice,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      newCount: newCount ?? this.newCount,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt,
    );
  }

  /// One line describing the filters, e.g. "“cycle” · Cycles · up to ₹3,000".
  String get filterSummary => describeFilters(
        query: query,
        categoryName: categoryName,
        minPrice: minPrice,
        maxPrice: maxPrice,
      );
}

String _rupees(double value) {
  final whole = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '₹$buffer';
}

/// Shared by the saved-search list and the "Save this search" dialog.
String describeFilters({String? query, String? categoryName, double? minPrice, double? maxPrice}) {
  final parts = <String>[
    if (query != null && query.isNotEmpty) '“$query”',
    if (categoryName != null && categoryName.isNotEmpty) categoryName,
    if (minPrice != null && maxPrice != null)
      '${_rupees(minPrice)} – ${_rupees(maxPrice)}'
    else if (maxPrice != null)
      'up to ${_rupees(maxPrice)}'
    else if (minPrice != null)
      'from ${_rupees(minPrice)}',
  ];
  return parts.isEmpty ? 'Everything new' : parts.join(' · ');
}

/// One row of the in-app inbox. [payload] always has a ready-to-show `message`.
class AppNotification {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? '',
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse('${json['created_at']}') ?? DateTime.now(),
    );
  }

  AppNotification markedRead() =>
      AppNotification(id: id, type: type, payload: payload, isRead: true, createdAt: createdAt);

  String get message => payload['message']?.toString() ?? 'New activity on CampusHub';

  /// Where tapping goes: a listing (saved search or Wanted match) ...
  String? get listingId => payload['listing_id']?.toString();

  /// ... or a found report (saved search or FR-9 lost & found match).
  String? get foundReportId => payload['found_report_id']?.toString();
}
