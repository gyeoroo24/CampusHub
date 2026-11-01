import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';

/// Texts a code to [phone] and asks for it, like the email sign-in. Returns true once the number
/// is verified and saved on the profile.
Future<bool> showVerifyPhoneDialog(BuildContext context, String phone) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerifyPhoneDialog(phone: phone),
    ) ??
    false;

class _VerifyPhoneDialog extends ConsumerStatefulWidget {
  final String phone;

  const _VerifyPhoneDialog({required this.phone});

  @override
  ConsumerState<_VerifyPhoneDialog> createState() => _VerifyPhoneDialogState();
}

class _VerifyPhoneDialogState extends ConsumerState<_VerifyPhoneDialog> {
  final _code = TextEditingController();
  bool _sending = true;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPhoneCode(widget.phone);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyPhone(widget.phone, _code.text);
      ref.invalidate(currentUserProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.sms_outlined),
      title: const Text('Verify your phone number'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter the 6-digit code sent to ${widget.phone}.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              key: const Key('phone_otp'),
              controller: _code,
              autofocus: true,
              enabled: !_verifying,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, letterSpacing: 8),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _verify(),
              decoration: InputDecoration(
                counterText: '',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _sending || _verifying ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Resend code', style: TextStyle(color: theme.hintColor)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _verifying ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _verifying || _sending ? null : _verify,
          child: Text(_verifying ? 'Verifying…' : 'Verify'),
        ),
      ],
    );
  }
}
