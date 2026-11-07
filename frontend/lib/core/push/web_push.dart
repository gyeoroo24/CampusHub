import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart';

/// This browser's Web Push subscription (FR-22), through web/push.js. Off the web every call reports
/// "unsupported" and does nothing.
abstract class WebPush {
  static final WebPush instance = createWebPush();

  /// 'unsupported', 'default' (not asked yet), 'granted' or 'denied'.
  String get permission;

  /// Asks for permission if needed, then subscribes with the server's VAPID [publicKey]. Returns the
  /// subscription JSON to register with the API, or null if the browser can't or the person said no.
  Future<String?> subscribe(String publicKey);

  /// The existing subscription's JSON, without asking anything; null if there is none.
  Future<String?> current();

  /// Ends this browser's subscription. Returns its JSON (to unregister it with the API), or null.
  Future<String?> unsubscribe();
}
