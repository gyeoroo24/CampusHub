import 'package:flutter/material.dart';

class CategoryFilterBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final sortedCategories = <String>['All'];
    final nonAllCategories = categories.where((c) => c != 'All').toList()..sort();
    sortedCategories.addAll(nonAllCategories);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sortedCategories.map((cat) {
          final isSelected = selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (_) => onSelected(cat),
              showCheckmark: false,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              labelStyle: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
