import 'package:flutter/services.dart';

/// Lets through digits and one decimal point. When a keystroke or paste has anything else, the edit is
/// refused and [onRejected] runs, so the field can say it only takes numbers.
class NumbersOnlyFormatter extends TextInputFormatter {
  final VoidCallback onRejected;

  NumbersOnlyFormatter({required this.onRejected});

  static final _allowed = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (_allowed.hasMatch(newValue.text)) return newValue;
    onRejected();
    return oldValue;
  }
}
