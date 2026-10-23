import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/widgets/compact_date_range_picker_dialog.dart';
import '../../providers/lost_found_providers.dart';

class LostFoundFilterBar extends ConsumerWidget {
  const LostFoundFilterBar({super.key});

  static const categories = [
    'All',
    'ID Cards',
    'Electronics',
    'Personal Belongings',
    'Keys',
    'Documents',
    'Other'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(lostFoundFilterProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 750;

    final sortBtn = _buildSortButton(context, ref, filter, isDark);
    final dateBtn = _buildDateButton(context, ref, filter, isDark);
    final hasActiveFilter = filter.dateRange != null ||
        filter.category != 'All' ||
        filter.query.isNotEmpty ||
        filter.sortOption != SortOption.newest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      color: theme.cardColor,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategoryChips(context, ref, filter),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: sortBtn),
                    const SizedBox(width: 8),
                    Expanded(child: dateBtn),
                    if (hasActiveFilter) ...[
                      const SizedBox(width: 6),
                      _buildClearButton(ref),
                    ],
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: _buildCategoryChips(context, ref, filter)),
                const SizedBox(width: 12),
                sortBtn,
                const SizedBox(width: 8),
                dateBtn,
                if (hasActiveFilter) ...[
                  const SizedBox(width: 6),
                  _buildClearButton(ref),
                ],
              ],
            ),
    );
  }

  Widget _buildCategoryChips(
    BuildContext context,
    WidgetRef ref,
    LostFoundFilterState filter,
  ) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = filter.category == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: FilterChip(
              label: Text(cat),
              selected: isSelected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              selectedColor: theme.colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : null,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (selected) {
                ref.read(lostFoundFilterProvider.notifier).update(
                      (state) => state.copyWith(category: selected ? cat : 'All'),
                    );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSortButton(
    BuildContext context,
    WidgetRef ref,
    LostFoundFilterState filter,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final label = filter.sortOption == SortOption.newest ? 'Newest First' : 'Oldest First';

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: PopupMenuButton<SortOption>(
        tooltip: 'Sort reports',
        offset: const Offset(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 6,
        onSelected: (sort) {
          ref.read(lostFoundFilterProvider.notifier).update(
                (state) => state.copyWith(sortOption: sort),
              );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sort_rounded, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey[600]),
          ],
        ),
        itemBuilder: (context) => [
          _buildSortMenuItem(context, SortOption.newest, 'Newest First', filter.sortOption),
          _buildSortMenuItem(context, SortOption.oldest, 'Oldest First', filter.sortOption),
        ],
      ),
    );
  }

  PopupMenuItem<SortOption> _buildSortMenuItem(
    BuildContext context,
    SortOption option,
    String text,
    SortOption currentSort,
  ) {
    final isSelected = option == currentSort;
    final theme = Theme.of(context);

    return PopupMenuItem<SortOption>(
      value: option,
      height: 36,
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 16,
            color: isSelected ? theme.colorScheme.primary : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildDateButton(
    BuildContext context,
    WidgetRef ref,
    LostFoundFilterState filter,
    bool isDark,
  ) {
    final hasDate = filter.dateRange != null;
    final theme = Theme.of(context);
    final label = hasDate
        ? '${filter.dateRange!.start.day}/${filter.dateRange!.start.month} - ${filter.dateRange!.end.day}/${filter.dateRange!.end.month}'
        : 'Date & Time';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final result = await showDialog(
          context: context,
          builder: (ctx) => CompactDateRangePickerDialog(
            initialDateRange: filter.dateRange,
          ),
        );
        if (result == 'CLEAR') {
          ref.read(lostFoundFilterProvider.notifier).update(
                (state) => state.copyWith(clearDateRange: true),
              );
        } else if (result is DateTimeRange) {
          ref.read(lostFoundFilterProvider.notifier).update(
                (state) => state.copyWith(dateRange: result),
              );
        }
      },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: hasDate
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasDate
                ? theme.colorScheme.primary
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 16,
              color: hasDate ? theme.colorScheme.primary : Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: hasDate ? FontWeight.bold : FontWeight.w600,
                    color: hasDate
                        ? theme.colorScheme.primary
                        : (isDark ? Colors.white : const Color(0xFF1E293B)),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearButton(WidgetRef ref) {
    return Tooltip(
      message: 'Clear All Filters',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          ref.read(lostFoundFilterProvider.notifier).state = LostFoundFilterState();
        },
        child: Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.filter_alt_off_rounded, size: 16, color: Colors.red),
        ),
      ),
    );
  }
}
