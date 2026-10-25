import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/page.dart';
import '../domain/buy_sell_item.dart';
import 'mock_buy_sell_repository.dart';

export 'api_buy_sell_repository.dart';
export 'mock_buy_sell_repository.dart';

/// Contract for Buy & Sell data operations matching FastAPI endpoints.
abstract class IBuySellRepository {
  /// Fetches listings with server-side filtering and pagination.
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
  });

  /// Standard paginated listing query returning `PaginatedResponse<ListingItem>` (`has_more`, `offset`, `limit`).
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
  });

  /// Fetches a single listing with full details and photos.
  Future<ListingItem?> getListingById(String id);

  /// Creates a new listing with optional pre-uploaded S3 photo keys.
  Future<ListingItem> addListing(
    ListingItem item, {
    List<String> photoKeys = const [],
  });

  /// Edits listing fields (seller only).
  Future<ListingItem> updateListing(
    String id, {
    String? title,
    String? description,
    double? price,
    int? categoryId,
    String? location,
  });

  /// Updates status to available, reserved, or sold (seller only, FR-5).
  Future<void> updateStatus(String id, ListingStatus newStatus);

  /// Replaces, reorders, or removes photos (seller only).
  Future<void> replacePhotos(String id, List<String> photoKeys);

  /// Soft deletes a listing (seller, Buy & Sell moderator, or admin).
  Future<void> deleteListing(String id, {String? reason});

  /// Lists all Buy & Sell categories A-Z from `GET /api/v1/buy-sell/categories`.
  Future<List<CategoryRef>> fetchCategories();

  /// Adds a missing category or gets existing one (`POST /api/v1/buy-sell/categories`).
  Future<CategoryRef> createCategory(String name);

  /// Updates or renames an existing category.
  Future<CategoryRef> updateCategory(int id, String newName);

  /// Deletes or removes a category.
  Future<void> deleteCategory(int id);
}

/// Backward compatibility alias for existing code
typedef ClientSideBuySellRepository = MockBuySellRepository;
