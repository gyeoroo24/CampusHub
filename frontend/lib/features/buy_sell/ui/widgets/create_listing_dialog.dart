import 'package:flutter/material.dart';
import '../../domain/buy_sell_item.dart';

class CreateListingDialog extends StatefulWidget {
  final Function(ListingItem) onSubmit;
  final String? userEmail;
  final String? userId;

  const CreateListingDialog({
    super.key,
    required this.onSubmit,
    this.userEmail,
    this.userId,
  });

  @override
  State<CreateListingDialog> createState() => _CreateListingDialogState();
}

class _CreateListingDialogState extends State<CreateListingDialog> {
  final _titleController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  String _category = 'Books';

  final List<String> _categories = [
    'Books',
    'Cycles',
    'Electronics',
    'Furniture',
    'Lab Equipment',
    'Other'
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Post Buy & Sell Listing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _costPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Original Cost Price (₹)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _sellingPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Selling Price (₹)'),
                  ),
                ),
              ],
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
            TextField(controller: _locationController, decoration: const InputDecoration(labelText: 'Campus Location')),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Detailed Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.isNotEmpty && _sellingPriceController.text.isNotEmpty) {
              final sellingPrice = double.tryParse(_sellingPriceController.text) ?? 0.0;
              final costPrice = double.tryParse(_costPriceController.text) ?? sellingPrice;

              final item = ListingItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                sellerId: widget.userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
                title: _titleController.text,
                description: _descController.text,
                costPrice: costPrice,
                sellingPrice: sellingPrice,
                category: _category,
                location: _locationController.text.isEmpty ? 'IISc Campus' : _locationController.text,
                imageUrls: ['https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/600/400'],
                status: ListingStatus.available,
                sellerEmail: widget.userEmail ?? 'user@iisc.ac.in',
                createdAt: DateTime.now(),
              );
              widget.onSubmit(item);
              Navigator.pop(context);
            }
          },
          child: const Text('Publish Listing'),
        ),
      ],
    );
  }
}
