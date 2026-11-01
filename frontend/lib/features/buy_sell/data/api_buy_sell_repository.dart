import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_endpoints.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/page.dart';
import '../domain/buy_sell_item.dart';
import 'buy_sell_dto.dart';
import 'buy_sell_repository.dart';

/// HTTP/REST implementation of [IBuySellRepository] calling FastAPI backend.
class ApiBuySellRepository implements IBuySellRepository {
  final ApiClient apiClient;

  ApiBuySellRepository(this.apiClient);

  @override
  Future<PaginatedResponse<ListingItem>> fetchListingsPage({
    String query = '',
    int? categoryId,
    double? minPrice,
    double? maxPrice,
    List<ListingStatus>? statusList,
    String? sellerId,
    SortOption sortOption = SortOption.newest,
    int limit = 20,
    int offset = 0,
  }) async {
    final queryParams = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };

    if (query.trim().isNotEmpty) queryParams['q'] = query.trim();
    if (categoryId != null) queryParams['category_id'] = categoryId;
    if (minPrice != null) queryParams['min_price'] = minPrice;
    if (maxPrice != null) queryParams['max_price'] = maxPrice;
    if (sellerId != null && sellerId.isNotEmpty) queryParams['seller_id'] = sellerId;
    queryParams['sort'] = switch (sortOption) {
      SortOption.priceLowToHigh => 'price_asc',
      SortOption.priceHighToLow => 'price_desc',
      _ => 'newest',
    };
    if (statusList != null && statusList.isNotEmpty) {
      queryParams['status'] = statusList.map((s) => s.name).toList();
    }

    final response = await apiClient.get(
      ApiEndpoints.listings,
      queryParameters: queryParams,
    );

    if (response.data is Map<String, dynamic>) {
      return PaginatedResponse<ListingItem>.fromJson(
        response.data as Map<String, dynamic>,
        (itemJson) => BuySellListingDto.fromJson(itemJson as Map<String, dynamic>).toDomain(),
      );
    }

    return const PaginatedResponse(items: [], limit: 20, offset: 0, hasMore: false);
  }

  @override
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    int? categoryId,
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
    double? minPrice,
    double? maxPrice,
    DateTime? fromDate,
    DateTime? toDate,
    String? sellerId,
    int page = 1,
    int limit = 50,
    int offset = 0,
  }) async {
    final effectiveOffset = offset > 0 ? offset : (page > 1 ? (page - 1) * limit : 0);

    final statusList = statusFilter != null ? [statusFilter] : null;

    final paged = await fetchListingsPage(
      query: query,
      categoryId: categoryId,
      minPrice: minPrice,
      maxPrice: maxPrice,
      statusList: statusList,
      sellerId: sellerId,
      limit: limit,
      offset: effectiveOffset,
    );

    var items = paged.items;

    // Client-side date filtering if fromDate / toDate supplied (FR-6)
    if (fromDate != null) {
      items = items.where((it) => it.createdAt.isAfter(fromDate)).toList();
    }
    if (toDate != null) {
      items = items.where((it) => it.createdAt.isBefore(toDate)).toList();
    }

    // Client-side category string fallback if category is text and categoryId was null
    if (category != 'All' && categoryId == null) {
      items = items.where((it) => it.category.name.toLowerCase() == category.toLowerCase()).toList();
    }

    return items;
  }

  @override
  Future<ListingItem?> getListingById(String id) async {
    final response = await apiClient.get(ApiEndpoints.listing(id));
    if (response.data != null && response.data is Map<String, dynamic>) {
      return BuySellListingDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return null;
  }

  @override
  Future<ListingItem> addListing(
    ListingItem item, {
    List<String> photoKeys = const [],
  }) async {
    final dto = BuySellListingDto.fromDomain(item);
    final response = await apiClient.post(
      ApiEndpoints.listings,
      data: dto.toCreateJson(photoKeys: photoKeys),
    );

    if (response.data != null && response.data is Map<String, dynamic>) {
      return BuySellListingDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return item;
  }

  @override
  Future<ListingItem> updateListing(
    String id, {
    String? title,
    String? description,
    double? price,
    int? categoryId,
    String? location,
    bool? negotiable,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (description != null) payload['description'] = description;
    if (price != null) payload['price'] = price;
    if (categoryId != null) payload['category_id'] = categoryId;
    if (location != null) payload['location'] = location;
    if (negotiable != null) payload['negotiable'] = negotiable;

    final response = await apiClient.patch(
      ApiEndpoints.listing(id),
      data: payload,
    );

    final data = response.data as Map<String, dynamic>;
    return BuySellListingDto.fromJson(data).toDomain();
  }

  @override
  Future<void> setWatching(String id, bool watching) async {
    if (watching) {
      await apiClient.put(ApiEndpoints.listingWatch(id));
    } else {
      await apiClient.delete(ApiEndpoints.listingWatch(id));
    }
  }

  @override
  Future<List<ListingItem>> fetchWatchedListings() async {
    final response = await apiClient.get(ApiEndpoints.myWatchedListings, queryParameters: {'limit': 50});
    final items = (response.data as Map<String, dynamic>)['items'] as List? ?? const [];
    return items.map((j) => BuySellListingDto.fromJson(j as Map<String, dynamic>).toDomain()).toList();
  }

  @override
  Future<void> updateStatus(String id, ListingStatus newStatus) async {
    await apiClient.patch(
      ApiEndpoints.listingStatus(id),
      data: {'status': newStatus.name},
    );
  }

  @override
  Future<void> replacePhotos(String id, List<String> photoKeys) async {
    await apiClient.put(
      ApiEndpoints.listingPhotos(id),
      data: {'photo_keys': photoKeys},
    );
  }

  @override
  Future<void> deleteListing(String id, {String? reason, String? severity}) async {
    final queryParams = <String, dynamic>{};
    if (reason != null && reason.trim().isNotEmpty) {
      queryParams['reason'] = reason.trim();
    }
    if (severity != null) queryParams['severity'] = severity;

    await apiClient.delete(
      ApiEndpoints.listing(id),
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  @override
  Future<List<CategoryRef>> fetchCategories() async {
    final response = await apiClient.get(ApiEndpoints.buySellCategories);
    if (response.data is List) {
      return (response.data as List<dynamic>)
          .map((item) => CategoryRef.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<CategoryRef> createCategory(String name) async {
    final response = await apiClient.post(
      ApiEndpoints.buySellCategories,
      data: {'name': name.trim()},
    );

    return CategoryRef.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<CategoryRef?> suggestCategory(String title) async {
    if (title.trim().isEmpty) return null;
    final response = await apiClient.get(
      ApiEndpoints.buySellCategorySuggest,
      queryParameters: {'title': title.trim()},
    );
    final category = (response.data as Map<String, dynamic>)['category'];
    return category == null ? null : CategoryRef.fromJson(category as Map<String, dynamic>);
  }

  // The API has no rename for categories, so say so rather than reporting a success that never
  // happened. Mock mode still supports it.
  @override
  Future<CategoryRef> updateCategory(int id, String newName) async {
    throw Exception("The server doesn't support renaming categories yet.");
  }

  @override
  Future<void> deleteCategory(int id, {int? moveTo}) async {
    await apiClient.delete(
      '${ApiEndpoints.buySellCategories}/$id',
      queryParameters: {if (moveTo != null) 'move_to': moveTo},
    );
  }

}
