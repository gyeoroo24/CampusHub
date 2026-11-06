import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/models/category_ref.dart';
import '../../../core/models/contact.dart';
import '../../../core/models/user_ref.dart';
import '../../buy_sell/data/buy_sell_dto.dart';
import '../../buy_sell/data/mock_buy_sell_repository.dart';
import '../../buy_sell/domain/buy_sell_item.dart';
import '../domain/wanted_post.dart';

/// Wanted posts (`/wanted`): buyers say what they need instead of waiting for it to be listed.
abstract class IWantedRepository {
  /// Newest first. [statuses] defaults to open posts only (as the API does).
  Future<List<WantedPost>> fetchWanted({
    String query = '',
    int? categoryId,
    List<WantedStatus>? statuses,
    String? authorId,
    int limit = 50,
  });

  Future<WantedPost?> getWanted(String id);

  /// Available listings that match the post, best first (up to 10).
  Future<List<ListingItem>> fetchMatches(String id);

  /// The reply includes [WantedPost.possibleMatches].
  Future<WantedPost> createWanted({
    required String title,
    String? description,
    required int categoryId,
    double? maxPrice,
  });

  Future<WantedPost> updateWanted(String id, {String? title, String? description, double? maxPrice});

  Future<WantedPost> updateStatus(String id, WantedStatus status);

  Future<void> deleteWanted(String id, {String? reason});
}

class ApiWantedRepository implements IWantedRepository {
  final ApiClient apiClient;

  ApiWantedRepository(this.apiClient);

