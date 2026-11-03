import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/seller_strike.dart';

/// Seller trust score (future plan §1.5): a seller's own strike history and appeal, and the
/// Buy & Sell moderator side (the contested-appeal queue, overturn, reject, lift a suspension).
abstract class ISellerTrustRepository {
  /// Strikes against me, newest first.
  Future<List<SellerStrike>> fetchMyStrikes();

  /// Contests one of my strikes. One appeal per strike.
  Future<void> appealStrike(String strikeId, String message);

  /// Moderator queue: strikes across all sellers. 'pending' (default) is the actionable queue -
  /// an appeal nobody has resolved yet.
  Future<List<SellerStrike>> fetchStrikesForModeration({
    String appealStatus = 'pending',
    String? sellerId,
  });

  /// Overturn a strike: it stops counting, the listing it hid becomes visible again.
  Future<void> overturnStrike(String strikeId, {String? note});

  /// Reject a pending appeal: the strike stands and the listing stays hidden, but it drops out
  /// of the queue.
  Future<void> rejectAppeal(String strikeId);

  /// Lifts a seller's posting suspension without overturning any strike.
  Future<void> liftListingSuspension(String sellerId);
}

class ApiSellerTrustRepository implements ISellerTrustRepository {
  final ApiClient apiClient;

  ApiSellerTrustRepository(this.apiClient);

  @override
  Future<List<SellerStrike>> fetchMyStrikes() async {
    final response = await apiClient.get(ApiEndpoints.mySellerStrikes);
    return (response.data as List<dynamic>)
        .map((j) => SellerStrike.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> appealStrike(String strikeId, String message) async {
    await apiClient.post(ApiEndpoints.appealSellerStrike(strikeId), data: {'message': message});
  }

  @override
  Future<List<SellerStrike>> fetchStrikesForModeration({
    String appealStatus = 'pending',
    String? sellerId,
  }) async {
    final response = await apiClient.get(
      ApiEndpoints.sellerStrikes,
      queryParameters: {
        'appeal_status': appealStatus,
        if (sellerId != null) 'seller_id': sellerId,
      },
    );
    return (response.data as List<dynamic>)
        .map((j) => SellerStrike.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> overturnStrike(String strikeId, {String? note}) async {
    await apiClient.post(
      ApiEndpoints.overturnSellerStrike(strikeId),
      data: {if (note != null && note.isNotEmpty) 'note': note},
    );
  }

  @override
  Future<void> rejectAppeal(String strikeId) async {
    await apiClient.post(ApiEndpoints.rejectSellerStrikeAppeal(strikeId));
  }

  @override
  Future<void> liftListingSuspension(String sellerId) async {
    await apiClient.post(ApiEndpoints.liftListingSuspension(sellerId));
  }
}

/// Local-only mock: no seller trust data in mock mode (no backend model behind it).
class MockSellerTrustRepository implements ISellerTrustRepository {
  final List<SellerStrike> _strikes = [];

  @override
  Future<List<SellerStrike>> fetchMyStrikes() async => List.unmodifiable(_strikes);

  @override
  Future<void> appealStrike(String strikeId, String message) async {
    final idx = _strikes.indexWhere((s) => s.id == strikeId);
    if (idx == -1) return;
    final s = _strikes[idx];
    _strikes[idx] = SellerStrike(
      id: s.id, seller: s.seller, listingId: s.listingId, listingTitle: s.listingTitle,
      listingHidden: s.listingHidden, severity: s.severity, moderatorNote: s.moderatorNote,
      excluded: s.excluded, appealMessage: message, appealCreatedAt: DateTime.now(),
      appealStatus: AppealStatus.pending, createdAt: s.createdAt,
    );
  }

  @override
  Future<List<SellerStrike>> fetchStrikesForModeration({
    String appealStatus = 'pending',
    String? sellerId,
  }) async =>
      const [];

  @override
  Future<void> overturnStrike(String strikeId, {String? note}) async {}

  @override
  Future<void> rejectAppeal(String strikeId) async {}

  @override
  Future<void> liftListingSuspension(String sellerId) async {}
}
