import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/enums/view_mode.dart';
import '../../../core/models/category_ref.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/buy_sell_repository.dart';
import '../domain/buy_sell_item.dart';

final buySellRepositoryProvider = Provider<IBuySellRepository>((ref) {
  if (AppConfig.useMockData) {
    return MockBuySellRepository();
  }
  return ApiBuySellRepository(ref.watch(apiClientProvider));
});

final buySellCategoriesProvider = FutureProvider<List<CategoryRef>>((ref) async {
  final repo = ref.watch(buySellRepositoryProvider);
  return repo.fetchCategories();
});

enum DateDurationFilter {
  allTime('All Time'),
  today('Today'),
  thisWeek('Past 7 Days'),
  thisMonth('Past 30 Days');

  final String label;
  const DateDurationFilter(this.label);
}

class BuySellFilterState {
  final String query;
  final String category;
  final SortOption sortOption;
  final Set<ListingStatus> selectedStatuses;
  final double? minPrice;
  final double? maxPrice;
  final DateDurationFilter dateDuration;
  final ViewMode viewMode;

  BuySellFilterState({
    this.query = '',
    this.category = 'All',
    this.sortOption = SortOption.newest,
    Set<ListingStatus>? selectedStatuses,
    ListingStatus? statusFilter,
    this.minPrice,
    this.maxPrice,
    this.dateDuration = DateDurationFilter.allTime,
    this.viewMode = ViewMode.grid,
  }) : selectedStatuses = selectedStatuses ??
            (statusFilter != null
                ? {statusFilter}
                : {ListingStatus.available, ListingStatus.reserved, ListingStatus.sold});

  ListingStatus? get statusFilter =>
      selectedStatuses.length == 1 ? selectedStatuses.first : null;

  bool get hasActiveCustomFilters =>
      (selectedStatuses.isNotEmpty && selectedStatuses.length < 3) ||
      minPrice != null ||
      maxPrice != null ||
      dateDuration != DateDurationFilter.allTime;

  int get activeFiltersCount {
    int count = 0;
    if (selectedStatuses.isNotEmpty && selectedStatuses.length < 3) count++;
    if (minPrice != null || maxPrice != null) count++;
    if (dateDuration != DateDurationFilter.allTime) count++;
    return count;
  }

  BuySellFilterState copyWith({
    String? query,
    String? category,
    SortOption? sortOption,
    Set<ListingStatus>? selectedStatuses,
    ListingStatus? statusFilter,
    bool clearStatusFilter = false,
    double? minPrice,
    bool clearMinPrice = false,
    double? maxPrice,
    bool clearMaxPrice = false,
    DateDurationFilter? dateDuration,
    ViewMode? viewMode,
  }) {
    return BuySellFilterState(
      query: query ?? this.query,
      category: category ?? this.category,
      sortOption: sortOption ?? this.sortOption,
      selectedStatuses: clearStatusFilter
          ? {ListingStatus.available, ListingStatus.reserved, ListingStatus.sold}
          : ((selectedStatuses != null && selectedStatuses.isEmpty)
              ? {ListingStatus.available}
              : (selectedStatuses ??
                  (statusFilter != null ? {statusFilter} : this.selectedStatuses))),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      dateDuration: dateDuration ?? this.dateDuration,
      viewMode: viewMode ?? this.viewMode,
    );
  }

  BuySellFilterState resetAdvancedFilters() {
    return copyWith(
      clearStatusFilter: true,
      clearMinPrice: true,
      clearMaxPrice: true,
      dateDuration: DateDurationFilter.allTime,
    );
  }
}

final buySellFilterProvider = StateProvider<BuySellFilterState>((ref) => BuySellFilterState());

// ─────────────────────────────────────────────────────────────────────────────
// Paginated Feed State & Infinite Scrolling Notifier
// ─────────────────────────────────────────────────────────────────────────────

class PaginatedFeedState<T> {
  final List<T> items;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final int offset;
  final String? errorMessage;

  const PaginatedFeedState({
    this.items = const [],
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.offset = 0,
    this.errorMessage,
  });

