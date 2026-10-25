import 'package:flutter/material.dart' show DateTimeRange;

/// Convenient date filter presets for Lost & Found and Buy & Sell feeds.
enum DatePresetFilter {
  all('All'),
  today('Today'),
  yesterday('Yesterday'),
  last3Days('Last 3 Days'),
  thisWeek('This Week'),
  thisMonth('This Month');

  final String label;
  const DatePresetFilter(this.label);

  /// Converts the preset into a concrete [DateTimeRange] relative to the current clock time.
  DateTimeRange? toDateTimeRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (this) {
      case DatePresetFilter.all:
        return null;
      case DatePresetFilter.today:
        return DateTimeRange(start: todayStart, end: todayEnd);
      case DatePresetFilter.yesterday:
        final yesterdayStart = todayStart.subtract(const Duration(days: 1));
        final yesterdayEnd = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59, 999);
        return DateTimeRange(start: yesterdayStart, end: yesterdayEnd);
      case DatePresetFilter.last3Days:
        final threeDaysAgo = todayStart.subtract(const Duration(days: 3));
        return DateTimeRange(start: threeDaysAgo, end: todayEnd);
      case DatePresetFilter.thisWeek:
        final weekAgo = todayStart.subtract(const Duration(days: 7));
        return DateTimeRange(start: weekAgo, end: todayEnd);
      case DatePresetFilter.thisMonth:
        final monthStart = DateTime(now.year, now.month, 1);
        return DateTimeRange(start: monthStart, end: todayEnd);
    }
  }
}
