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

/// Company list search box and sort on the Placements tab.
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

final upcomingPptsProvider = FutureProvider<List<Ppt>>((ref) {
  return ref.watch(placementRepositoryProvider).fetchUpcomingPpts();
});

/// Newest interview experiences across all companies (Placements tab).
final recentInterviewsProvider = FutureProvider<List<InterviewExperience>>((ref) {
  ref.watch(currentUserProvider); // names and "mine" depend on who is viewing
  return ref.watch(placementRepositoryProvider).fetchInterviews(limit: 5);
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

final companyForumIdProvider = FutureProvider.family<String, String>((ref, companyId) {
  return ref.watch(placementRepositoryProvider).companyForumId(companyId);
});

final forumThreadsProvider = FutureProvider.family<List<ForumThread>, String>((ref, forumId) {
  return ref.watch(placementRepositoryProvider).fetchThreads(forumId);
});

final forumThreadProvider = FutureProvider.family<ForumThread, String>((ref, threadId) {
  ref.watch(currentUserProvider);
  return ref.watch(placementRepositoryProvider).getThread(threadId);
});

/// Refresh everything a company page and the Placements tab show after a change.
void refreshCompany(WidgetRef ref, String companyId) {
  ref.invalidate(companyProvider(companyId));
  ref.invalidate(hiringStatsProvider(companyId));
  ref.invalidate(companyInterviewsProvider(companyId));
  ref.invalidate(companiesProvider);
  ref.invalidate(upcomingPptsProvider);
  ref.invalidate(recentInterviewsProvider);
  ref.invalidate(placementOverviewProvider);
}
