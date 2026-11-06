import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/seller_trust_repository.dart';
import '../domain/seller_strike.dart';

final sellerTrustRepositoryProvider = Provider<ISellerTrustRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockSellerTrustRepository();
  }
  return ApiSellerTrustRepository(ref.watch(apiClientProvider));
});

/// My own strikes (empty for guests).
final mySellerStrikesProvider = FutureProvider<List<SellerStrike>>((ref) async {
  if (ref.watch(isGuestUserProvider)) return [];
  return ref.watch(sellerTrustRepositoryProvider).fetchMyStrikes();
});

/// My strike count against the limits. The defaults (no strikes, 3 to be blocked) in mock mode and for guests.
final myStrikeSummaryProvider = FutureProvider<StrikeSummary>((ref) async {
  if (ref.watch(isGuestUserProvider) || ref.watch(serverConfigProvider).useMockData) return const StrikeSummary();
  final r = await ref.watch(apiClientProvider).get(ApiEndpoints.mySellerStrikeSummary);
  return StrikeSummary.fromJson(r.data as Map<String, dynamic>);
});

/// The moderator Seller Strikes tab's appeal-status filter; 'pending' is the actionable queue.
final sellerStrikesFilterProvider = StateProvider<String>((ref) => 'pending');

/// Strikes across all sellers matching the filter above (empty unless you can moderate Buy & Sell).
final moderatedSellerStrikesProvider = FutureProvider<List<SellerStrike>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.canModerateBuySell) return [];
  final filter = ref.watch(sellerStrikesFilterProvider);
  return ref.watch(sellerTrustRepositoryProvider).fetchStrikesForModeration(appealStatus: filter);
});

/// My latest request to be unblocked (null for guests, in mock mode, or if I never asked).
final myUnblockRequestProvider = FutureProvider<UnblockRequest?>((ref) async {
  if (ref.watch(isGuestUserProvider)) return null;
  return ref.watch(sellerTrustRepositoryProvider).fetchMyUnblockRequest();
});

/// Unblock requests a moderator has already decided, newest first (empty unless you can moderate Buy & Sell).
/// Waiting ones show with their seller in [blockedSellersProvider].
final resolvedUnblockRequestsProvider = FutureProvider<List<UnblockRequest>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.canModerateBuySell) return [];
  return ref.watch(sellerTrustRepositoryProvider).fetchUnblockRequests(status: 'resolved');
});

/// Sellers blocked right now (empty unless you can moderate Buy & Sell).
final blockedSellersProvider = FutureProvider<List<BlockedSeller>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.canModerateBuySell) return [];
  return ref.watch(sellerTrustRepositoryProvider).fetchBlockedSellers();
});
