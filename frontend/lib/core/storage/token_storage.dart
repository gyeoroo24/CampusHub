import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage interface for auth/JWT tokens and persisted session.
abstract class ITokenStorage {
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<void> saveTokens({required String accessToken, String? refreshToken});
  Future<void> clearTokens();
  Future<bool> hasToken();

  Future<Map<String, dynamic>?> getSavedUser();
  Future<void> saveUser(Map<String, dynamic> userMap);
  Future<void> clearAll();
}

/// SharedPreferences-backed token and user storage with automatic in-memory fallback.
///
/// If platform channels are unavailable (e.g. before a full app rebuild / hot restart
/// when a new plugin is added), it seamlessly falls back to memory without crashing.
class SharedPrefsTokenStorage implements ITokenStorage {
  static const String _keyAccessToken = 'campushub_access_token';
  static const String _keyRefreshToken = 'campushub_refresh_token';
  static const String _keyUser = 'campushub_persisted_user';

  final InMemoryTokenStorage _fallback = InMemoryTokenStorage();
  bool _pluginFailed = false;

  Future<SharedPreferences?> _getPrefs() async {
    if (_pluginFailed) return null;
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[TokenStorage] SharedPreferences unavailable, using in-memory fallback: $e');
      _pluginFailed = true;
      return null;
    }
  }

  @override
  Future<String?> getAccessToken() async {
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        return prefs.getString(_keyAccessToken);
      }
    } catch (_) {}
    return _fallback.getAccessToken();
  }

  @override
  Future<String?> getRefreshToken() async {
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        return prefs.getString(_keyRefreshToken);
      }
    } catch (_) {}
    return _fallback.getRefreshToken();
  }

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    await _fallback.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        await prefs.setString(_keyAccessToken, accessToken);
        if (refreshToken != null) {
          await prefs.setString(_keyRefreshToken, refreshToken);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> clearTokens() async {
    await _fallback.clearTokens();
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        await prefs.remove(_keyAccessToken);
        await prefs.remove(_keyRefreshToken);
      }
    } catch (_) {}
  }

  @override
  Future<bool> hasToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<Map<String, dynamic>?> getSavedUser() async {
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        final raw = prefs.getString(_keyUser);
        if (raw != null && raw.isNotEmpty) {
          return jsonDecode(raw) as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return _fallback.getSavedUser();
  }

  @override
  Future<void> saveUser(Map<String, dynamic> userMap) async {
    await _fallback.saveUser(userMap);
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        await prefs.setString(_keyUser, jsonEncode(userMap));
      }
    } catch (_) {}
  }

  @override
  Future<void> clearAll() async {
    await _fallback.clearAll();
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        await prefs.remove(_keyAccessToken);
        await prefs.remove(_keyRefreshToken);
        await prefs.remove(_keyUser);
      }
    } catch (_) {}
  }
}

/// In-memory token storage implementation (fallback / test mock).
class InMemoryTokenStorage implements ITokenStorage {
  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _persistedUser;

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
    }
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<bool> hasToken() async => _accessToken != null && _accessToken!.isNotEmpty;

  @override
  Future<Map<String, dynamic>?> getSavedUser() async => _persistedUser;

  @override
  Future<void> saveUser(Map<String, dynamic> userMap) async {
    _persistedUser = userMap;
  }

  @override
  Future<void> clearAll() async {
    _accessToken = null;
    _refreshToken = null;
    _persistedUser = null;
  }
}
