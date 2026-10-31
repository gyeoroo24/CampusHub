import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/page.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/config/server_config.dart';
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
  final Set<ReportStatus> selectedStatuses;

  LostFoundFilterState({
    this.query = '',
    this.category = 'All',
    this.datePreset = DatePresetFilter.all,
    this.customDateRange,
    this.sortOption = SortOption.newest,
    this.typeFilter,
    this.viewMode = ViewMode.grid,
    Set<ReportStatus>? selectedStatuses,
  }) : selectedStatuses = selectedStatuses ?? defaultStatuses;

  /// What the feed shows until the user changes it: only items still being looked for.
  static const defaultStatuses = {ReportStatus.open};

  /// The active date range computed from custom selection or date preset
  DateTimeRange? get dateRange => customDateRange ?? datePreset.toDateTimeRange();

  bool get isAllSelected =>
      datePreset == DatePresetFilter.all &&
      customDateRange == null &&
      selectedStatuses.length >= 3;

  bool get hasActiveFilters =>
      category != 'All' ||
      datePreset != DatePresetFilter.all ||
      customDateRange != null ||
      query.isNotEmpty ||
      sortOption != SortOption.newest ||
      !setEquals(selectedStatuses, defaultStatuses);

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
    Set<ReportStatus>? selectedStatuses,
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
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
    );
  }
}

final lostFoundFilterProvider = StateProvider<LostFoundFilterState>((ref) => LostFoundFilterState());

final lostFoundRepositoryProvider = Provider<ILostFoundRepository>((ref) {
  final serverConfig = ref.watch(serverConfigProvider);
  if (serverConfig.useMockData) {
    return MockLostFoundRepository();
  }
  return ApiLostFoundRepository(ref.watch(apiClientProvider));
});

/// The full report (photos, reporter contact for signed-in users). Feed cards carry only the
/// summary, so the detail view loads this when it opens.
final lostFoundDetailProvider =
    FutureProvider.autoDispose.family<LostFoundItem?, ({String id, PostType kind})>((ref, key) {
  ref.watch(currentUserProvider); // contact details depend on who is asking
  return ref.watch(lostFoundRepositoryProvider).getReportById(key.id, type: key.kind);
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

  /// One page from the server with the current filters. Category chips hold names, so the name is
  /// turned into the server's category id; a preset chip with no server category matches nothing.
  Future<PaginatedResponse<LostFoundItem>?> _fetch(int offset) async {
    final repo = _ref.read(lostFoundRepositoryProvider);
    final filter = _ref.read(lostFoundFilterProvider);
    int? categoryId;
    if (filter.category != 'All') {
      final categories = await _ref.read(lostFoundCategoriesProvider.future);
      final match = categories.where((c) => c.name.toLowerCase() == filter.category.toLowerCase());
      if (match.isEmpty) return null;
      categoryId = match.first.id;
    }
    return repo.fetchReportsPage(
      type: _kind,
      query: filter.query,
      categoryId: categoryId,
      dateRange: filter.dateRange,
      sortOption: filter.sortOption,
      statusList: filter.selectedStatuses.toList(),
      limit: _pageSize,
      offset: offset,
    );
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoadingInitial: true, clearError: true);
    try {
      final paged = await _fetch(0);
      state = PaginatedFeedState(
        items: paged?.items ?? const [],
        isLoadingInitial: false,
        isLoadingMore: false,
        hasMore: paged?.hasMore ?? false,
        offset: paged?.items.length ?? 0,
      );
    } catch (e) {
      state = state.copyWith(isLoadingInitial: false, errorMessage: errorText(e));
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingInitial || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final paged = await _fetch(state.offset);
      state = state.copyWith(
        items: [...state.items, ...?paged?.items],
        isLoadingMore: false,
        hasMore: paged?.hasMore ?? false,
        offset: state.offset + (paged?.items.length ?? 0),
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, errorMessage: errorText(e));
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

/// Every report the signed-in user filed of one kind, newest first. Asked for by reporter_id,
/// page by page (the API returns at most 50 per page), so older reports are included too.
Future<List<LostFoundItem>> _myReports(Ref ref, PostType type) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest) return [];
  final repo = ref.watch(lostFoundRepositoryProvider);
  final mine = <LostFoundItem>[];
  for (var offset = 0; offset < 500; offset += 50) {
    final page = await repo.fetchReportsPage(type: type, reporterId: user.id, limit: 50, offset: offset);
    mine.addAll(page.items);
    if (!page.hasMore) break;
  }
  return mine;
}

final myLostReportsProvider = FutureProvider<List<LostFoundItem>>((ref) => _myReports(ref, PostType.lost));

final myFoundReportsProvider = FutureProvider<List<LostFoundItem>>((ref) => _myReports(ref, PostType.found));
