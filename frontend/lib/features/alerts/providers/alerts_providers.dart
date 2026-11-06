import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/alerts_repository.dart';
import '../domain/alerts_models.dart';

final alertsRepositoryProvider = Provider<IAlertsRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockAlertsRepository();
  }
  return ApiAlertsRepository(ref.watch(apiClientProvider));
});

/// My saved searches with their "N new" counts (empty for guests).
final savedSearchesProvider = FutureProvider<List<SavedSearch>>((ref) async {
  if (ref.watch(isGuestUserProvider)) return [];
  return ref.watch(alertsRepositoryProvider).fetchSavedSearches();
});

/// The latest notifications in my inbox, newest first (empty for guests).
/// Refreshed every 30 seconds while signed in, so the badge shows new alerts without a reload.
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  if (ref.watch(isGuestUserProvider)) return [];
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(alertsRepositoryProvider).fetchNotifications(limit: 30);
});

/// Unread count for the bell badge.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return items.where((n) => !n.isRead).length;
});
