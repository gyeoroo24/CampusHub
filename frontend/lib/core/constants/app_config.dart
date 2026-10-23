/// Application-wide configuration.
/// 
/// Set [useMockData] to `false` when running against the live FastAPI backend.
class AppConfig {
  AppConfig._();

  /// Whether to use in-memory mock repositories or real HTTP endpoints.
  /// Defaults to `true` until backend API is deployed.
  static const bool useMockData = bool.fromEnvironment('USE_MOCK', defaultValue: true);

  /// Base URL of the FastAPI backend.
  /// Override with `--dart-define=API_BASE_URL=https://api.yourdomain.com`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Connect and receive timeouts for Dio network requests.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
