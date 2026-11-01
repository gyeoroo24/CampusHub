import 'package:flutter/material.dart';
import '../../../../core/enums/sort_option.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';

class CombinedFilterDropdown extends StatelessWidget {
  final BuySellFilterState filterState;
  final ValueChanged<BuySellFilterState> onFilterChanged;

  // Kept for backwards compatibility
  final SortOption? currentSort;
  final ListingStatus? currentStatus;
  final ValueChanged<SortOption>? onSortChanged;
  final ValueChanged<ListingStatus?>? onStatusChanged;

  const CombinedFilterDropdown({
    super.key,
    required this.filterState,
    required this.onFilterChanged,
    this.currentSort,
    this.currentStatus,
    this.onSortChanged,
    this.onStatusChanged,
  });

  String _getSortLabel(SortOption sort) {
    switch (sort) {
      case SortOption.newest:
        return 'Newest First';
      case SortOption.oldest:
        return 'Oldest First';
      case SortOption.priceLowToHigh:
        return 'Price: Low to High';
      case SortOption.priceHighToLow:
        return 'Price: High to Low';
      case SortOption.discountHighToLow:
        return 'Highest Discount';
    }
  }

  void _openFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _RichFilterDialog(
        initialState: filterState,
        onApply: (newState) {
          onFilterChanged(newState);
          onSortChanged?.call(newState.sortOption);
          onStatusChanged?.call(newState.statusFilter);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeCount = filterState.activeFiltersCount;
    final hasActive = activeCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openFilterDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hasActive
                ? theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.25 : 0.4)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasActive
                  ? theme.colorScheme.primary
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              width: hasActive ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: hasActive ? theme.colorScheme.primary : (isDark ? Colors.grey[300] : Colors.grey[700]),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _getSortLabel(filterState.sortOption),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }
}

class _RichFilterDialog extends StatefulWidget {
  final BuySellFilterState initialState;
  final ValueChanged<BuySellFilterState> onApply;

  const _RichFilterDialog({
    required this.initialState,
    required this.onApply,
  });

  @override
  State<_RichFilterDialog> createState() => _RichFilterDialogState();
}

class _RichFilterDialogState extends State<_RichFilterDialog> {
  late SortOption _sortOption;
  late ListingStatus? _statusFilter;
  late DateDurationFilter _dateDuration;
  late TextEditingController _minPriceController;
  late TextEditingController _maxPriceController;

