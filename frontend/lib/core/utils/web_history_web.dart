// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'web_history_support.dart';

WebHistoryManager createWebHistoryManager() => _WebHistoryWeb();

class _WebHistoryWeb implements WebHistoryManager {
  html.EventListener? _listener;
  bool _poppedByBrowser = false;

  /// Modals shown and not yet disposed, and callers of [settled] waiting for them to close.
  int _openModals = 0;
  bool _backPending = false;
  final List<Completer<void>> _waiters = [];

  @override
  void pushModalState(VoidCallback onPop) {
    if (!kIsWeb) return;
    _poppedByBrowser = false;
    _openModals++;

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
    if (_openModals > 0) _openModals--;
    if (_listener != null) {
      try {
        html.window.removeEventListener('popstate', _listener!);
      } catch (_) {}
      _listener = null;
    }
    if (!_poppedByBrowser) {
      _backPending = true;
      late html.EventListener once;
      var finished = false;
      void finish() {
        if (finished) return;
        finished = true;
        html.window.removeEventListener('popstate', once);
        _backPending = false;
        _wakeWaiters();
      }
      once = (_) => finish();
      try {
        html.window.addEventListener('popstate', once);
        html.window.history.back();
      } catch (_) {
        finish();
      }
      // In case the browser never reports it.
      Future.delayed(const Duration(milliseconds: 500), finish);
    } else {
      _wakeWaiters();
    }
  }

  void _wakeWaiters() {
    if (_openModals > 0 || _backPending) return;
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete();
    }
    _waiters.clear();
  }

  @override
  Future<void> get settled {
    if (_openModals == 0 && !_backPending) return Future.value();
    final waiter = Completer<void>();
    _waiters.add(waiter);
    // Never block navigation for long, e.g. if a modal stays open underneath.
    return waiter.future.timeout(const Duration(seconds: 1), onTimeout: () {});
  }
}
