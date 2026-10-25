/// Input rules shared by forms. Each mirrors the backend's check, so the app rejects a value
/// before sending it instead of showing the server's error.
library;

/// IISc addresses, including subdomains such as alum.iisc.ac.in (same rule as the API and the
/// Cognito pre-sign-up trigger). Rejects look-alikes such as fakeiisc.ac.in.
final RegExp _iiscEmail = RegExp(r'^[^@\s]+@([a-z0-9-]+\.)*iisc\.ac\.in$', caseSensitive: false);

bool isIiscEmail(String email) => _iiscEmail.hasMatch(email.trim());

/// Profile phone: an optional leading + and 10 to 15 digits (the users.phone CHECK constraint).
/// Spaces and dashes typed for readability are removed by [normalizePhone] before checking.
String normalizePhone(String phone) => phone.replaceAll(RegExp(r'[\s-]'), '');

String? validatePhone(String? value) {
  final v = normalizePhone(value ?? '');
  if (v.isEmpty) return null; // optional
  if (!RegExp(r'^\+?[0-9]+$').hasMatch(v)) return 'Use digits only, with an optional + in front';
  final digits = v.replaceAll('+', '').length;
  if (digits < 10) return 'Too short: a phone number has at least 10 digits';
  if (digits > 15) return 'Too long: at most 15 digits, including the country code';
  return null;
}
