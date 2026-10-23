import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/models/category_ref.dart';
import '../../auth/providers/auth_providers.dart';
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

final lostFoundCategoriesProvider = FutureProvider<List<CategoryRef>>((ref) async {
  final repo = ref.watch(lostFoundRepositoryProvider);
  return repo.fetchCategories();
});