  @override
  Future<List<WantedPost>> fetchWanted({
    String query = '',
    int? categoryId,
    List<WantedStatus>? statuses,
    String? authorId,
    int limit = 50,
  }) async {
    final response = await apiClient.get(ApiEndpoints.wanted, queryParameters: {
      'limit': limit,
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (categoryId != null) 'category_id': categoryId,
      if (statuses != null && statuses.isNotEmpty) 'status': statuses.map((s) => s.name).toList(),
      if (authorId != null) 'author_id': authorId,
    });
    final items = (response.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? [];
    return items.map((j) => WantedPost.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<WantedPost?> getWanted(String id) async {
    final response = await apiClient.get(ApiEndpoints.wantedPost(id));
    return WantedPost.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<ListingItem>> fetchMatches(String id) async {
    final response = await apiClient.get(ApiEndpoints.wantedMatches(id));
    return (response.data as List<dynamic>)
        .map((j) => BuySellListingDto.fromJson(j as Map<String, dynamic>).toDomain())
        .toList();
  }

  @override
  Future<WantedPost> createWanted({
    required String title,
    String? description,
    required int categoryId,
    double? maxPrice,
  }) async {
    final response = await apiClient.post(ApiEndpoints.wanted, data: {
      'title': title,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      'category_id': categoryId,
      if (maxPrice != null) 'max_price': maxPrice,
    });
    return WantedPost.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<WantedPost> updateWanted(String id, {String? title, String? description, double? maxPrice}) async {
    final response = await apiClient.patch(ApiEndpoints.wantedPost(id), data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (maxPrice != null) 'max_price': maxPrice,
    });
    return WantedPost.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<WantedPost> updateStatus(String id, WantedStatus status) async {
    final response = await apiClient.patch(ApiEndpoints.wantedStatus(id), data: {'status': status.name});
    return WantedPost.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteWanted(String id, {String? reason}) async {
    await apiClient.delete(
      ApiEndpoints.wantedPost(id),
      queryParameters: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  }
}

/// In-memory version for mock mode. Matches come from the mock Buy & Sell listings.
class MockWantedRepository implements IWantedRepository {
  /// Who new posts belong to (the signed-in mock user).
  final UserRef author;

  MockWantedRepository({this.author = const UserRef(id: 'mock_user', name: 'You')});

  static final List<WantedPost> _posts = [
    WantedPost(
      id: 'w_1',
      title: 'Need a lab coat (size M)',
      description: 'For the chemistry lab starting next week.',
      category: const CategoryRef(id: 5, name: 'Lab Equipment'),
      maxPrice: 400,
      author: const UserRef(id: 'user_meera', name: 'Meera Iyer'),
      authorContact: const Contact(email: 'meerai@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(hours: 20)),
    ),
    WantedPost(
      id: 'w_2',
      title: 'Looking for a cycle for campus rides',
      category: const CategoryRef(id: 2, name: 'Cycles'),
      maxPrice: 3000,
      author: const UserRef(id: 'user_rohan', name: 'Rohan Nair'),
      authorContact: const Contact(email: 'rohann@iisc.ac.in', phone: '+919845012345'),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    WantedPost(
      id: 'w_3',
      title: 'Want CLRS (any edition)',
      description: 'Happy to pick it up from any hostel.',
      category: const CategoryRef(id: 1, name: 'Books'),
      author: const UserRef(id: 'user_kavya', name: 'Kavya Reddy'),
      authorContact: const Contact(email: 'kavyar@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
  ];

  static void resetMockData() => _posts.removeWhere((p) => !p.id.startsWith('w_'));

  int _index(String id) {
    final i = _posts.indexWhere((p) => p.id == id);
    if (i < 0) throw Exception('Wanted post not found.');
    return i;
  }

  @override
  Future<List<WantedPost>> fetchWanted({
    String query = '',
    int? categoryId,
    List<WantedStatus>? statuses,
    String? authorId,
    int limit = 50,
  }) async {
    final allowed = statuses ?? [WantedStatus.open];
    final q = query.trim().toLowerCase();
    return _posts
        .where((p) => allowed.contains(p.status))
        .where((p) => categoryId == null || p.category.id == categoryId)
        .where((p) => authorId == null || p.author.id == authorId)
        .where((p) => q.isEmpty || '${p.title} ${p.description ?? ''}'.toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  @override
  Future<WantedPost?> getWanted(String id) async {
    final i = _posts.indexWhere((p) => p.id == id);
    return i < 0 ? null : _posts[i];
  }

  @override
  Future<List<ListingItem>> fetchMatches(String id) async {
    final post = _posts[_index(id)];
    final words = post.title.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 2).toSet();
    final listings = await MockBuySellRepository().fetchListings();
    return listings
        .where((l) => l.status == ListingStatus.available && l.category.id == post.category.id)
        .where((l) => post.maxPrice == null || l.price <= post.maxPrice!)
        .where((l) => words.any((w) => '${l.title} ${l.description}'.toLowerCase().contains(w)))
        .take(10)
        .toList();
  }

  @override
  Future<WantedPost> createWanted({
    required String title,
    String? description,
    required int categoryId,
    double? maxPrice,
  }) async {
    final categories = await MockBuySellRepository().fetchCategories();
    final category = categories.firstWhere((c) => c.id == categoryId,
        orElse: () => throw Exception("category_id isn't a Buy & Sell category."));
    final post = WantedPost(
      id: 'wn_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      description: description,
      category: category,
      maxPrice: maxPrice,
      author: author,
      createdAt: DateTime.now(),
    );
    _posts.insert(0, post);
    final matches = await fetchMatches(post.id);
    return WantedPost(
      id: post.id,
      title: post.title,
      description: post.description,
      category: post.category,
      maxPrice: post.maxPrice,
      author: post.author,
      createdAt: post.createdAt,
      possibleMatches: matches,
    );
  }

  @override
  Future<WantedPost> updateWanted(String id, {String? title, String? description, double? maxPrice}) async {
    final i = _index(id);
    _posts[i] = _posts[i].copyWith(title: title, description: description, maxPrice: maxPrice);
    return _posts[i];
  }

  @override
  Future<WantedPost> updateStatus(String id, WantedStatus status) async {
    final i = _index(id);
    _posts[i] = _posts[i].copyWith(status: status);
    return _posts[i];
  }

  @override
  Future<void> deleteWanted(String id, {String? reason}) async => _posts.removeAt(_index(id));
}
