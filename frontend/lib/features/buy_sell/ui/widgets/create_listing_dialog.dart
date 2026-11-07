import 'dart:async';
import '../../../../core/widgets/category_picker.dart';

import 'package:flutter/material.dart';
import '../../../../core/utils/numbers_only_formatter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/utils/error_text.dart';
import '../../../../core/widgets/photo_picker_field.dart';
import '../../../../core/models/user_ref.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';

class CreateListingDialog extends ConsumerStatefulWidget {
  /// Saves the listing; the dialog waits for it and shows any error.
  final FutureOr<void> Function(ListingItem) onSubmit;
  final String? userEmail;
  final String? userName;
  final String? userId;

  const CreateListingDialog({
    super.key,
    required this.onSubmit,
    this.userEmail,
    this.userName,
    this.userId,
  });

  @override
  ConsumerState<CreateListingDialog> createState() => _CreateListingDialogState();
}

class _CreateListingDialogState extends ConsumerState<CreateListingDialog> {
  bool _numbersOnly = false;
  Timer? _numbersOnlyTimer;

  /// Shows "only numbers" under the price for a few seconds after a letter is typed or pasted.
  void _flashNumbersOnly() {
    _numbersOnlyTimer?.cancel();
    if (!_numbersOnly) setState(() => _numbersOnly = true);
    _numbersOnlyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _numbersOnly = false);
    });
  }

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  List<PickedPhoto> _photos = [];
  bool _isSubmitting = false;
  String? _submitError;

  CategoryRef? _selectedCategory;
  List<CategoryRef> _availableCategories = [];
  bool _isLoadingCategories = true;
  bool _isCustomCategory = false;
  bool _negotiable = false;
  final _customCategoryController = TextEditingController();

  // Category auto-suggestion (future plan §2.4): a hint only, never auto-applied.
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
    _numbersOnlyTimer?.cancel();
    _suggestDebounce?.cancel();
    _titleController.removeListener(_onTitleChanged);
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
      final suggestion = await ref.read(buySellRepositoryProvider).suggestCategory(title);
      if (!mounted || _titleController.text.trim() != title) return; // stale request
      if (suggestion != null && suggestion.id == _selectedCategory?.id) {
        setState(() => _suggestedCategory = null);
        return;
      }
      setState(() => _suggestedCategory = suggestion);
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
      final cats = await ref.read(buySellRepositoryProvider).fetchCategories();
      if (mounted) {
        setState(() {
          // No category picked for the user: the first one alphabetically is rarely right, and a wrong
          // default is easy to miss. The picker's validator asks for one instead.
          _availableCategories = cats;
          _isLoadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableCategories = const [
            CategoryRef(id: 1, name: 'Books'),
            CategoryRef(id: 2, name: 'Cycles'),
            CategoryRef(id: 3, name: 'Electronics'),
            CategoryRef(id: 4, name: 'Furniture'),
            CategoryRef(id: 5, name: 'Lab Equipment'),
            CategoryRef(id: 6, name: 'Others'),
          ];
          _isLoadingCategories = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ModalHistoryWrapper(
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Row(
        children: [
          Icon(Icons.storefront_outlined, size: 22),
          SizedBox(width: 8),
          Text('Post Listing for Sale'),
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
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _titleController,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Listing Title *',
                    hintText: 'e.g. Hero Sprint 21-Speed Bicycle',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a listing title.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [NumbersOnlyFormatter(onRejected: _flashNumbersOnly)],
                  decoration: InputDecoration(
                    labelText: 'Price (₹) *',
                    helperText: _numbersOnly ? 'Only numbers can go here, e.g. 1500 or 99.50' : null,
                    helperStyle: const TextStyle(color: Colors.orange),
                    hintText: 'e.g. 1500',
                    prefixText: '₹ ',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a price.';
                    }
                    final parsed = double.tryParse(val.trim());
                    if (parsed == null || parsed < 0) {
                      return 'Please enter a valid non-negative amount.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _negotiable,
                  onChanged: (v) => setState(() => _negotiable = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Price is negotiable'),
                ),
                const SizedBox(height: 8),
                if (_isLoadingCategories)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  CategoryPicker(
                    categories: _availableCategories,
                    value: _selectedCategory,
                    addNewLabel: CategoryPicker.addNew.name,
                    validator: (_) =>
                        !_isCustomCategory && _selectedCategory == null ? 'Please select a category.' : null,
                    onChanged: (val) {
                      if (val.id == -1) {
                        setState(() {
                          _isCustomCategory = true;
                          _categoryTouchedByUser = true;
                          _suggestedCategory = null;
                        });
                      } else {
                        setState(() {
                          _selectedCategory = val;
                          _isCustomCategory = false;
                          _categoryTouchedByUser = true;
                          _suggestedCategory = null;
                        });
                      }
                    },
                  ),
                  if (_suggestedCategory != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.auto_awesome, size: 16),
                        label: Text('Suggested category: ${_suggestedCategory!.name}'),
                        onPressed: _applySuggestion,
                      ),
                    ),
                  if (_isCustomCategory) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      controller: _customCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'New Category Name',
                        hintText: 'e.g. Musical Instruments',
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
                const SizedBox(height: 8),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _locationController,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Campus Location',
                    hintText: 'e.g. R-Block Hostel / CSA Dept',
                  ),
                ),
                const SizedBox(height: 8),
                PhotoPickerField(
                  photos: _photos,
                  enabled: !_isSubmitting,
                  onChanged: (p) => setState(() => _photos = p),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _descController,
                  maxLines: 3,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Detailed Description',
                    hintText: 'Describe condition, age, reasons for selling, etc.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_submitError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
        TextButton(onPressed: _isSubmitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleSubmit,
          icon: _isSubmitting
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.publish_rounded, size: 16),
          label: Text(_isSubmitting ? (_photos.isEmpty ? 'Publishing…' : 'Uploading photos…') : 'Publish Listing'),
        ),
      ],
    ));
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await _submit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = "Couldn't publish: ${errorText(e)}";
        });
      }
    }
  }

  Future<void> _submit() async {
    final price = double.parse(_priceController.text.trim());
    CategoryRef cat = _selectedCategory ?? const CategoryRef(id: 1, name: 'Others');

    if (_isCustomCategory && _customCategoryController.text.trim().isNotEmpty) {
      cat = await ref.read(buySellRepositoryProvider).createCategory(_customCategoryController.text.trim());
      ref.invalidate(buySellCategoriesProvider);
    }

    final photos = await uploadPickedPhotos(ref, _photos, kind: 'listing_photo');

    final newItem = ListingItem(
      id: '',
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      price: price,
      negotiable: _negotiable,
      status: ListingStatus.available,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : 'IISc Campus',
      category: cat,
      seller: UserRef(
        id: widget.userId ?? 'usr_me',
        name: widget.userName ?? (widget.userEmail?.split('@').first ?? 'Seller'),
      ),
      coverPhotoUrl: photos.isEmpty ? null : photos.first.url,
      photos: photos,
      createdAt: DateTime.now(),
    );

    await widget.onSubmit(newItem);
  }
}
