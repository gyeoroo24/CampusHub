import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/date_preset.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/enums/view_mode.dart';
import '../../../../core/widgets/compact_date_range_picker_dialog.dart';
import '../../providers/lost_found_providers.dart';

class LostFoundFilterBar extends ConsumerWidget {
  const LostFoundFilterBar({super.key});

  static const Map<String, String> _categoryIcons = {
    'All': '📋',
    'ID Cards': '🪪',
    'Electronics': '💻',
    'Personal Belongings': '🎒',
    'Keys': '🔑',
    'Documents': '📄',
    'Other': '📦',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(lostFoundFilterProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Category Pills (Horizontal Scroll with Icons) ───────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.cardColor,
          child: Row(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categoryIcons.entries.map((entry) {
                    final isSelected = filter.category == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        avatar: Text(entry.value, style: const TextStyle(fontSize: 13)),
                        label: Text(entry.key),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            ref.read(lostFoundFilterProvider.notifier).update(
                                  (s) => s.copyWith(category: entry.key),
                                );
                          }
                        },
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              
            ],
          ),
        ),

        // ── Quick Filter Toolbar (Date Presets, Sort, Custom Date, View Mode) ─
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Row(
            children: [
              // Convenient Date Filter Presets
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: DatePresetFilter.values.map((preset) {
                      final isSelected = filter.customDateRange == null && filter.datePreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: FilterChip(
                          label: Text(preset.label, style: const TextStyle(fontSize: 11)),
                          selected: isSelected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onSelected: (_) {
                            ref.read(lostFoundFilterProvider.notifier).update(
                                  (s) => s.copyWith(
                                    datePreset: preset,
                                    clearCustomDateRange: true,
                                  ),
                                );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Sort Dropdown (Styled identically to Buy & Sell toolbar)
              PopupMenuButton<SortOption>(
                tooltip: 'Sort Reports',
                initialValue: filter.sortOption,
                onSelected: (option) {
                  ref.read(lostFoundFilterProvider.notifier).update(
                        (s) => s.copyWith(sortOption: option),
                      );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        filter.sortOption == SortOption.newest ? 'Newest First' : 'Oldest First',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: SortOption.newest,
                    child: Text('Newest First', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: SortOption.oldest,
                    child: Text('Oldest First', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(width: 4),

              // Custom Date Range Picker button
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: filter.customDateRange != null
                    ? 'Custom: ${filter.customDateRange!.start.day}/${filter.customDateRange!.start.month} - ${filter.customDateRange!.end.day}/${filter.customDateRange!.end.month}'
                    : 'Pick Custom Date Range',
                icon: Icon(
                  Icons.date_range_rounded,
                  color: filter.customDateRange != null ? theme.colorScheme.primary : null,
                ),
                onPressed: () async {
                  final result = await showDialog(
                    context: context,
                    builder: (ctx) => CompactDateRangePickerDialog(
                      initialDateRange: filter.customDateRange,
                    ),
                  );
                  if (result == 'CLEAR') {
                    ref.read(lostFoundFilterProvider.notifier).update(
                          (s) => s.copyWith(clearCustomDateRange: true),
                        );
                  } else if (result is DateTimeRange) {
                    ref.read(lostFoundFilterProvider.notifier).update(
                          (s) => s.copyWith(customDateRange: result),
                        );
                  }
                },
              ),
              const SizedBox(width: 4),

              // View Mode Toggle (Grid vs List)
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: filter.viewMode == ViewMode.grid ? 'List View' : 'Grid View',
                icon: Icon(
                  filter.viewMode == ViewMode.grid
                      ? Icons.view_list_rounded
                      : Icons.grid_view_rounded,
                ),
                onPressed: () {
                  ref.read(lostFoundFilterProvider.notifier).update(
                        (s) => s.copyWith(
                          viewMode: filter.viewMode == ViewMode.grid
                              ? ViewMode.list
                              : ViewMode.grid,
                        ),
                      );
                },
              ),

              // Clear All Filters Button (if active)
              if (filter.hasActiveFilters) ...[
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Reset all filters',
                  icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.red),
                  onPressed: () {
                    ref.read(lostFoundFilterProvider.notifier).state = LostFoundFilterState(
                      viewMode: filter.viewMode,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
