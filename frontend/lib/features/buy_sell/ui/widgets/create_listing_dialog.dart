import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';

class CreateListingDialog extends ConsumerStatefulWidget {
  final Function(ListingItem) onSubmit;
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
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  final _imageUrlController = TextEditingController();

  CategoryRef? _selectedCategory;
  List<CategoryRef> _availableCategories = [];
  bool _isLoadingCategories = true;
  bool _isCustomCategory = false;
  final _customCategoryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ref.read(buySellRepositoryProvider).fetchCategories();
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
            CategoryRef(id: 1, name: 'Books'),
            CategoryRef(id: 2, name: 'Cycles'),
            CategoryRef(id: 3, name: 'Electronics'),
            CategoryRef(id: 4, name: 'Furniture'),
            CategoryRef(id: 5, name: 'Lab Equipment'),
            CategoryRef(id: 6, name: 'Other'),
          ];
          _selectedCategory = _availableCategories.first;
          _isLoadingCategories = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModalHistoryWrapper(
      child: AlertDialog(
        backgroundColor: Colors.white,
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
                const SizedBox(height: 8),
                if (_isLoadingCategories)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  DropdownButtonFormField<CategoryRef>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category *'),
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
                          setState(() => _isCustomCategory = true);
                        } else {
                          setState(() {
                            _selectedCategory = val;
                            _isCustomCategory = false;
                          });
                        }
                      }
                    },
                  ),
                  if (_isCustomCategory) ...[
                    const SizedBox(height: 8),
                    TextFormField(
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
                  controller: _locationController,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Campus Location',
                    hintText: 'e.g. R-Block Hostel / CSA Dept',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Photo URL (optional)',
                    hintText: 'Paste an image link or leave empty',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _handleSubmit,
          child: const Text('Publish Listing'),
        ),
      ],
    ));
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final price = double.parse(_priceController.text.trim());
    CategoryRef cat = _selectedCategory ?? const CategoryRef(id: 1, name: 'Other');

    if (_isCustomCategory && _customCategoryController.text.trim().isNotEmpty) {
      try {
        cat = await ref.read(buySellRepositoryProvider).createCategory(
              _customCategoryController.text.trim(),
            );
      } catch (_) {
        cat = CategoryRef(id: 99, name: _customCategoryController.text.trim());
      }
    }

    final imageUrl = _imageUrlController.text.trim().isNotEmpty
        ? _imageUrlController.text.trim()
        : 'https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/600/400';

    final newItem = ListingItem(
      id: '',
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      price: price,
      status: ListingStatus.available,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : 'IISc Campus',
      category: cat,
      seller: UserRef(
        id: widget.userId ?? 'usr_me',
        name: widget.userName ?? (widget.userEmail?.split('@').first ?? 'Seller'),
      ),
      coverPhotoUrl: imageUrl,
      photos: [
        Photo(s3Key: '', url: imageUrl, sortOrder: 0),
      ],
      createdAt: DateTime.now(),
    );

    widget.onSubmit(newItem);
    if (mounted) Navigator.pop(context);
  }
}
