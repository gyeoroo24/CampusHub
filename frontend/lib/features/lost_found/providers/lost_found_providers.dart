import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/enums/date_preset.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/enums/view_mode.dart';
import '../../../core/models/category_ref.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart' show PaginatedFeedState;
import '../data/lost_found_repository.dart';
import '../domain/lost_found_item.dart';

class LostFoundFilterState {
  final String query;
  final String category;
  final DatePresetFilter datePreset;
  final DateTimeRange? customDateRange;
  final SortOption sortOption;
  final PostType? typeFilter;
  final ViewMode viewMode;

  LostFoundFilterState({
    this.query = '',
    this.category = 'All',
    this.datePreset = DatePresetFilter.all,
    this.customDateRange,
    this.sortOption = SortOption.newest,
    this.typeFilter,
    this.viewMode = ViewMode.grid,
  });

  /// The active date range computed from custom selection or date preset
  DateTimeRange? get dateRange => customDateRange ?? datePreset.toDateTimeRange();

  bool get hasActiveFilters =>
      category != 'All' ||
      datePreset != DatePresetFilter.all ||
      customDateRange != null ||
      query.isNotEmpty ||
      sortOption != SortOption.newest;

  LostFoundFilterState copyWith({
    String? query,
    String? category,
    DatePresetFilter? datePreset,
    DateTimeRange? customDateRange,
    bool clearCustomDateRange = false,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    SortOption? sortOption,
    PostType? typeFilter,
    bool clearTypeFilter = false,
    ViewMode? viewMode,
  }) {
    return LostFoundFilterState(
      query: query ?? this.query,
      category: category ?? this.category,
      datePreset: datePreset ?? this.datePreset,
      customDateRange: (clearCustomDateRange || clearDateRange)
          ? null
          : (customDateRange ?? dateRange ?? this.customDateRange),
      sortOption: sortOption ?? this.sortOption,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      viewMode: viewMode ?? this.viewMode,
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
        dateRange: filter.dateRange,
        sortOption: filter.sortOption,
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
        dateRange: filter.dateRange,
        sortOption: filter.sortOption,
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

final possibleMatchesForItemProvider =
    FutureProvider.family<List<LostFoundItem>, LostFoundItem>((ref, item) async {
  return ref.watch(lostFoundRepositoryProvider).getPossibleMatches(item);
});

final myLostReportsProvider = FutureProvider<List<LostFoundItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest) return [];
  final repo = ref.watch(lostFoundRepositoryProvider);
  final all = await repo.fetchReports(type: PostType.lost, limit: 100);
  return all
      .where((r) =>
          r.reporter.id == user.id ||
          r.reporter.name == user.name ||
          (r.reporterContact?.email != null && r.reporterContact!.email == user.email))
      .toList();
});

final myFoundReportsProvider = FutureProvider<List<LostFoundItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest) return [];
  final repo = ref.watch(lostFoundRepositoryProvider);
  final all = await repo.fetchReports(type: PostType.found, limit: 100);
  return all
      .where((r) =>
          r.reporter.id == user.id ||
          r.reporter.name == user.name ||
          (r.reporterContact?.email != null && r.reporterContact!.email == user.email))
      .toList();
});
