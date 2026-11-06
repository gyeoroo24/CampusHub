import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the unlocked messaging key on this device, so the passphrase is only needed once per
/// device. Signing out removes it (see `SharedPrefsTokenStorage.clearAll`), and so does
/// "Lock messages on this device".
///
/// On the web this is the browser's local storage for this site: anyone with access to this
/// browser profile could read it, the same as the messages shown on screen.
class ChatKeyStore {
  static const prefix = 'campushub_chat_key_';

  /// If shared_preferences is unavailable, keep the key for this session only.
  final Map<String, String> _memory = {};

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[ChatKeyStore] SharedPreferences unavailable, keeping the key in memory: $e');
      return null;
    }
  }

  Future<({String keyId, Uint8List privateKey})?> read(String userId) async {
    final raw = (await _prefs())?.getString('$prefix$userId') ?? _memory['$prefix$userId'];
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (keyId: j['key_id'] as String, privateKey: Uint8List.fromList(base64Decode(j['private_key'] as String)));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, String keyId, Uint8List privateKey) async {
    final raw = jsonEncode({'key_id': keyId, 'private_key': base64Encode(privateKey)});
    _memory['$prefix$userId'] = raw;
    await (await _prefs())?.setString('$prefix$userId', raw);
  }

  Future<void> remove(String userId) async {
    _memory.remove('$prefix$userId');
    await (await _prefs())?.remove('$prefix$userId');
  }
}
