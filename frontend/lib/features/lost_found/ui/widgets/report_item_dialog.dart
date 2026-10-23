import 'package:flutter/material.dart';
import '../../domain/lost_found_item.dart';

class ReportItemDialog extends StatefulWidget {
  final PostType postType;
  final Function(LostFoundItem) onSubmit;
  final String? userEmail;
  final String? userId;

  const ReportItemDialog({
    super.key,
    required this.postType,
    required this.onSubmit,
    this.userEmail,
    this.userId,
  });

  @override
  State<ReportItemDialog> createState() => _ReportItemDialogState();
}

class _ReportItemDialogState extends State<ReportItemDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locController = TextEditingController();
  final _timeController = TextEditingController();
  String _category = 'Personal Belongings';

  final List<String> _categories = [
    'ID Cards',
    'Electronics',
    'Personal Belongings',
    'Keys',
    'Books & Stationary',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    final hour = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    _timeController.text = 'Today at $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isLost = widget.postType == PostType.lost;

    return AlertDialog(
      title: Text(isLost ? 'Report Lost Item' : 'Report Found Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Item Name / Short Title'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _category = val);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _locController,
              decoration: InputDecoration(
                labelText: isLost ? 'Last Seen Location' : 'Found Location',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _timeController,
              decoration: InputDecoration(
                labelText: isLost ? 'Time When Lost' : 'Time When Found',
                hintText: 'e.g. Oct 21, 2026 at 3:00 PM',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Detailed Description (distinguishing marks, color, etc.)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.isNotEmpty) {
              final report = LostFoundItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                reporterId: widget.userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
                title: _titleController.text,
                description: _descController.text,
                category: _category,
                location: _locController.text.isEmpty ? 'IISc Campus' : _locController.text,
                imageUrls: ['https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/600/400'],
                type: widget.postType,
                eventTime: _timeController.text.isEmpty ? 'Just now' : _timeController.text,
                dateReported: DateTime.now(),
                reporterContact: widget.userEmail ?? 'user@iisc.ac.in',
              );
              widget.onSubmit(report);
              Navigator.pop(context);
            }
          },
          child: Text(isLost ? 'Submit Lost Report' : 'Submit Found Report'),
        ),
      ],
    );
  }
}
