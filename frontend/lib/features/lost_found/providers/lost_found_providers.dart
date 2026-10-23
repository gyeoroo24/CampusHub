import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/models/category_ref.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart' show PaginatedFeedState;
import '../data/lost_found_repository.dart';
import '../domain/lost_found_item.dart';

class LostFoundFilterState {
  final String query;
  final String category;
  final DateTimeRange? dateRange;
  final SortOption sortOption;
  final PostType? typeFilter;

  LostFoundFilterState({
    this.query = '',
    this.category = 'All',
    this.dateRange,
    this.sortOption = SortOption.newest,
    this.typeFilter,
  });

  LostFoundFilterState copyWith({
    String? query,
    String? category,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    SortOption? sortOption,
    PostType? typeFilter,
    bool clearTypeFilter = false,
  }) {
    return LostFoundFilterState(
      query: query ?? this.query,
      category: category ?? this.category,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      sortOption: sortOption ?? this.sortOption,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
    );
  }
}

final lostFoundFilterProvider = StateProvider<LostFoundFilterState>((ref) => LostFoundFilterState());

final lostFoundRepositoryProvider = Provider<ILostFoundRepository>((ref) {
  if (AppConfig.useMockData) {
    return MockLostFoundRepository();
  }
  return ApiLostFoundRepository(ref.watch(apiClientProvider));
});

final lostFoundCategoriesProvider = FutureProvider<List<CategoryRef>>((ref) async {
  final repo = ref.watch(lostFoundRepositoryProvider);
  return repo.fetchCategories();
});

// ─────────────────────────────────────────────────────────────────────────────
// Paginated Lost & Found Notifier
// ─────────────────────────────────────────────────────────────────────────────

class LostFoundPaginationNotifier extends StateNotifier<PaginatedFeedState<LostFoundItem>> {
  final Ref _ref;
  final PostType _kind;
  static const int _pageSize = 6;

  LostFoundPaginationNotifier(this._ref, this._kind)
      : super(const PaginatedFeedState(isLoadingInitial: true)) {
    loadInitial();
    _ref.listen<LostFoundFilterState>(lostFoundFilterProvider, (_, __) {
      loadInitial();
    });
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoadingInitial: true, clearError: true);
    try {
      final repo = _ref.read(lostFoundRepositoryProvider);
      final filter = _ref.read(lostFoundFilterProvider);

      final paged = await repo.fetchReportsPage(
        type: _kind,
        query: filter.query,
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
      final repo = _ref.read(lostFoundRepositoryProvider);
      final filter = _ref.read(lostFoundFilterProvider);

      final paged = await repo.fetchReportsPage(
        type: _kind,
        query: filter.query,
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

  void updateItemStatusLocally(String id, ReportStatus newStatus) {
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

final lostReportsPaginationProvider =
    StateNotifierProvider<LostFoundPaginationNotifier, PaginatedFeedState<LostFoundItem>>((ref) {
  return LostFoundPaginationNotifier(ref, PostType.lost);
});

final foundReportsPaginationProvider =
    StateNotifierProvider<LostFoundPaginationNotifier, PaginatedFeedState<LostFoundItem>>((ref) {
  return LostFoundPaginationNotifier(ref, PostType.found);
});

// ─────────────────────────────────────────────────────────────────────────────
// Legacy providers for SuperSearchBar & tests
// ─────────────────────────────────────────────────────────────────────────────

final lostReportsProvider = FutureProvider<List<LostFoundItem>>((ref) async {
  final repo = ref.watch(lostFoundRepositoryProvider);
  final filter = ref.watch(lostFoundFilterProvider);

  return repo.fetchReports(
    type: PostType.lost,
    query: filter.query,
    category: filter.category,
    dateRange: filter.dateRange,
    sortOption: filter.sortOption,
  );
});

final foundReportsProvider = FutureProvider<List<LostFoundItem>>((ref) async {
  final repo = ref.watch(lostFoundRepositoryProvider);
  final filter = ref.watch(lostFoundFilterProvider);

  return repo.fetchReports(
    type: PostType.found,
    query: filter.query,
    category: filter.category,
    dateRange: filter.dateRange,
    sortOption: filter.sortOption,
  );
});
