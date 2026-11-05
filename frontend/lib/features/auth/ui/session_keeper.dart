import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/error_text.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';
import '../providers/auth_providers.dart';

/// Keeps the signed-in user (and their roles) in step with the server.
///
/// The app shows the session saved in the browser, so a new tab opens signed in. But what that
/// session says about roles can go stale: if an admin removes someone's moderator role, their
/// tools must disappear. So `/me` is checked again when the tab comes back into view, every
/// [interval], and whenever the server answers 403. The server checks permissions on every
/// request regardless; this is about what the app shows.
class SessionKeeper extends ConsumerStatefulWidget {
  final Widget child;

  static const interval = Duration(minutes: 1);

  const SessionKeeper({super.key, required this.child});

  @override
  ConsumerState<SessionKeeper> createState() => _SessionKeeperState();
}

class _SessionKeeperState extends ConsumerState<SessionKeeper> with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<String>? _forbidden;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(SessionKeeper.interval, (_) => _refresh());
    _forbidden = ApiClient.forbidden.stream.listen((path) {
      if (!path.endsWith('/me')) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    // A burst of 403s (or focus changes) refreshes once.
    if (DateTime.now().difference(_last) < const Duration(seconds: 5)) return;
    _last = DateTime.now();
    try {
      await ref.read(authRepositoryProvider).getCurrentUser();
    } catch (_) {
      // 401/403 from /me already signed the user out; anything else keeps the session.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _forbidden?.cancel();
    super.dispose();
  }

  bool _reactivationChecked = false;

  /// Right after sign-in resolves (success, guest or error), check whether it was for a
  /// deactivated account and, if so, ask before reactivating it. `authStateProvider` only reaches
  /// AsyncData/AsyncError once the repository's `_init()` -- which sets this -- has finished, so
  /// there's no race with [IAuthRepository.consumePendingReactivation].
  Future<void> _checkPendingReactivation() async {
    if (_reactivationChecked) return;
    _reactivationChecked = true;
    final AccountDeactivatedException? pending = ref.read(authRepositoryProvider).consumePendingReactivation();
    if (pending == null || !mounted) return;

    final reactivate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivate your account?'),
        content: const Text(
          'This account was deactivated. Signing in again will reactivate it and make your profile '
          'and posts visible again. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reactivate and sign in')),
        ],
      ),
    );
    if (!mounted) return;

    if (reactivate == true) {
      try {
        await ref.read(authRepositoryProvider).confirmReactivation();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Couldn't reactivate your account: ${errorText(e)}")));
        }
      }
    } else {
      await ref.read(authRepositoryProvider).declineReactivation();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
      if (!next.isLoading) _checkPendingReactivation();
    });
    return widget.child;
  }
}
