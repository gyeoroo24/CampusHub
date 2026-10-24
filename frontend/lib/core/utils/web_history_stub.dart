import 'dart:ui';
import 'web_history_support.dart';

WebHistoryManager createWebHistoryManager() => _WebHistoryStub();

class _WebHistoryStub implements WebHistoryManager {
  @override
  void pushModalState(VoidCallback onPop) {}

  @override
  void popModalState() {}
}
