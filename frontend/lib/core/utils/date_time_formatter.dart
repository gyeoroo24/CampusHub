/// Utilities for human-friendly date and time formatting.
class DateTimeFormatter {
  DateTimeFormatter._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Relative human-readable time (e.g., 'Just now', '15m ago', '3h ago', 'Yesterday', '18 Oct').
  static String timeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (dateTime.year == now.year) {
      return '${dateTime.day} ${_months[dateTime.month - 1]}';
    } else {
      return '${dateTime.day} ${_months[dateTime.month - 1]} ${dateTime.year}';
    }
  }

  /// Full formatted timestamp (e.g., '22 Oct 2026, 04:30 PM').
  static String fullDateTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final month = _months[dateTime.month - 1];

    return '${dateTime.day} $month ${dateTime.year}, $hour:$minute $period';
  }
}
