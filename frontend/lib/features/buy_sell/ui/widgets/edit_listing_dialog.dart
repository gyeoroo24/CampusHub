import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/numbers_only_formatter.dart';
import '../../../../core/widgets/category_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/category_ref.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';

class EditListingDialog extends ConsumerStatefulWidget {
  final ListingItem item;

  const EditListingDialog({super.key, required this.item});

  @override
  ConsumerState<EditListingDialog> createState() => _EditListingDialogState();
}

class _EditListingDialogState extends ConsumerState<EditListingDialog> {
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
  late final TextEditingController _titleController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;
  late final TextEditingController _descController;
  CategoryRef? _selectedCategory;
  late bool _negotiable = widget.item.negotiable;
  bool _isSaving = false;

  /// The listing as saved, which the form starts from and Save compares against. Lists (e.g. My
  /// Postings) don't carry the description, so the full listing is loaded before the form shows.
  late ListingItem _original = widget.item;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _priceController = TextEditingController();
    _locationController = TextEditingController();
    _descController = TextEditingController();
    _fill(widget.item);
    _loadFullListing();
  }

  void _fill(ListingItem item) {
    _original = item;
    _titleController.text = item.title;
    _priceController.text = item.price.toStringAsFixed(item.price == item.price.roundToDouble() ? 0 : 2);
    _locationController.text = item.location;
    _descController.text = item.description;
    _selectedCategory = item.category;
    _negotiable = item.negotiable;
  }

  Future<void> _loadFullListing() async {
    try {
      final full = await ref.read(buySellRepositoryProvider).getListingById(widget.item.id);
      if (full != null && mounted) setState(() => _fill(full));
    } catch (_) {
      // Keep what we have: Save only sends the fields the seller changed, so nothing is wiped.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _numbersOnlyTimer?.cancel();
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    // Send only what changed, so a field the form never showed correctly can't overwrite the saved value.
    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    final location = _locationController.text.trim();
    final price = double.parse(_priceController.text.trim());
    final categoryId = _selectedCategory?.id;
    final changed = title != _original.title.trim() ||
        description != _original.description.trim() ||
        location != _original.location.trim() ||
        price != _original.price ||
        (categoryId != null && categoryId != _original.category.id) ||
        _negotiable != _original.negotiable;
    if (!changed) {
      Navigator.pop(context, false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(buySellRepositoryProvider).updateListing(
            widget.item.id,
            title: title != _original.title.trim() ? title : null,
            description: description != _original.description.trim() ? description : null,
            price: price != _original.price ? price : null,
            categoryId: categoryId != _original.category.id ? categoryId : null,
            location: location != _original.location.trim() ? location : null,
            negotiable: _negotiable != _original.negotiable ? _negotiable : null,
          );

      ref.invalidate(buySellListingsProvider);
      ref.read(buySellPaginationProvider.notifier).loadInitial();

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing updated successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update listing: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(buySellCategoriesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: const Text('Edit Listing', style: TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: _isLoading
            ? const SizedBox(width: 480, height: 160, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
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
                    prefixText: '₹ ',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a price.';
                    }
                    final parsed = double.tryParse(val.trim());
                    if (parsed == null || parsed < 0) {
                      return 'Please enter a valid price.';
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
                categoriesAsync.when(
                  data: (cats) {
                    final matchingCategory = cats.where((c) => c.id == _selectedCategory?.id);
                    final currentValue = matchingCategory.isNotEmpty
                        ? matchingCategory.first
                        : (cats.isNotEmpty ? cats.first : _selectedCategory);

                    return CategoryPicker(
                      categories: cats,
                      value: currentValue,
                      onChanged: (val) => setState(() => _selectedCategory = val),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(),
                  ),
                  error: (_, __) => CategoryPicker(
                    categories: [if (_selectedCategory != null) _selectedCategory!],
                    value: _selectedCategory,
                    onChanged: (val) => setState(() => _selectedCategory = val),
                  ),
                ),
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
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _descController,
                  maxLines: 4,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe condition, age, reasons for selling, etc.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving || _isLoading ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Changes'),
        ),
      ],
    );
  }
}
