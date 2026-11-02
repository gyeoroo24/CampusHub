import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
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

final companiesProvider = FutureProvider<List<Company>>((ref) {
  return ref.watch(placementRepositoryProvider).fetchCompanies(
        query: ref.watch(companySearchProvider),
        sort: ref.watch(companySortProvider),
      );
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

/// The full upcoming schedule (Schedule tab).
final scheduleProvider = FutureProvider<List<Ppt>>((ref) {
  return ref.watch(placementRepositoryProvider).fetchUpcomingPpts(limit: 50, kinds: ref.watch(scheduleKindsProvider));
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
  ref.invalidate(companiesProvider);
  ref.invalidate(upcomingPptsProvider);
  ref.invalidate(scheduleProvider);
  ref.invalidate(placementOverviewProvider);
}
