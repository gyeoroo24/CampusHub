/// Application-wide configuration.
/// 
/// Set [useMockData] to `false` when running against the live FastAPI backend.
class AppConfig {
  AppConfig._();

  /// Default compile-time values configured via `--dart-define`
  static const bool defaultUseMockData = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  static const String defaultDevKey = String.fromEnvironment(
    'DEV_KEY',
    defaultValue: '',
  );

  /// Cognito Hosted UI sign-in (cloud builds). Leave both empty for local sign-in with the 123456 code.
  static const String cognitoDomain = String.fromEnvironment('COGNITO_DOMAIN', defaultValue: '');
  static const String cognitoClientId = String.fromEnvironment('COGNITO_CLIENT_ID', defaultValue: '');
  static bool get cognitoEnabled => cognitoDomain.isNotEmpty && cognitoClientId.isNotEmpty;

  /// Active runtime values (can be updated at runtime by Admin via Live Demo Connection controls)
  static bool useMockData = defaultUseMockData;
  static String apiBaseUrl = defaultApiBaseUrl;
  static String devKey = defaultDevKey;

  /// Connect and receive timeouts for Dio network requests.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
