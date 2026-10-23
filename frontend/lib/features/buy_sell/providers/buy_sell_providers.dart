import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/enums/view_mode.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/buy_sell_repository.dart';
import '../domain/buy_sell_item.dart';

final buySellRepositoryProvider = Provider<IBuySellRepository>((ref) {
  if (AppConfig.useMockData) {
    return MockBuySellRepository();
  }
  return ApiBuySellRepository(ref.watch(apiClientProvider));
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
  final ListingStatus? statusFilter;
  final double? minPrice;
  final double? maxPrice;
  final DateDurationFilter dateDuration;
  final ViewMode viewMode;

  BuySellFilterState({
    this.query = '',
    this.category = 'All',
    this.sortOption = SortOption.newest,
    this.statusFilter,
    this.minPrice,
    this.maxPrice,
    this.dateDuration = DateDurationFilter.allTime,
    this.viewMode = ViewMode.grid,
  });

  bool get hasActiveCustomFilters =>
      statusFilter != null ||
      minPrice != null ||
      maxPrice != null ||
      dateDuration != DateDurationFilter.allTime;

  int get activeFiltersCount {
    int count = 0;
    if (statusFilter != null) count++;
    if (minPrice != null || maxPrice != null) count++;
    if (dateDuration != DateDurationFilter.allTime) count++;
    return count;
  }

  BuySellFilterState copyWith({
    String? query,
    String? category,
    SortOption? sortOption,
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
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
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
