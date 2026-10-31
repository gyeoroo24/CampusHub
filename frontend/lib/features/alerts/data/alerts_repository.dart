import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/alerts_models.dart';

/// Saved searches (`/me/saved-searches`) and the notification inbox (`/me/notifications`).
abstract class IAlertsRepository {
  Future<List<SavedSearch>> fetchSavedSearches();

  Future<SavedSearch> createSavedSearch({
    required SavedSearchModule module,
    required String name,
    String? query,
    int? categoryId,
    double? minPrice,
    double? maxPrice,
    bool alertsEnabled = true,
  });

  Future<SavedSearch> updateSavedSearch(String id, {String? name, bool? alertsEnabled});

  /// The user opened the results: resets `new_count` to 0.
  Future<SavedSearch> markSeen(String id);

  Future<void> deleteSavedSearch(String id);

  Future<List<AppNotification>> fetchNotifications({bool unreadOnly = false, int limit = 30});

  Future<void> markRead(String id);

  Future<void> markAllRead();

  /// Deletes my notifications with these ids (one or several).
  Future<void> deleteNotifications(List<String> ids);

  /// Deletes all my notifications.
  Future<void> clearNotifications();
}

class ApiAlertsRepository implements IAlertsRepository {
  final ApiClient apiClient;

  ApiAlertsRepository(this.apiClient);

  @override
  Future<List<SavedSearch>> fetchSavedSearches() async {
    final response = await apiClient.get(ApiEndpoints.savedSearches);
    return (response.data as List<dynamic>)
        .map((j) => SavedSearch.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SavedSearch> createSavedSearch({
    required SavedSearchModule module,
    required String name,
    String? query,
    int? categoryId,
    double? minPrice,
    double? maxPrice,
    bool alertsEnabled = true,
  }) async {
    final response = await apiClient.post(ApiEndpoints.savedSearches, data: {
      'module': module.apiValue,
      'name': name,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (categoryId != null) 'category_id': categoryId,
      if (minPrice != null) 'min_price': minPrice,
      if (maxPrice != null) 'max_price': maxPrice,
      'alerts_enabled': alertsEnabled,
    });
    return SavedSearch.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<SavedSearch> updateSavedSearch(String id, {String? name, bool? alertsEnabled}) async {
    final response = await apiClient.patch(ApiEndpoints.savedSearch(id), data: {
      if (name != null) 'name': name,
      if (alertsEnabled != null) 'alerts_enabled': alertsEnabled,
    });
    return SavedSearch.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<SavedSearch> markSeen(String id) async {
    final response = await apiClient.post(ApiEndpoints.savedSearchSeen(id));
    return SavedSearch.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteSavedSearch(String id) async {
    await apiClient.delete(ApiEndpoints.savedSearch(id));
  }

  @override
  Future<List<AppNotification>> fetchNotifications({bool unreadOnly = false, int limit = 30}) async {
    final response = await apiClient.get(ApiEndpoints.notifications, queryParameters: {
      'limit': limit,
      if (unreadOnly) 'unread_only': true,
    });
    final items = (response.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? [];
    return items.map((j) => AppNotification.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> markRead(String id) async {
    await apiClient.post(ApiEndpoints.notificationRead(id));
  }

  @override
  Future<void> markAllRead() async {
    await apiClient.post(ApiEndpoints.notificationsReadAll);
  }

  @override
  Future<void> deleteNotifications(List<String> ids) async {
    if (ids.length == 1) {
      await apiClient.delete(ApiEndpoints.notification(ids.single));
    } else if (ids.isNotEmpty) {
      await apiClient.post(ApiEndpoints.notificationsDelete, data: {'ids': ids});
    }
  }

  @override
  Future<void> clearNotifications() async {
    await apiClient.delete(ApiEndpoints.notifications);
  }
}

/// In-memory version for mock mode (`USE_MOCK=true`).
class MockAlertsRepository implements IAlertsRepository {
  static final List<SavedSearch> _searches = [
    SavedSearch(
      id: 'ss_1',
      module: SavedSearchModule.buySell,
      name: 'Cycle under ₹3,000',
      query: 'cycle',
      categoryId: 2,
      categoryName: 'Cycles',
      maxPrice: 3000,
      newCount: 1,
      lastSeenAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: DateTime.now().subtract(const Duration(days: 9)),
    ),
  ];

  static final List<AppNotification> _notifications = [
    AppNotification(
      id: 'n_1',
      type: 'saved_search_match',
      payload: const {
        'listing_id': '2',
        'saved_search_id': 'ss_1',
        'message': 'New match for “Cycle under ₹3,000”: Hero cycle for ₹2,500',
      },
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    AppNotification(
      id: 'n_2',
      type: 'wanted_post_match',
      payload: const {
        'listing_id': '1',
        'wanted_post_id': 'w_1',
        'message': 'Someone listed IISc Chemistry Lab Coat for ₹350, which may be what you wanted (“Need a lab coat”)',
      },
      isRead: true,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  /// Restores the starting data (used by tests).
  static void resetMockData() {
    _searches.removeWhere((s) => s.id != 'ss_1');
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].id == 'n_1') {
        _notifications[i] = AppNotification(
          id: 'n_1',
          type: _notifications[i].type,
          payload: _notifications[i].payload,
          isRead: false,
          createdAt: _notifications[i].createdAt,
        );
      }
    }
  }

  int _index(String id) {
    final i = _searches.indexWhere((s) => s.id == id);
    if (i < 0) throw Exception('Saved search not found.');
    return i;
  }

  @override
  Future<List<SavedSearch>> fetchSavedSearches() async => List.of(_searches);

  @override
  Future<SavedSearch> createSavedSearch({
    required SavedSearchModule module,
    required String name,
    String? query,
    int? categoryId,
    double? minPrice,
    double? maxPrice,
    bool alertsEnabled = true,
  }) async {
    if (_searches.length >= 20) {
      throw Exception('You can keep up to 20 saved searches. Delete one first.');
    }
    final search = SavedSearch(
      id: 'ss_${DateTime.now().microsecondsSinceEpoch}',
      module: module,
      name: name,
      query: (query == null || query.trim().isEmpty) ? null : query.trim(),
      categoryId: categoryId,
      minPrice: minPrice,
      maxPrice: maxPrice,
      alertsEnabled: alertsEnabled,
      lastSeenAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    _searches.add(search);
    return search;
  }

  @override
  Future<SavedSearch> updateSavedSearch(String id, {String? name, bool? alertsEnabled}) async {
    final i = _index(id);
    _searches[i] = _searches[i].copyWith(name: name, alertsEnabled: alertsEnabled);
    return _searches[i];
  }

  @override
  Future<SavedSearch> markSeen(String id) async {
    final i = _index(id);
    _searches[i] = _searches[i].copyWith(newCount: 0, lastSeenAt: DateTime.now());
    return _searches[i];
  }

  @override
  Future<void> deleteSavedSearch(String id) async => _searches.removeAt(_index(id));

  @override
  Future<List<AppNotification>> fetchNotifications({bool unreadOnly = false, int limit = 30}) async {
    final items = unreadOnly ? _notifications.where((n) => !n.isRead) : _notifications;
    return items.take(limit).toList();
  }

  @override
  Future<void> markRead(String id) async {
    final i = _notifications.indexWhere((n) => n.id == id);
    if (i >= 0) _notifications[i] = _notifications[i].markedRead();
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].markedRead();
    }
  }

  @override
  Future<void> deleteNotifications(List<String> ids) async =>
      _notifications.removeWhere((n) => ids.contains(n.id));

  @override
  Future<void> clearNotifications() async => _notifications.clear();
}
