import 'package:flutter/material.dart';
import '../../../../core/widgets/category_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/category_ref.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';

class EditReportDialog extends ConsumerStatefulWidget {
  final LostFoundItem item;

  const EditReportDialog({super.key, required this.item});

  @override
  ConsumerState<EditReportDialog> createState() => _EditReportDialogState();
}

class _EditReportDialogState extends ConsumerState<EditReportDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _locationController;
  late final TextEditingController _descController;
  CategoryRef? _selectedCategory;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _locationController = TextEditingController(text: widget.item.location);
    _descController = TextEditingController(text: widget.item.description);
    _selectedCategory = widget.item.category;
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(lostFoundRepositoryProvider).updateReport(
            widget.item.id,
            type: widget.item.kind,
            description: _descController.text.trim(),
            categoryId: _selectedCategory?.id,
            location: _locationController.text.trim(),
          );

      ref.invalidate(lostReportsProvider);
      ref.invalidate(foundReportsProvider);
      ref.read(lostReportsPaginationProvider.notifier).loadInitial();
      ref.read(foundReportsPaginationProvider.notifier).loadInitial();

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report updated successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update report: $e'),
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
    final categoriesAsync = ref.watch(lostFoundCategoriesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Text(
        'Edit ${widget.item.kind == PostType.lost ? "Lost" : "Found"} Report',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
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
                    labelText: 'Campus Location *',
                    hintText: 'e.g. Near Physics Canteen',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter location.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  maxLength: 2000, // same limit as the API and the report form
                  decoration: const InputDecoration(
                    labelText: 'Detailed Description *',
                    hintText: 'Color, brand, identifying marks, where/when last seen...',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter description.';
                    }
                    return null;
                  },
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
