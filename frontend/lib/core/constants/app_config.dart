/// Application-wide configuration.
/// 
/// Set [useMockData] to `false` when running against the live FastAPI backend.
class AppConfig {
  AppConfig._();

  /// Whether to use in-memory mock repositories or real HTTP endpoints.
  /// Defaults to `true` (mock mode). Set to `false` when connecting to live backend server.
  static const bool useMockData = bool.fromEnvironment('USE_MOCK', defaultValue: true);

  /// Base URL of the FastAPI backend.
  /// Override with `--dart-define=API_BASE_URL=http://...`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Development authentication security key for team testing across local network.
  /// Override with `--dart-define=DEV_KEY=...`
  static const String devKey = String.fromEnvironment(
    'DEV_KEY',
    defaultValue: 'kSH3AyYRCzXn8Czy8xXCZbC9',
  );

  /// Connect and receive timeouts for Dio network requests.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
