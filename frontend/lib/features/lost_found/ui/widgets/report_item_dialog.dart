import 'dart:async';
import '../../../../core/widgets/category_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/error_text.dart';
import '../../../../core/widgets/photo_picker_field.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/user_ref.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'possible_matches_section.dart';

class ReportItemDialog extends ConsumerStatefulWidget {
  final PostType postType;
  final FutureOr<LostFoundItem?> Function(LostFoundItem) onSubmit;
  final String? userEmail;
  final String? userName;
  final String? userId;
  final BuildContext? parentContext;

  const ReportItemDialog({
    super.key,
    required this.postType,
    required this.onSubmit,
    this.userEmail,
    this.userName,
    this.userId,
    this.parentContext,
  });

  @override
  ConsumerState<ReportItemDialog> createState() => _ReportItemDialogState();
}

class _ReportItemDialogState extends ConsumerState<ReportItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locController = TextEditingController();
  List<PickedPhoto> _photos = [];

  DateTime _occurredAt = DateTime.now();
  CategoryRef? _selectedCategory;
  List<CategoryRef> _availableCategories = [];
  bool _isLoadingCategories = true;
  bool _isCustomCategory = false;
  final _customCategoryController = TextEditingController();
  bool _isSubmitting = false;

  // Category auto-suggestion from the title (as in Buy & Sell): a hint only, never auto-applied.
  Timer? _suggestDebounce;
  CategoryRef? _suggestedCategory;
  bool _categoryTouchedByUser = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _descController.dispose();
    _locController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    _suggestDebounce?.cancel();
    if (_categoryTouchedByUser || _isCustomCategory) return;
    final title = _titleController.text.trim();
    if (title.length < 4) {
      if (_suggestedCategory != null) setState(() => _suggestedCategory = null);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 500), () => _fetchSuggestion(title));
  }

  Future<void> _fetchSuggestion(String title) async {
    try {
      final suggestion = await ref.read(lostFoundRepositoryProvider).suggestCategory(title);
      if (!mounted || _titleController.text.trim() != title) return; // stale request
      setState(() => _suggestedCategory = suggestion?.id == _selectedCategory?.id ? null : suggestion);
    } catch (_) {
      // Suggestion is a nice-to-have; silently skip on any failure.
    }
  }

  void _applySuggestion() {
    final suggestion = _suggestedCategory;
    if (suggestion == null) return;
    final match = _availableCategories.where((c) => c.id == suggestion.id);
    setState(() {
      _selectedCategory = match.isNotEmpty ? match.first : suggestion;
      _isCustomCategory = false;
      _categoryTouchedByUser = true;
      _suggestedCategory = null;
    });
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

                TextFormField(
                  controller: _titleController,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: 'Title *',
                    hintText: isLost ? 'e.g. Black JBL earbuds' : 'e.g. Blue Milton water bottle',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Please give the item a short title.' : null,
                ),
                const SizedBox(height: 6),

                // Category Dropdown
                if (_isLoadingCategories)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  CategoryPicker(
                    label: 'Item Category *',
                    categories: _availableCategories,
                    value: _selectedCategory,
                    addNewLabel: CategoryPicker.addNew.name,
                    onChanged: (val) {
                      if (val.id == -1) {
                        setState(() {
                          _isCustomCategory = true;
                          _selectedCategory = null;
                          _suggestedCategory = null;
                        });
                      } else {
                        setState(() {
                          _isCustomCategory = false;
                          _selectedCategory = val;
                          _categoryTouchedByUser = true;
                          _suggestedCategory = null;
                        });
                      }
                    },
                    validator: (val) {
                      if (!_isCustomCategory && _selectedCategory == null) {
                        return 'Please select a category.';
                      }
                      return null;
                    },
                  ),
                  if (_suggestedCategory != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          avatar: const Icon(Icons.auto_awesome, size: 16),
                          label: Text('Suggested category: ${_suggestedCategory!.name}'),
                          onPressed: _applySuggestion,
                        ),
                      ),
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

                PhotoPickerField(
                  photos: _photos,
                  enabled: !_isSubmitting,
                  onChanged: (p) => setState(() => _photos = p),
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
      CategoryRef cat = _selectedCategory ?? const CategoryRef(id: 6, name: 'Others');
      if (_isCustomCategory && _customCategoryController.text.trim().isNotEmpty) {
        cat = await ref.read(lostFoundRepositoryProvider).createCategory(_customCategoryController.text.trim());
        ref.invalidate(lostFoundCategoriesProvider);
      }

      final photos = await uploadPickedPhotos(
        ref,
        _photos,
        kind: widget.postType == PostType.lost ? 'lost_report_photo' : 'found_report_photo',
      );

      final newItem = LostFoundItem(
        id: '',
        kind: widget.postType,
        title: _titleController.text.trim(),
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
        coverPhotoUrl: photos.isEmpty ? null : photos.first.url,
        photos: photos,
        reporterContact: Contact(
          email: widget.userEmail ?? 'student@iisc.ac.in',
        ),
        createdAt: DateTime.now(),
      );

      final createdReport = await widget.onSubmit(newItem);

      final hostContext = widget.parentContext ?? (mounted ? Navigator.of(context).context : null);
      if (!mounted) return;
      Navigator.of(context).pop();

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
      // FR-9: the server ranks possible matches in the background; show them as they arrive.
      if (createdReport != null && hostContext != null && hostContext.mounted) {
        _showPossibleMatchesModal(hostContext, createdReport);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: ${errorText(e)}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showPossibleMatchesModal(BuildContext parentContext, LostFoundItem report) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Report filed'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(ctx).width - 48).clamp(280.0, 480.0),
          child: SingleChildScrollView(child: PossibleMatchesSection(item: report)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
