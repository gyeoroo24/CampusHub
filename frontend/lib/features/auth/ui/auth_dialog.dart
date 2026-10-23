import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';

/// Modal dialog prompting the user to sign in with their IISc email address and OTP.
class AuthDialog extends ConsumerStatefulWidget {
  final String title;
  final String message;

  const AuthDialog({
    super.key,
    this.title = 'Sign In to CampusHub',
    this.message = 'Please enter your IISc email address to continue.',
  });

  /// Static helper to trigger the dialog and return `true` if user is signed in.
  static Future<bool> ensureSignedIn(
    BuildContext context,
    WidgetRef ref, {
    String? title,
    String? message,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user != null && !user.isGuest) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AuthDialog(
        title: title ?? 'Sign In to CampusHub',
        message: message ?? 'An IISc email is required to publish posts and reports.',
      ),
    );

    return result ?? false;
  }

  @override
  ConsumerState<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<AuthDialog> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  bool _isOtpSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      await ref.read(authRepositoryProvider).sendOtp(email);

      if (mounted) {
        setState(() {
          _isOtpSent = true;
          _isLoading = false;
          _otpController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (!_otpFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final otp = _otpController.text.trim();
      await ref.read(authRepositoryProvider).verifyOtp(email, otp);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.school_rounded, color: Colors.indigo),
          const SizedBox(width: 10),
          Text(
            _isOtpSent ? 'Verify OTP Code' : widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isOtpSent ? _buildOtpForm() : _buildEmailForm(),
        ),
      ),
      actions: _isOtpSent ? _buildOtpActions() : _buildEmailActions(),
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        key: const ValueKey('email_form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'IISc Email',
              hintText: 'name@iisc.ac.in',
              prefixIcon: const Icon(Icons.email_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              errorText: _errorMessage,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              final trimmed = value.trim().toLowerCase();
              if (!trimmed.endsWith('@iisc.ac.in')) {
                return 'Must be an @iisc.ac.in email address';
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleSendOtp(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEmailActions() {
    return [
      TextButton(
        onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel / Browse as Guest'),
      ),
      FilledButton.icon(
        onPressed: _isLoading ? null : _handleSendOtp,
        icon: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('Send OTP'),
      ),
    ];
  }

  Widget _buildOtpForm() {
    final email = _emailController.text.trim();

    return Form(
      key: _otpFormKey,
      child: Column(
        key: const ValueKey('otp_form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    children: [
                      const TextSpan(text: 'Enter the 6-digit code sent to\n'),
                      TextSpan(
                        text: email,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Change Email',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _isOtpSent = false;
                          _errorMessage = null;
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            autofocus: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              errorText: _errorMessage,
            ),
            validator: (value) {
              if (value == null || value.trim().length != 6) {
                return 'Enter the complete 6-digit OTP code';
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleVerifyOtp(),
          ),
          const SizedBox(height: 8),
          Text(
            '💡 Mock Mode: Enter any 6 digits (e.g., 123456)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOtpActions() {
    return [
      TextButton(
        onPressed: _isLoading
            ? null
            : () {
                setState(() {
                  _isOtpSent = false;
                  _errorMessage = null;
                });
              },
        child: const Text('Back'),
      ),
      FilledButton.icon(
        onPressed: _isLoading ? null : _handleVerifyOtp,
        icon: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_rounded, size: 16),
        label: const Text('Verify & Sign In'),
      ),
    ];
  }
}
