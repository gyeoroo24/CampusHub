import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_config.dart';

/// Configuration for backend connectivity (supports live runtime switching between
/// mock in-memory data and a teammate's FastAPI server with PostgreSQL).
class ServerConfig {
  final bool useMockData;
  final String apiBaseUrl;
  final String devKey;
  final String devUserEmail;
  final String? databaseUrl;

  const ServerConfig({
    required this.useMockData,
    required this.apiBaseUrl,
    required this.devKey,
    required this.devUserEmail,
    this.databaseUrl,
  });

  String get baseUrl => apiBaseUrl;

  ServerConfig copyWith({
    bool? useMockData,
    String? apiBaseUrl,
    String? devKey,
    String? devUserEmail,
    String? databaseUrl,
  }) {
    return ServerConfig(
      useMockData: useMockData ?? this.useMockData,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      devKey: devKey ?? this.devKey,
      devUserEmail: devUserEmail ?? this.devUserEmail,
      databaseUrl: databaseUrl ?? this.databaseUrl,
    );
  }
}

class ServerConfigNotifier extends StateNotifier<ServerConfig> {
  static const String _keyUseMock = 'campushub_cfg_use_mock';
  static const String _keyBaseUrl = 'campushub_cfg_base_url';
  static const String _keyDevKey = 'campushub_cfg_dev_key';
  static const String _keyDevUser = 'campushub_cfg_dev_user';
  static const String _keyDbUrl = 'campushub_cfg_db_url';

  ServerConfigNotifier()
      : super(ServerConfig(
          useMockData: AppConfig.useMockData,
          apiBaseUrl: AppConfig.apiBaseUrl,
          devKey: AppConfig.devKey,
          devUserEmail: 'mukund@iisc.ac.in',
          databaseUrl: null,
        )) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUseMock = prefs.getBool(_keyUseMock);
      final savedBaseUrl = prefs.getString(_keyBaseUrl);
      final savedDevKey = prefs.getString(_keyDevKey);
      final savedDevUser = prefs.getString(_keyDevUser);
      final savedDbUrl = prefs.getString(_keyDbUrl);

      final nextMock = savedUseMock ?? AppConfig.useMockData;
      final nextBase = (savedBaseUrl != null && savedBaseUrl.isNotEmpty) ? savedBaseUrl : AppConfig.apiBaseUrl;
      final nextKey = (savedDevKey != null && savedDevKey.isNotEmpty) ? savedDevKey : AppConfig.devKey;
      final nextUser = (savedDevUser != null && savedDevUser.isNotEmpty) ? savedDevUser : 'mukund@iisc.ac.in';
      final nextDb = savedDbUrl;

      state = ServerConfig(
        useMockData: nextMock,
        apiBaseUrl: nextBase,
        devKey: nextKey,
        devUserEmail: nextUser,
        databaseUrl: nextDb,
      );

      // Keep AppConfig static fields in sync
      AppConfig.useMockData = nextMock;
      AppConfig.apiBaseUrl = nextBase;
      AppConfig.devKey = nextKey;
    } catch (_) {}
  }

  Future<void> updateConfig({
    required bool useMockData,
    required String apiBaseUrl,
    required String devKey,
    required String devUserEmail,
    String? databaseUrl,
  }) async {
    final cleanBaseUrl = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanDevKey = devKey.trim();
    final cleanDevUser = devUserEmail.trim();

    state = ServerConfig(
      useMockData: useMockData,
      apiBaseUrl: cleanBaseUrl,
      devKey: cleanDevKey,
      devUserEmail: cleanDevUser,
      databaseUrl: databaseUrl?.trim(),
    );

    // Keep AppConfig static fields in sync
    AppConfig.useMockData = useMockData;
    AppConfig.apiBaseUrl = cleanBaseUrl;
    AppConfig.devKey = cleanDevKey;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyUseMock, useMockData);
      await prefs.setString(_keyBaseUrl, cleanBaseUrl);
      await prefs.setString(_keyDevKey, cleanDevKey);
      await prefs.setString(_keyDevUser, cleanDevUser);
      if (databaseUrl != null) {
        await prefs.setString(_keyDbUrl, databaseUrl.trim());
      }
    } catch (_) {}
  }

  Future<void> resetToDefaults() async {
    state = ServerConfig(
      useMockData: AppConfig.defaultUseMockData,
      apiBaseUrl: AppConfig.defaultApiBaseUrl,
      devKey: AppConfig.defaultDevKey,
      devUserEmail: 'mukund@iisc.ac.in',
      databaseUrl: null,
    );

    AppConfig.useMockData = AppConfig.defaultUseMockData;
    AppConfig.apiBaseUrl = AppConfig.defaultApiBaseUrl;
    AppConfig.devKey = AppConfig.defaultDevKey;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUseMock);
      await prefs.remove(_keyBaseUrl);
      await prefs.remove(_keyDevKey);
      await prefs.remove(_keyDevUser);
      await prefs.remove(_keyDbUrl);
    } catch (_) {}
  }
}

final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, ServerConfig>((ref) {
  return ServerConfigNotifier();
});
