import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/enums/sort_option.dart';
import '../domain/buy_sell_item.dart';
import 'buy_sell_dto.dart';
import 'buy_sell_repository.dart';

/// HTTP/REST implementation of [IBuySellRepository] calling FastAPI backend.
class ApiBuySellRepository implements IBuySellRepository {
  final ApiClient apiClient;

  ApiBuySellRepository(this.apiClient);

  @override
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
    double? minPrice,
    double? maxPrice,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int limit = 50,
  }) async {
    // Map SortOption enum to API query param
    String sortByParam;
    switch (sortOption) {
      case SortOption.oldest:
        sortByParam = 'created_at_asc';
        break;
      case SortOption.priceLowToHigh:
        sortByParam = 'price_asc';
        break;
      case SortOption.priceHighToLow:
        sortByParam = 'price_desc';
        break;
      case SortOption.discountHighToLow:
        sortByParam = 'discount_desc';
        break;
      case SortOption.newest:
        sortByParam = 'created_at_desc';
        break;
    }

    final queryParams = <String, dynamic>{
      'page': page,
      'limit': limit,
      'sort_by': sortByParam,
    };

    if (query.isNotEmpty) queryParams['query'] = query;
    if (category != 'All') queryParams['category'] = category;
    if (statusFilter != null) queryParams['status'] = statusFilter.name;
    if (minPrice != null) queryParams['min_price'] = minPrice;
    if (maxPrice != null) queryParams['max_price'] = maxPrice;
    if (fromDate != null) queryParams['from_date'] = fromDate.toIso8601String();
    if (toDate != null) queryParams['to_date'] = toDate.toIso8601String();

    final response = await apiClient.get(
      ApiEndpoints.buySellListings,
      queryParameters: queryParams,
    );

    final rawData = response.data;
    List<dynamic> itemsList = [];

    if (rawData is List) {
      itemsList = rawData;
    } else if (rawData is Map<String, dynamic>) {
      // In case backend wraps in { "items": [...], "total": 10 }
      itemsList = (rawData['items'] as List<dynamic>?) ?? [];
    }

    return itemsList
        .map((item) => BuySellListingDto.fromJson(item as Map<String, dynamic>).toDomain())
        .toList();
  }

  @override
  Future<ListingItem?> getListingById(String id) async {
    final response = await apiClient.get(ApiEndpoints.buySellListing(id));
    if (response.data != null && response.data is Map<String, dynamic>) {
      return BuySellListingDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return null;
  }

  @override
  Future<ListingItem> addListing(ListingItem item) async {
    final dto = BuySellListingDto.fromDomain(item);
    final response = await apiClient.post(
      ApiEndpoints.buySellListings,
      data: dto.toJson(),
    );

    if (response.data != null && response.data is Map<String, dynamic>) {
      return BuySellListingDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return item;
  }

  @override
  Future<void> updateStatus(String id, ListingStatus newStatus) async {
    await apiClient.patch(
      ApiEndpoints.buySellStatus(id),
      data: {'status': newStatus.name},
    );
  }

  @override
  Future<void> deleteListing(String id) async {
    await apiClient.delete(ApiEndpoints.buySellListing(id));
  }
}
