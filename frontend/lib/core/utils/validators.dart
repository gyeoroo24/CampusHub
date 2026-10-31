/// Input rules shared by forms. Each mirrors the backend's check, so the app rejects a value
/// before sending it instead of showing the server's error.
library;

/// IISc addresses, including subdomains such as alum.iisc.ac.in (same rule as the API and the
/// Cognito pre-sign-up trigger). Rejects look-alikes such as fakeiisc.ac.in.
final RegExp _iiscEmail = RegExp(r'^[^@\s]+@([a-z0-9-]+\.)*iisc\.ac\.in$', caseSensitive: false);

bool isIiscEmail(String email) => _iiscEmail.hasMatch(email.trim());

// Profile phone numbers are checked per country: see phone_countries.dart.
