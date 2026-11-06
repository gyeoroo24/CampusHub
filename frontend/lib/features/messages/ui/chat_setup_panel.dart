import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_text.dart';
import '../crypto/chat_crypto.dart';
import '../providers/messages_providers.dart';

/// Only for accounts that set a messaging passphrase before it was removed, on a device that never
/// unlocked it: enter it once (the key then moves to the server-held backup), or start over.
class ChatSetupPanel extends ConsumerStatefulWidget {
  final ChatSession session;

  const ChatSetupPanel({super.key, required this.session});

  @override
  ConsumerState<ChatSetupPanel> createState() => _ChatSetupPanelState();
}

class _ChatSetupPanelState extends ConsumerState<ChatSetupPanel> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(conversationsProvider);
    } on WrongPassphraseException {
      if (mounted) setState(() => _error = 'That passphrase is not right.');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_passphrase.text.isEmpty) {
      setState(() => _error = 'Enter your old messaging passphrase.');
      return;
    }
    await _run(() => ref.read(chatSessionProvider.notifier).unlock(_passphrase.text));
  }

  Future<void> _startOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over without your old messages?'),
        content: const Text(
          'Your old messages were locked with that passphrase, and they can’t be opened without it.\n\n'
          'Starting over makes a new messaging key. You can keep chatting, but messages sent or received so far '
          'will no longer be readable.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _run(() => ref.read(chatSessionProvider.notifier).resetKey());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const title = 'Unlock your old messages';
    const body = 'Messaging no longer uses a passphrase. Your earlier messages were locked with the one you chose, '
        'so enter it one last time on this device. After that you won’t be asked again, on any device.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('chat_passphrase'),
                      controller: _passphrase,
                      obscureText: _obscure,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Old messaging passphrase',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show' : 'Hide',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(_busy ? 'Unlocking…' : 'Unlock'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _startOver,
                      child: const Text('Forgot it? Start over'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
