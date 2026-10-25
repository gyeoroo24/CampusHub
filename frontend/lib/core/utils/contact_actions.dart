import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Email" opens the mail app and "Call" the dialer. Where neither is available (some desktop
/// browsers), the address is copied instead and a message says so.
Future<void> contactBy(BuildContext context, {String? email, String? phone, String? subject}) async {
  final value = (email ?? phone ?? '').trim();
  if (value.isEmpty) return;
  final uri = email != null
      ? Uri(scheme: 'mailto', path: value, query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}')
      : Uri(scheme: 'tel', path: value.replaceAll(RegExp(r'[^0-9+]'), ''));
  final messenger = ScaffoldMessenger.maybeOf(context);
  bool opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {}
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: value));
    messenger?.showSnackBar(SnackBar(
      content: Text("Couldn't open your ${email != null ? 'mail app' : 'phone app'}, so $value is copied."),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
