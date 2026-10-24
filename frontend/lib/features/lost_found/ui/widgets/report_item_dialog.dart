import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'lost_found_detail_dialog.dart';

class ReportItemDialog extends ConsumerStatefulWidget {
  final PostType postType;
  final FutureOr<LostFoundItem?> Function(LostFoundItem) onSubmit;
  final String? userEmail;
  final String? userName;
  final String? userId;

  const ReportItemDialog({
    super.key,
    required this.postType,
    required this.onSubmit,
    this.userEmail,
    this.userName,
    this.userId,
  });

  @override
  ConsumerState<ReportItemDialog> createState() => _ReportItemDialogState();
}

class _ReportItemDialogState extends ConsumerState<ReportItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _locController = TextEditingController();
  final _imageUrlController = TextEditingController();

  DateTime _occurredAt = DateTime.now();
  CategoryRef? _selectedCategory;
  List<CategoryRef> _availableCategories = [];
  bool _isLoadingCategories = true;
  bool _isCustomCategory = false;
  final _customCategoryController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _descController.dispose();
    _locController.dispose();
    _imageUrlController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ref.read(lostFoundRepositoryProvider).fetchCategories();
      if (mounted) {
        setState(() {
          _availableCategories = cats;
          if (cats.isNotEmpty) {
            _selectedCategory = cats.first;
          }
          _isLoadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableCategories = const [
            CategoryRef(id: 1, name: 'ID Cards'),
            CategoryRef(id: 2, name: 'Electronics'),
            CategoryRef(id: 3, name: 'Personal Belongings'),
            CategoryRef(id: 4, name: 'Keys'),
            CategoryRef(id: 5, name: 'Documents'),
            CategoryRef(id: 6, name: 'Other'),
          ];
          _selectedCategory = _availableCategories.first;
          _isLoadingCategories = false;
        });
      }
    }
  }

  static String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} $month ${dt.year}, $hour:$minute $ampm';
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _occurredAt.isAfter(now) ? now : _occurredAt;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: widget.postType == PostType.lost
          ? 'Select Date Item Was Lost'
          : 'Select Date Item Was Found',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
      helpText: 'Select Approximate Time',
    );
    if (pickedTime == null || !mounted) return;

    var combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (combined.isAfter(now)) {
      combined = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incident time cannot be in the future. Reset to current time.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    setState(() {
      _occurredAt = combined;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLost = widget.postType == PostType.lost;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isLost ? Colors.pinkAccent.shade700 : Colors.teal.shade700;

    return ModalHistoryWrapper(
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Row(
        children: [
          Icon(
            isLost ? Icons.search_off_rounded : Icons.check_circle_outline_rounded,
            color: primaryColor,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(isLost ? 'Report Lost Item' : 'Report Found Item'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isLost
                              ? 'Provide details of the lost item. We will automatically match it when someone files a found report.'
                              : 'Found an item? Report it here so the owner can claim it.',
                          style: TextStyle(fontSize: 12, color: primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Category Dropdown
                if (_isLoadingCategories)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  DropdownButtonFormField<CategoryRef>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Item Category *'),
                    items: [
                      ..._availableCategories.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                      ),
                      const DropdownMenuItem(
                        value: CategoryRef(id: -1, name: '+ Add New Category...'),
                        child: Text('+ Add New Category...', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        if (val.id == -1) {
                          setState(() {
                            _isCustomCategory = true;
                            _selectedCategory = null;
                          });
                        } else {
                          setState(() {
                            _isCustomCategory = false;
                            _selectedCategory = val;
                          });
                        }
                      }
                    },
                    validator: (val) {
                      if (!_isCustomCategory && val == null) {
                        return 'Please select a category.';
                      }
                      return null;
                    },
                  ),
                  if (_isCustomCategory) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _customCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'New Category Name *',
                        hintText: 'e.g. Water Bottle, Scientific Calculator',
                      ),
                      validator: (val) {
                        if (_isCustomCategory && (val == null || val.trim().isEmpty)) {
                          return 'Please enter a category name.';
                        }
                        return null;
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 10),

                // Date & Time Picker Card
                InkWell(
                  onTap: _pickDateTime,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: isLost ? 'When was it lost? *' : 'When was it found? *',
                      suffixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
                    ),
                    child: Text(
                      _formatDateTime(_occurredAt),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Location
                TextFormField(
                  controller: _locController,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: isLost ? 'Last Seen Location *' : 'Found Location *',
                    hintText: 'e.g. Main Library 1st Floor, Near Nescafe, Dept of CSA',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please specify a campus location.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),

                // Detailed Description
                TextFormField(
                  controller: _descController,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Detailed Description *',
                    hintText: 'Describe distinguishing marks, color, brand, stickers, serial hints, contents, etc.',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please provide a detailed description.';
                    }
                    if (val.trim().length < 5) {
                      return 'Please provide at least 5 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),

                // Photo URL (optional)
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Photo URL (optional)',
                    hintText: 'Paste an image link or leave empty',
                    prefixIcon: Icon(Icons.photo_camera_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),

                // Contact notice
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reporter contact (${widget.userEmail ?? 'your IISc email'}) will be shown only to signed-in students.',
                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: primaryColor),
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(isLost ? 'Submit Lost Report' : 'Submit Found Report'),
        ),
      ],
    ));
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      CategoryRef cat = _selectedCategory ?? const CategoryRef(id: 6, name: 'Other');
      if (_isCustomCategory && _customCategoryController.text.trim().isNotEmpty) {
        try {
          cat = await ref.read(lostFoundRepositoryProvider).createCategory(
                _customCategoryController.text.trim(),
              );
          ref.invalidate(lostFoundCategoriesProvider);
        } catch (_) {
          cat = CategoryRef(id: 99, name: _customCategoryController.text.trim());
        }
      }

      final imageUrl = _imageUrlController.text.trim().isNotEmpty
          ? _imageUrlController.text.trim()
          : 'https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/600/400';

      final newItem = LostFoundItem(
        id: '',
        kind: widget.postType,
        description: _descController.text.trim(),
        category: cat,
        occurredAt: _occurredAt,
        location: _locController.text.trim().isNotEmpty
            ? _locController.text.trim()
            : 'IISc Campus',
        status: ReportStatus.open,
        reporter: UserRef(
          id: widget.userId ?? 'usr_me',
          name: widget.userName ?? (widget.userEmail?.split('@').first ?? 'Reporter'),
        ),
        coverPhotoUrl: imageUrl,
        photos: [Photo(s3Key: '', url: imageUrl, sortOrder: 0)],
        reporterContact: Contact(
          email: widget.userEmail ?? 'student@iisc.ac.in',
        ),
        createdAt: DateTime.now(),
      );

      final createdReport = await widget.onSubmit(newItem);

      if (!mounted) return;
      Navigator.of(context).pop();

      // If backend returns possible matches (FR-9), present them in a modal!
      if (createdReport != null &&
          createdReport.possibleMatches != null &&
          createdReport.possibleMatches!.isNotEmpty) {
        _showPossibleMatchesModal(context, createdReport);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.postType == PostType.lost
                  ? 'Lost report filed successfully.'
                  : 'Found report filed successfully.',
            ),
            backgroundColor: Colors.teal.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showPossibleMatchesModal(BuildContext parentContext, LostFoundItem report) {
    final matches = report.possibleMatches!;
    final otherKindLabel = report.kind == PostType.lost ? 'Found Items' : 'Lost Items';

    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber.shade700, size: 24),
            const SizedBox(width: 8),
            const Text('Possible Matches Found!'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your report was submitted. We discovered ${matches.length} active $otherKindLabel in category "${report.category.name}" that might match your item:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final match = matches[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: match.imageUrl.isNotEmpty
                            ? Image.network(
                                match.imageUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 44,
                                  height: 44,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.inventory_2_outlined, size: 20),
                                ),
                              )
                            : Container(
                                width: 44,
                                height: 44,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.inventory_2_outlined, size: 20),
                              ),
                      ),
                      title: Text(
                        match.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${match.location} • ${_formatDateTime(match.occurredAt)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () {
                        Navigator.pop(ctx);
                        showDialog(
                          context: parentContext,
                          builder: (_) => LostFoundDetailDialog(item: match),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
