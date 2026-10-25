/// Generic paginated response matching FastAPI `Page[T]`.
///
/// Renamed to [PaginatedResponse] to avoid colliding with Flutter's `Page<T>`
/// from `package:flutter/widgets.dart`.
///
/// Query params: `limit` (max 50) and `offset` (items to skip).
/// The server determines [hasMore] by fetching `limit + 1` rows.
class PaginatedResponse<T> {
  final List<T> items;
  final int limit;
  final int offset;
  final bool hasMore;

  const PaginatedResponse({
    required this.items,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic jsonItem) fromJsonItem,
  ) {
    final rawItems = (json['items'] as List<dynamic>?) ?? [];
    return PaginatedResponse<T>(
      items: rawItems.map(fromJsonItem).toList(),
      limit: json['limit'] is int
          ? json['limit'] as int
          : int.tryParse(json['limit']?.toString() ?? '20') ?? 20,
      offset: json['offset'] is int
          ? json['offset'] as int
          : int.tryParse(json['offset']?.toString() ?? '0') ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  PaginatedResponse<R> map<R>(R Function(T item) mapper) {
    return PaginatedResponse<R>(
      items: items.map(mapper).toList(),
      limit: limit,
      offset: offset,
      hasMore: hasMore,
    );
  }
}

/// Backward compatibility alias
typedef PageResult<T> = PaginatedResponse<T>;
