import 'package:flutter/material.dart';
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;
  late final TextEditingController _descController;
  CategoryRef? _selectedCategory;
  late bool _negotiable = widget.item.negotiable;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _priceController = TextEditingController(text: widget.item.price.toStringAsFixed(0));
    _locationController = TextEditingController(text: widget.item.location);
    _descController = TextEditingController(text: widget.item.description);
    _selectedCategory = widget.item.category;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final price = double.parse(_priceController.text.trim());
      await ref.read(buySellRepositoryProvider).updateListing(
            widget.item.id,
            title: _titleController.text.trim(),
            description: _descController.text.trim(),
            price: price,
            categoryId: _selectedCategory?.id,
            location: _locationController.text.trim(),
            negotiable: _negotiable,
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
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
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
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (₹) *',
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
                  subtitle: const Text('Shows a "Negotiable" badge; people watching it are told'),
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
                  controller: _locationController,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Campus Location',
                    hintText: 'e.g. R-Block Hostel / CSA Dept',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
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
          onPressed: _isSaving ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Changes'),
        ),
      ],
    );
  }
}
