import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config/server_config.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';
import '../data/cognito_hosted_ui.dart';
import '../domain/user.dart';

final tokenStorageProvider = Provider<ITokenStorage>((ref) {
  return SharedPrefsTokenStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final serverConfig = ref.watch(serverConfigProvider);
  return ApiClient(
    storage: tokenStorage,
    baseUrl: serverConfig.apiBaseUrl,
    devKey: serverConfig.devKey,
    devUserEmail: serverConfig.devUserEmail,
  );
});

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final serverConfig = ref.watch(serverConfigProvider);
  if (serverConfig.useMockData) {
    return MockAuthRepository(storage: tokenStorage);
  }
  final apiClient = ref.watch(apiClientProvider);
  final repo = ApiAuthRepository(
    apiClient: apiClient,
    tokenStorage: tokenStorage,
    cognito: AppConfig.cognitoEnabled
        ? CognitoHostedUi(domain: AppConfig.cognitoDomain, clientId: AppConfig.cognitoClientId)
        : null,
  );
  // Any API call's 401 (not just getCurrentUser's) now refreshes the Cognito ID token and retries
  // once, instead of leaving the user signed out until they reload.
  apiClient.onUnauthorized = repo.refreshSession;
  return repo;
});

/// Stream of the current authenticated user (null means Guest).
final authStateProvider = StreamProvider<User?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

/// Synchronous-like access to current user (can be null if Guest).
final currentUserProvider = Provider<User?>((ref) {
  // select: only a real change of user (User compares by value) reaches the ~50 providers below; the
  // session re-check every minute returns an equal user and changes nothing.
  return ref.watch(authStateProvider.select((state) => state.value));
});

/// Whether the current session is an unauthenticated Guest.
final isGuestUserProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user == null || user.isGuest;
});

/// Tracks whether the "Trusted Campus Exchange" info banner should be shown.
/// Only shown when the user has just logged in manually during the active session.
/// Does NOT show on app launch for persisted sessions or for guests.
/// Dismissible via the 'x' button until next manual login.
final showTrustedExchangeBannerProvider = StateProvider<bool>((ref) => false);