  @override
  void initState() {
    super.initState();
    _sortOption = widget.initialState.sortOption;
    _statusFilter = widget.initialState.statusFilter;
    _dateDuration = widget.initialState.dateDuration;
    _minPriceController = TextEditingController(
      text: widget.initialState.minPrice != null
          ? widget.initialState.minPrice!.toStringAsFixed(0)
          : '',
    );
    _maxPriceController = TextEditingController(
      text: widget.initialState.maxPrice != null
          ? widget.initialState.maxPrice!.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  void _resetAll() {
    setState(() {
      _sortOption = SortOption.newest;
      _statusFilter = null;
      _dateDuration = DateDurationFilter.allTime;
      _minPriceController.clear();
      _maxPriceController.clear();
    });
  }

  void _apply() {
    final minPrice = double.tryParse(_minPriceController.text.trim());
    final maxPrice = double.tryParse(_maxPriceController.text.trim());

    final newState = widget.initialState.copyWith(
      sortOption: _sortOption,
      statusFilter: _statusFilter,
      clearStatusFilter: _statusFilter == null,
      minPrice: minPrice,
      clearMinPrice: minPrice == null,
      maxPrice: maxPrice,
      clearMaxPrice: maxPrice == null,
      dateDuration: _dateDuration,
    );

    widget.onApply(newState);
    Navigator.of(context).pop();
  }

  void _setPricePreset(double? min, double? max) {
    setState(() {
      _minPriceController.text = min != null ? min.toStringAsFixed(0) : '';
      _maxPriceController.text = max != null ? max.toStringAsFixed(0) : '';
    });
  }

  bool _isPresetSelected(double? min, double? max) {
    final curMin = double.tryParse(_minPriceController.text.trim());
    final curMax = double.tryParse(_maxPriceController.text.trim());
    return curMin == min && curMax == max;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: screenHeight * 0.85),
        child: Column(
          children: [
            // Title & Reset Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: Colors.indigo, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter & Sort Listings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _resetAll,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset All', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Sort By
                    _buildSectionHeader('SORT BY', Icons.sort_rounded),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChoiceChip(
                          label: 'Newest First',
                          selected: _sortOption == SortOption.newest,
                          onSelected: () => setState(() => _sortOption = SortOption.newest),
                        ),
                        _buildChoiceChip(
                          label: 'Price: Low to High',
                          selected: _sortOption == SortOption.priceLowToHigh,
                          onSelected: () => setState(() => _sortOption = SortOption.priceLowToHigh),
                        ),
                        _buildChoiceChip(
                          label: 'Price: High to Low',
                          selected: _sortOption == SortOption.priceHighToLow,
                          onSelected: () => setState(() => _sortOption = SortOption.priceHighToLow),
                        ),
                        _buildChoiceChip(
                          label: 'Highest Discount',
                          selected: _sortOption == SortOption.discountHighToLow,
                          onSelected: () => setState(() => _sortOption = SortOption.discountHighToLow),
                        ),
                        _buildChoiceChip(
                          label: 'Oldest First',
                          selected: _sortOption == SortOption.oldest,
                          onSelected: () => setState(() => _sortOption = SortOption.oldest),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Section 2: Availability / Status
                    _buildSectionHeader('STATUS', Icons.check_circle_outline_rounded),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChoiceChip(
                          label: 'All Statuses',
                          selected: _statusFilter == null,
                          onSelected: () => setState(() => _statusFilter = null),
                        ),
                        _buildChoiceChip(
                          label: 'Available Only',
                          selected: _statusFilter == ListingStatus.available,
                          onSelected: () => setState(() => _statusFilter = ListingStatus.available),
                        ),
                        _buildChoiceChip(
                          label: 'Reserved Only',
                          selected: _statusFilter == ListingStatus.reserved,
                          onSelected: () => setState(() => _statusFilter = ListingStatus.reserved),
                        ),
                        _buildChoiceChip(
                          label: 'Sold only',
                          selected: _statusFilter == ListingStatus.sold,
                          onSelected: () => setState(() => _statusFilter = ListingStatus.sold),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Section 3: Price Range Selector
                    _buildSectionHeader('PRICE RANGE', Icons.currency_rupee_rounded),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChoiceChip(
                          label: 'Any Price',
                          selected: _isPresetSelected(null, null),
                          onSelected: () => _setPricePreset(null, null),
                        ),
                        _buildChoiceChip(
                          label: 'Under ₹500',
                          selected: _isPresetSelected(null, 500),
                          onSelected: () => _setPricePreset(null, 500),
                        ),
                        _buildChoiceChip(
                          label: '₹500 – ₹2,000',
                          selected: _isPresetSelected(500, 2000),
                          onSelected: () => _setPricePreset(500, 2000),
                        ),
                        _buildChoiceChip(
                          label: '₹2,000 – ₹5,000',
                          selected: _isPresetSelected(2000, 5000),
                          onSelected: () => _setPricePreset(2000, 5000),
                        ),
                        _buildChoiceChip(
                          label: 'Above ₹5,000',
                          selected: _isPresetSelected(5000, null),
                          onSelected: () => _setPricePreset(5000, null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minPriceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Min Price (₹)',
                              prefixText: '₹ ',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('to', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _maxPriceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Max Price (₹)',
                              prefixText: '₹ ',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Section 4: Quick Date Duration Selector
                    _buildSectionHeader('POSTED WITHIN', Icons.calendar_today_rounded),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DateDurationFilter.values.map((duration) {
                        return _buildChoiceChip(
                          label: duration.label,
                          selected: _dateDuration == duration,
                          onSelected: () => setState(() => _dateDuration = duration),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            // Apply / Cancel Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Apply Filters'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.indigo),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? Colors.white : null,
      ),
      selectedColor: Colors.indigo,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      visualDensity: VisualDensity.compact,
    );
  }
}
