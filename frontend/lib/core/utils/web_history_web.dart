// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'web_history_support.dart';

WebHistoryManager createWebHistoryManager() => _WebHistoryWeb();

class _WebHistoryWeb implements WebHistoryManager {
  html.EventListener? _listener;
  bool _poppedByBrowser = false;

  @override
  void pushModalState(VoidCallback onPop) {
    if (!kIsWeb) return;
    _poppedByBrowser = false;

    try {
      html.window.history.pushState({'type': 'modal_dialog'}, '', html.window.location.href);

      _listener = (event) {
        _poppedByBrowser = true;
        onPop();
      };

      html.window.addEventListener('popstate', _listener!);
    } catch (_) {}
  }

  @override
  void popModalState() {
    if (!kIsWeb) return;
    if (_listener != null) {
      try {
        html.window.removeEventListener('popstate', _listener!);
      } catch (_) {}
      _listener = null;
    }
    if (!_poppedByBrowser) {
      try {
        html.window.history.back();
      } catch (_) {}
    }
  }
}
