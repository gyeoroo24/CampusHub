import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/models/user_ref.dart';
import '../domain/seller_strike.dart';

/// Seller trust score: a seller's own strike history and appeal, and the
/// Buy & Sell moderator side (the contested-appeal queue, overturn, reject, lift a suspension, unblock).
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

  /// My latest request to be unblocked, or null if I never asked.
  Future<UnblockRequest?> fetchMyUnblockRequest();

  /// Asks the Buy & Sell moderators to unblock me (only while blocked).
  Future<UnblockRequest> requestUnblock(String message);

  /// Moderator queue of unblock requests: 'pending' (default), 'resolved' or 'all'.
  Future<List<UnblockRequest>> fetchUnblockRequests({String status = 'pending'});

  /// Sellers blocked right now.
  Future<List<BlockedSeller>> fetchBlockedSellers();

  /// Unblocks a seller: resets their strikes, lifts the suspension, approves a waiting request.
  Future<void> unblockSeller(String sellerId, {String? note});

  Future<void> approveUnblockRequest(String requestId, {String? note});

  Future<void> rejectUnblockRequest(String requestId, {String? note});
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

  Map<String, dynamic> _note(String? note) => {if (note != null && note.isNotEmpty) 'note': note};

  @override
  Future<UnblockRequest?> fetchMyUnblockRequest() async {
    final response = await apiClient.get(ApiEndpoints.mySellerUnblockRequest);
    final data = response.data;
    return data is Map<String, dynamic> ? UnblockRequest.fromJson(data) : null;
  }

  @override
  Future<UnblockRequest> requestUnblock(String message) async {
    final response = await apiClient.post(ApiEndpoints.mySellerUnblockRequest, data: {'message': message});
    return UnblockRequest.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<UnblockRequest>> fetchUnblockRequests({String status = 'pending'}) async {
    final response = await apiClient.get(ApiEndpoints.sellerUnblockRequests, queryParameters: {'status': status});
    return (response.data as List<dynamic>)
        .map((j) => UnblockRequest.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<BlockedSeller>> fetchBlockedSellers() async {
    final response = await apiClient.get(ApiEndpoints.blockedSellers);
    return (response.data as List<dynamic>)
        .map((j) => BlockedSeller.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> unblockSeller(String sellerId, {String? note}) async {
    await apiClient.post(ApiEndpoints.unblockSeller(sellerId), data: _note(note));
  }

  @override
  Future<void> approveUnblockRequest(String requestId, {String? note}) async {
    await apiClient.post(ApiEndpoints.approveUnblockRequest(requestId), data: _note(note));
  }

  @override
  Future<void> rejectUnblockRequest(String requestId, {String? note}) async {
    await apiClient.post(ApiEndpoints.rejectUnblockRequest(requestId), data: _note(note));
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

  @override
  Future<UnblockRequest?> fetchMyUnblockRequest() async => null;

  @override
  Future<UnblockRequest> requestUnblock(String message) async => UnblockRequest(
      id: 'mock', seller: const UserRef(id: 'me', name: 'Me'), message: message, status: 'pending',
      createdAt: DateTime.now());

  @override
  Future<List<UnblockRequest>> fetchUnblockRequests({String status = 'pending'}) async => const [];

  @override
  Future<List<BlockedSeller>> fetchBlockedSellers() async => const [];

  @override
  Future<void> unblockSeller(String sellerId, {String? note}) async {}

  @override
  Future<void> approveUnblockRequest(String requestId, {String? note}) async {}

  @override
  Future<void> rejectUnblockRequest(String requestId, {String? note}) async {}
}
