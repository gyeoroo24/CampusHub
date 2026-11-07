import 'dart:js_interop';

import 'web_push.dart';

WebPush createWebPush() => _BrowserWebPush();

@JS('campushubPush')
external _PushHelpers? get _helpers;

extension type _PushHelpers._(JSObject _) implements JSObject {
  external JSString permission();
  external JSPromise<JSString> subscribe(JSString publicKey);
  external JSPromise<JSString> current();
  external JSPromise<JSString> unsubscribe();
}

class _BrowserWebPush implements WebPush {
  String? _orNull(JSString value) => value.toDart.isEmpty ? null : value.toDart;

  @override
  String get permission => _helpers?.permission().toDart ?? 'unsupported';

  @override
  Future<String?> subscribe(String publicKey) async {
    final h = _helpers;
    return h == null ? null : _orNull(await h.subscribe(publicKey.toJS).toDart);
  }

  @override
  Future<String?> current() async {
    final h = _helpers;
    return h == null ? null : _orNull(await h.current().toDart);
  }

  @override
  Future<String?> unsubscribe() async {
    final h = _helpers;
    return h == null ? null : _orNull(await h.unsubscribe().toDart);
  }
}