  PaginatedFeedState<T> copyWith({
    List<T>? items,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    bool? hasMore,
    int? offset,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PaginatedFeedState<T>(
      items: items ?? this.items,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class BuySellPaginationNotifier extends StateNotifier<PaginatedFeedState<ListingItem>> {
  final Ref _ref;
  static const int _pageSize = 8;

  BuySellPaginationNotifier(this._ref) : super(const PaginatedFeedState(isLoadingInitial: true)) {
    loadInitial();
    _ref.listen<BuySellFilterState>(buySellFilterProvider, (_, __) {
      loadInitial();
    });
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoadingInitial: true, clearError: true);
    try {
      final repo = _ref.read(buySellRepositoryProvider);
      final filter = _ref.read(buySellFilterProvider);

      final statusList = (filter.selectedStatuses.isEmpty || filter.selectedStatuses.length == 3)
          ? null
          : filter.selectedStatuses.toList();
      final paged = await repo.fetchListingsPage(
        query: filter.query,
        minPrice: filter.minPrice,
        maxPrice: filter.maxPrice,
        statusList: statusList,
        limit: _pageSize,
        offset: 0,
      );

      var items = paged.items;
      if (filter.category != 'All') {
        items = items.where((it) => it.category.name.toLowerCase() == filter.category.toLowerCase()).toList();
      }

      state = PaginatedFeedState(
        items: items,
        isLoadingInitial: false,
        isLoadingMore: false,
        hasMore: paged.hasMore,
        offset: paged.items.length,
      );
    } catch (e) {
      state = state.copyWith(isLoadingInitial: false, errorMessage: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingInitial || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final repo = _ref.read(buySellRepositoryProvider);
      final filter = _ref.read(buySellFilterProvider);

      final statusList = (filter.selectedStatuses.isEmpty || filter.selectedStatuses.length == 3)
          ? null
          : filter.selectedStatuses.toList();
      final paged = await repo.fetchListingsPage(
        query: filter.query,
        minPrice: filter.minPrice,
        maxPrice: filter.maxPrice,
        statusList: statusList,
        limit: _pageSize,
        offset: state.offset,
      );

      var newItems = paged.items;
      if (filter.category != 'All') {
        newItems = newItems.where((it) => it.category.name.toLowerCase() == filter.category.toLowerCase()).toList();
      }

      state = state.copyWith(
        items: [...state.items, ...newItems],
        isLoadingMore: false,
        hasMore: paged.hasMore,
        offset: state.offset + paged.items.length,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, errorMessage: e.toString());
    }
  }

  void updateItemStatusLocally(String id, ListingStatus newStatus) {
    final updated = state.items.map((it) {
      if (it.id == id) {
        return it.copyWith(status: newStatus);
      }
      return it;
    }).toList();
    state = state.copyWith(items: updated);
  }

  void removeItemLocally(String id) {
    final updated = state.items.where((it) => it.id != id).toList();
    state = state.copyWith(items: updated);
  }
}

final buySellPaginationProvider =
    StateNotifierProvider<BuySellPaginationNotifier, PaginatedFeedState<ListingItem>>((ref) {
  return BuySellPaginationNotifier(ref);
});

// ─────────────────────────────────────────────────────────────────────────────
// Legacy listing provider for backward compatibility with SuperSearchBar & tests
// ─────────────────────────────────────────────────────────────────────────────
final buySellListingsProvider = FutureProvider<List<ListingItem>>((ref) async {
  final repo = ref.watch(buySellRepositoryProvider);
  final filter = ref.watch(buySellFilterProvider);

  DateTime? fromDate;
  final now = DateTime.now();
  switch (filter.dateDuration) {
    case DateDurationFilter.today:
      fromDate = DateTime(now.year, now.month, now.day);
      break;
    case DateDurationFilter.thisWeek:
      fromDate = now.subtract(const Duration(days: 7));
      break;
    case DateDurationFilter.thisMonth:
      fromDate = now.subtract(const Duration(days: 30));
      break;
    case DateDurationFilter.allTime:
      fromDate = null;
      break;
  }

  return repo.fetchListings(
    query: filter.query,
    category: filter.category,
    sortOption: filter.sortOption,
    statusFilter: filter.statusFilter,
    minPrice: filter.minPrice,
    maxPrice: filter.maxPrice,
    fromDate: fromDate,
  );
});

final myBuySellListingsProvider = FutureProvider<List<ListingItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest) return [];
  final repo = ref.watch(buySellRepositoryProvider);
  final all = await repo.fetchListings();
  return all
      .where((it) =>
          it.seller.id == user.id ||
          it.seller.name == user.name ||
          (it.sellerContact?.email != null && it.sellerContact!.email == user.email))
      .toList();
});
