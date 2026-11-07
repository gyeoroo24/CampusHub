import 'web_push.dart';

WebPush createWebPush() => _NoWebPush();

class _NoWebPush implements WebPush {
  @override
  String get permission => 'unsupported';

  @override
  Future<String?> subscribe(String publicKey) async => null;

  @override
  Future<String?> current() async => null;

  @override
  Future<String?> unsubscribe() async => null;
}
