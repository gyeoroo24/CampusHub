import '../api/api_exception.dart';

/// A short, user-facing message for an error caught in the UI
/// (the backend's `detail` for API errors, without the "ApiException:" prefix).
String errorText(Object error) {
  if (error is ApiException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}
