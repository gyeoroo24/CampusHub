import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/config/server_config.dart';
import '../../../core/push/web_push.dart';
import '../../auth/providers/auth_providers.dart';

/// Push notifications on this browser (FR-22), as the notifications panel shows them.
enum PushStatus {
  /// This browser can't do Web Push (or this isn't the web app).
  unsupported,

  /// The server sends no pushes (no VAPID key set up), so there is nothing to turn on.
  unavailable,

  /// Supported, but not turned on for this browser.
  off,

  /// The person blocked notifications for this site; only the browser's site settings can undo it.
  blocked,
  on,
}

class PushState {
  final PushStatus status;
  final bool busy;
  const PushState(this.status, {this.busy = false});
}

/// Keeps this browser's push subscription registered with the API for whoever is signed in. Signing
/// in on a browser that already allowed notifications re-registers it silently; signing out ends it
/// (ApiAuthRepository.signOut), so a shared computer never gets the previous person's alerts.
class PushNotificationsController extends StateNotifier<PushState> {
  PushNotificationsController(this._ref) : super(const PushState(PushStatus.off, busy: true)) {
    _refresh(registerIfAllowed: true);
  }

  final Ref _ref;
  WebPush get _push => WebPush.instance;

  Future<String?> _publicKey() async {
    final response = await _ref.read(apiClientProvider).get(ApiEndpoints.pushConfig);
    final data = response.data as Map<String, dynamic>;
    return data['enabled'] == true ? data['public_key'] as String? : null;
  }

  Future<void> _register(String subscription) =>
      _ref.read(apiClientProvider).post(ApiEndpoints.devices, data: {'platform': 'web', 'push_token': subscription});

  Future<void> _refresh({bool registerIfAllowed = false}) async {
    final user = _ref.read(currentUserProvider);
    if (user == null || user.isGuest || _ref.read(serverConfigProvider).useMockData) {
      state = const PushState(PushStatus.unavailable);
      return;
    }
    if (_push.permission == 'unsupported') {
      state = const PushState(PushStatus.unsupported);
      return;
    }
    if (_push.permission == 'denied') {
      state = const PushState(PushStatus.blocked);
      return;
    }
    try {
      final key = await _publicKey();
      if (key == null) {
        state = const PushState(PushStatus.unavailable);
        return;
      }
      if (registerIfAllowed && _push.permission == 'granted') {
        // Already allowed (e.g. on before the last sign-out): subscribe again without asking.
        final subscription = await _push.subscribe(key);
        if (subscription != null) {
          await _register(subscription);
          state = const PushState(PushStatus.on);
          return;
        }
      }
      state = PushState(await _push.current() != null ? PushStatus.on : PushStatus.off);
    } catch (_) {
      state = const PushState(PushStatus.unavailable);
    }
  }

  /// Asks the browser for permission and subscribes. Returns a message for the person if it didn't work.
  Future<String?> turnOn() async {
    state = PushState(state.status, busy: true);
    try {
      final key = await _publicKey();
      if (key == null) {
        state = const PushState(PushStatus.unavailable);
        return 'Push notifications aren’t set up on this server.';
      }
      final subscription = await _push.subscribe(key);
      if (subscription == null) {
        final blocked = _push.permission == 'denied';
        state = PushState(blocked ? PushStatus.blocked : PushStatus.off);
        return blocked
            ? 'Notifications are blocked for this site. Allow them in your browser’s site settings.'
            : 'Notifications weren’t turned on.';
      }
      await _register(subscription);
      state = const PushState(PushStatus.on);
      return null;
    } catch (_) {
      state = const PushState(PushStatus.off);
      return 'Couldn’t turn on push notifications. Try again.';
    }
  }

  Future<void> turnOff() async {
    state = PushState(state.status, busy: true);
    final subscription = await _push.unsubscribe();
    if (subscription != null) {
      try {
        await _ref.read(apiClientProvider).delete(ApiEndpoints.devices, data: {'push_token': subscription});
      } catch (_) {
        // The browser no longer has the subscription; the server forgets it on the next push (410 Gone).
      }
    }
    state = const PushState(PushStatus.off);
  }
}

/// Rebuilt whenever the signed-in user changes, which is what re-registers this browser for them.
final pushNotificationsProvider =
    StateNotifierProvider.autoDispose<PushNotificationsController, PushState>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return PushNotificationsController(ref);
});
