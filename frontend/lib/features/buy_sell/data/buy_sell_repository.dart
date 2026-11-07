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
    bool? negotiable,
  });

  /// Price watch: be told when the price changes or it's marked negotiable.
  Future<void> setWatching(String id, bool watching);

  /// Listings the signed-in user is watching, most recently watched first.
  Future<List<ListingItem>> fetchWatchedListings();

  /// Bookmark or un-bookmark a listing for the signed-in user.
  Future<void> setBookmarked(String id, bool bookmarked);

  /// Ids of every listing the signed-in user bookmarked.
  Future<Set<String>> fetchBookmarkedIds();

  /// Listings the signed-in user bookmarked, most recent first.
  Future<List<ListingItem>> fetchBookmarkedListings();

  /// Listings with these ids, in order, leaving out ones that are gone (a guest's on-device bookmarks).
  Future<List<ListingItem>> lookupListings(List<String> ids);

  /// Copies bookmarks made as a guest to the account that just signed in.
  Future<void> importBookmarks(List<String> ids);

  /// Updates status to available, reserved, or sold (seller only, FR-5).
  Future<void> updateStatus(String id, ListingStatus newStatus);

  /// Replaces, reorders, or removes photos (seller only).
  Future<void> replacePhotos(String id, List<String> photoKeys);

  /// Soft deletes a listing (seller, Buy & Sell moderator, or admin).
  /// [severity] matters only when a moderator removes a listing that was reported (it becomes a strike).
  Future<void> deleteListing(String id, {String? reason, String? severity});

  /// Lists all Buy & Sell categories A-Z from `GET /api/v1/buy-sell/categories`.
  Future<List<CategoryRef>> fetchCategories();

  /// Adds a missing category or gets existing one (`POST /api/v1/buy-sell/categories`).
  Future<CategoryRef> createCategory(String name);

  /// Nearest existing category for a typed title (`GET /api/v1/buy-sell/categories/suggest`)
  /// - a hint only, never auto-applied. Returns null if nothing existing fits
  /// well, or if the suggestion model isn't available (e.g. mock mode).
  Future<CategoryRef?> suggestCategory(String title);

  /// Updates or renames an existing category.
  Future<CategoryRef> updateCategory(int id, String newName);

  /// Deletes a category (that module's moderators and the admin). If posts or saved searches use
  /// it, they are moved to [moveTo]; without one the server answers 409 saying how many use it.
  Future<void> deleteCategory(int id, {int? moveTo, bool deletePosts = false});
}

/// Backward compatibility alias for existing code
typedef ClientSideBuySellRepository = MockBuySellRepository;
