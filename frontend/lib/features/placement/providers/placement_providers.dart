import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/placement_repository.dart';
import '../domain/placement_models.dart';

final placementRepositoryProvider = Provider<IPlacementRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockPlacementRepository();
  }
  return ApiPlacementRepository(ref.watch(apiClientProvider));
});

/// Company list search box and sort on the Placement Hub page. The page clears the search each time it
/// opens, so coming back from a company shows every company again.
final companySearchProvider = StateProvider<String>((ref) => '');
final companySortProvider = StateProvider<String>((ref) => 'name');

/// The Companies tab's page-at-a-time list: opening the hub used to fetch every company (hundreds,
/// 50 a page) before showing anything. This loads one page up front and more as the grid is scrolled.
class CompaniesPageState {
  final List<Company> items;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;

  const CompaniesPageState({
    this.items = const [],
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
  });

  CompaniesPageState copyWith({
    List<Company>? items,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) =>
      CompaniesPageState(
        items: items ?? this.items,
        isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class CompaniesPaginationNotifier extends StateNotifier<CompaniesPageState> {
  final Ref _ref;
  static const _pageSize = 20;

  CompaniesPaginationNotifier(this._ref) : super(const CompaniesPageState(isLoadingInitial: true)) {
    loadInitial();
    _ref.listen(companySearchProvider, (_, __) => loadInitial());
    _ref.listen(companySortProvider, (_, __) => loadInitial());
  }

  Future<void> loadInitial() async {
    state = state.copyWith(isLoadingInitial: true, clearError: true);
    try {
      final page = await _ref.read(placementRepositoryProvider).fetchCompaniesPage(
          query: _ref.read(companySearchProvider), sort: _ref.read(companySortProvider), limit: _pageSize);
      state = CompaniesPageState(items: page.items, hasMore: page.hasMore);
    } catch (e) {
      state = state.copyWith(isLoadingInitial: false, errorMessage: errorText(e));
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingInitial || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _ref.read(placementRepositoryProvider).fetchCompaniesPage(
          query: _ref.read(companySearchProvider),
          sort: _ref.read(companySortProvider),
          limit: _pageSize,
          offset: state.items.length);
      state = state.copyWith(items: [...state.items, ...page.items], isLoadingMore: false, hasMore: page.hasMore);
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, errorMessage: errorText(e));
    }
  }
}

final companiesPaginationProvider = StateNotifierProvider<CompaniesPaginationNotifier, CompaniesPageState>((ref) {
  return CompaniesPaginationNotifier(ref);
});

final placementOverviewProvider = FutureProvider<PlacementOverview>((ref) {
  return ref.watch(placementRepositoryProvider).fetchOverview();
});

/// The next few dates on the placement schedule (the landing page's "Coming up" strip).
final upcomingPptsProvider = FutureProvider<List<Ppt>>((ref) {
  return ref.watch(placementRepositoryProvider).fetchUpcomingPpts(limit: 6);
});

/// Which kinds the Schedule tab shows (empty = all).
final scheduleKindsProvider = StateProvider<Set<PptKind>>((ref) => const {});

/// Schedule tab: dates that have passed instead of upcoming ones (newest first).
final schedulePastProvider = StateProvider<bool>((ref) => false);

/// The Schedule tab's dates.
final scheduleProvider = FutureProvider<List<Ppt>>((ref) {
  return ref.watch(placementRepositoryProvider).fetchUpcomingPpts(
      limit: 50, kinds: ref.watch(scheduleKindsProvider), past: ref.watch(schedulePastProvider));
});

final companyProvider = FutureProvider.family<Company, String>((ref, companyId) {
  ref.watch(currentUserProvider); // viewer_can_manage depends on who is viewing
  return ref.watch(placementRepositoryProvider).getCompany(companyId);
});

final hiringStatsProvider = FutureProvider.family<HiringStats, String>((ref, companyId) {
  return ref.watch(placementRepositoryProvider).fetchHiringStats(companyId);
});

final companyInterviewsProvider = FutureProvider.family<List<InterviewExperience>, String>((ref, companyId) {
  ref.watch(currentUserProvider);
  return ref.watch(placementRepositoryProvider).fetchInterviews(companyId: companyId, limit: 50);
});

/// Refresh everything a company page and the Placement Hub page show after a change.
void refreshCompany(WidgetRef ref, String companyId) {
  ref.invalidate(companyProvider(companyId));
  ref.invalidate(hiringStatsProvider(companyId));
  ref.invalidate(companyInterviewsProvider(companyId));
  ref.read(companiesPaginationProvider.notifier).loadInitial();
  ref.invalidate(upcomingPptsProvider);
  ref.invalidate(scheduleProvider);
  ref.invalidate(placementOverviewProvider);
}
