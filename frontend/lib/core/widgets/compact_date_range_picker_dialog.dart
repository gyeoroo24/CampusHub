import 'package:flutter/material.dart';
import '../utils/web_history_support.dart';

class CompactDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialDateRange;

  const CompactDateRangePickerDialog({super.key, this.initialDateRange});

  @override
  State<CompactDateRangePickerDialog> createState() => _CompactDateRangePickerDialogState();
}

class _CompactDateRangePickerDialogState extends State<CompactDateRangePickerDialog> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    final now = DateTime.now();

    if (initial != null) {
      _startDate = initial.start;
      _startTime = TimeOfDay.fromDateTime(initial.start);
      _endDate = initial.end;
      _endTime = TimeOfDay.fromDateTime(initial.end);
    } else {
      _startDate = now.subtract(const Duration(days: 7));
      _startTime = const TimeOfDay(hour: 0, minute: 0);
      _endDate = now;
      _endTime = const TimeOfDay(hour: 23, minute: 59);
    }
  }

  void _applyPreset(int days) {
    final now = DateTime.now();
    setState(() {
      _startDate = now.subtract(Duration(days: days));
      _startTime = const TimeOfDay(hour: 0, minute: 0);
      _endDate = now;
      _endTime = const TimeOfDay(hour: 23, minute: 59);
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) _startDate = _endDate;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  DateTimeRange _getRange() {
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
    final end = DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute);
    return DateTimeRange(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ModalHistoryWrapper(
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.date_range_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('Filter Date & Time', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 16),
            Text('Quick Presets', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(label: const Text('Today', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(0)),
                ActionChip(label: const Text('Past 3 Days', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(3)),
                ActionChip(label: const Text('Past 7 Days', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(7)),
                ActionChip(label: const Text('Past 30 Days', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(30)),
              ],
            ),
            const Divider(height: 24),
            _buildDateTimeBox('Start Date & Time', _startDate, _startTime, () => _pickDate(true), () => _pickTime(true), isDark),
            const SizedBox(height: 12),
            _buildDateTimeBox('End Date & Time', _endDate, _endTime, () => _pickDate(false), () => _pickTime(false), isDark),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.of(context).pop('CLEAR'),
                    child: const Text('Clear Filter'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.of(context).pop(_getRange()),
                    child: const Text('Apply Range'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildDateTimeBox(String title, DateTime date, TimeOfDay time, VoidCallback onTapDate, VoidCallback onTapTime, bool isDark) {
    final dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    final timeStr = time.format(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade300)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTapDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(dateStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onTapTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(timeStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
