import 'package:flutter/material.dart';
import 'web_history_stub.dart'
    if (dart.library.html) 'web_history_web.dart';

abstract class WebHistoryManager {
  static final WebHistoryManager instance = createWebHistoryManager();

  void pushModalState(VoidCallback onPop);
  void popModalState();

  /// Completes once the browser has applied the `history.back()` of the last closed modal.
  /// Await it after closing a dialog and before navigating, or that back step undoes the navigation.
  Future<void> get settled;
}

/// A wrapper widget for modal dialogs that intercepts browser/system back buttons on web.
/// Prevents the browser from leaving or closing the website when a modal is dismissed via back button.
class ModalHistoryWrapper extends StatefulWidget {
  final Widget child;

  /// False: just show [child], e.g. for a dialog that is itself a router page with its own address.
  final bool enabled;

  const ModalHistoryWrapper({super.key, required this.child, this.enabled = true});

  @override
  State<ModalHistoryWrapper> createState() => _ModalHistoryWrapperState();
}

class _ModalHistoryWrapperState extends State<ModalHistoryWrapper> {
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WebHistoryManager.instance.pushModalState(() {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    });
  }

  @override
  void dispose() {
    if (widget.enabled) WebHistoryManager.instance.popModalState();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
