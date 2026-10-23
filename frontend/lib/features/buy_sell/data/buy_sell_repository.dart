import '../domain/buy_sell_item.dart';
import '../../../core/enums/sort_option.dart';
import 'mock_buy_sell_repository.dart';

export 'mock_buy_sell_repository.dart';
export 'api_buy_sell_repository.dart';

/// Contract for Buy & Sell data operations.
abstract class IBuySellRepository {
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
  });

  Future<ListingItem?> getListingById(String id);

  Future<ListingItem> addListing(ListingItem item);

  Future<void> updateStatus(String id, ListingStatus newStatus);

  Future<void> deleteListing(String id);
}

/// Backward compatibility alias for existing code
typedef ClientSideBuySellRepository = MockBuySellRepository;
