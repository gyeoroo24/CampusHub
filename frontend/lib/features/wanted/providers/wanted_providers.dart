import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../../core/models/user_ref.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/domain/buy_sell_item.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../data/wanted_repository.dart';
import '../domain/wanted_post.dart';

final wantedRepositoryProvider = Provider<IWantedRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    final user = ref.watch(currentUserProvider);
    return user == null || user.isGuest
        ? MockWantedRepository()
        : MockWantedRepository(author: UserRef(id: user.id, name: user.displayName));
  }
  return ApiWantedRepository(ref.watch(apiClientProvider));
});

/// Filters of the Wanted feed. The search box and category chips are shared with the listings
/// feed, so switching between "For sale" and "Wanted" keeps what the user typed.
class WantedFilter {
  final bool showClosed;

  const WantedFilter({this.showClosed = false});
}

final wantedFilterProvider = StateProvider<WantedFilter>((ref) => const WantedFilter());

final wantedPostsProvider = FutureProvider<List<WantedPost>>((ref) async {
  final repo = ref.watch(wantedRepositoryProvider);
  final listingFilter = ref.watch(buySellFilterProvider);
  final filter = ref.watch(wantedFilterProvider);
  final categories = ref.watch(buySellCategoriesProvider).valueOrNull ?? const [];

  int? categoryId;
  if (listingFilter.category != 'All') {
    final match = categories.where((c) => c.name.toLowerCase() == listingFilter.category.toLowerCase());
    if (match.isEmpty) return []; // a preset category nobody has posted in yet
    categoryId = match.first.id;
  }
  return repo.fetchWanted(
    query: listingFilter.query,
    categoryId: categoryId,
    statuses: filter.showClosed ? WantedStatus.values : [WantedStatus.open],
  );
});

final myWantedPostsProvider = FutureProvider<List<WantedPost>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest) return [];
  return ref.watch(wantedRepositoryProvider).fetchWanted(authorId: user.id, statuses: WantedStatus.values);
});

final wantedMatchesProvider = FutureProvider.family<List<ListingItem>, String>((ref, id) {
  return ref.watch(wantedRepositoryProvider).fetchMatches(id);
});
