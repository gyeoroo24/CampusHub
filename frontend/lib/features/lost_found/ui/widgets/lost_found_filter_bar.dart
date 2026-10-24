import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/date_preset.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/enums/view_mode.dart';
import '../../../../core/utils/category_emoji_helper.dart';
import '../../../../core/widgets/compact_date_range_picker_dialog.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'report_item_dialog.dart';

class LostFoundFilterBar extends ConsumerWidget {
  const LostFoundFilterBar({super.key});

  static const _presetCategoryOrder = [
    'ID Cards',
    'Electronics',
    'Personal Belongings',
    'Bags',
    'Keys',
    'Others',
  ];

  static Future<void> handleReport(BuildContext context, WidgetRef ref, PostType postType) async {
    final signedIn = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: postType == PostType.lost
          ? 'Sign In to Report Lost Item'
          : 'Sign In to Report Found Item',
      message: 'Only authenticated IISc students can post lost and found reports.',
    );
    if (!signedIn || !context.mounted) return;

    final user = ref.read(currentUserProvider);
    showDialog(
      context: context,
      builder: (ctx) => ReportItemDialog(
        parentContext: context,
        postType: postType,
        userEmail: user?.email,
        userId: user?.id,
        userName: user?.name,
        onSubmit: (report) async {
          final created = await ref.read(lostFoundRepositoryProvider).submitReport(report);
          ref.invalidate(lostFoundCategoriesProvider);
          if (postType == PostType.lost) {
            ref.read(lostReportsPaginationProvider.notifier).loadInitial();
          } else {
            ref.read(foundReportsPaginationProvider.notifier).loadInitial();
          }
          return created;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(lostFoundFilterProvider);
    final categoriesAsync = ref.watch(lostFoundCategoriesProvider);
    final categoryPills = <({String name, String? icon})>[
      (name: 'All', icon: CategoryEmojiHelper.getEmoji('All')),
    ];
    for (final p in _presetCategoryOrder) {
      categoryPills.add((name: p, icon: CategoryEmojiHelper.getEmoji(p)));
    }
    final remoteCats = categoriesAsync.maybeWhen(
      data: (cats) => cats.map((c) => c.name.trim()).toList(),
      orElse: () => <String>[],
    );
    final userAdded = remoteCats.where((name) {
      final clean = CategoryEmojiHelper.cleanName(name).toLowerCase();
      if (clean == 'all') return false;
      return !_presetCategoryOrder.any((p) => p.toLowerCase() == clean);
    }).toList();
    for (final customName in userAdded) {
      final clean = CategoryEmojiHelper.cleanName(customName);
      final emoji = CategoryEmojiHelper.getEmoji(customName);
      categoryPills.add((name: clean, icon: emoji));
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width <= 750;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Category Pills (Horizontal Scroll with Icons) & Report Buttons ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.cardColor,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categoryPills.map((pill) {
                      final isSelected = filter.category == pill.name;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          avatar: pill.icon != null
                              ? Text(pill.icon!, style: const TextStyle(fontSize: 13))
                              : null,
                          label: Text(pill.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              ref.read(lostFoundFilterProvider.notifier).update(
                                    (s) => s.copyWith(category: pill.name),
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
              ),
              if (!isMobile) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFBE185D), // Deep Rose/Pink
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => handleReport(context, ref, PostType.lost),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text(
                    'Report Lost',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E), // Deep Teal
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => handleReport(context, ref, PostType.found),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text(
                    'Report Found',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
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
              // Quick Filter Chips: All | Date Presets + Custom | Status Chips
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // "All" Chip
                      Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: FilterChip(
                          label: const Text('All', style: TextStyle(fontSize: 11)),
                          selected: filter.isAllSelected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onSelected: (_) {
                            ref.read(lostFoundFilterProvider.notifier).update(
                                  (s) => s.copyWith(
                                    datePreset: DatePresetFilter.all,
                                    clearCustomDateRange: true,
                                    selectedStatuses: {
                                      ReportStatus.open,
                                      ReportStatus.matched,
                                      ReportStatus.closed,
                                    },
                                  ),
                                );
                          },
                        ),
                      ),

                      // Vertical Divider
                      Container(
                        height: 18,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                      const SizedBox(width: 4),

                      // Date Presets
                      ...[
                        DatePresetFilter.today,
                        DatePresetFilter.yesterday,
                        DatePresetFilter.last3Days,
                        DatePresetFilter.thisWeek,
                        DatePresetFilter.thisMonth,
                      ].map((preset) {
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
                              if (isSelected) {
                                ref.read(lostFoundFilterProvider.notifier).update(
                                      (s) => s.copyWith(
                                        datePreset: DatePresetFilter.all,
                                        clearCustomDateRange: true,
                                      ),
                                    );
                              } else {
                                ref.read(lostFoundFilterProvider.notifier).update(
                                      (s) => s.copyWith(
                                        datePreset: preset,
                                        clearCustomDateRange: true,
                                      ),
                                    );
                              }
                            },
                          ),
                        );
                      }),

                      // Custom Date Range Chip (if active)
                      if (filter.customDateRange != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: FilterChip(
                            label: Text(
                              '${filter.customDateRange!.start.day}/${filter.customDateRange!.start.month} - ${filter.customDateRange!.end.day}/${filter.customDateRange!.end.month}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: true,
                            showCheckmark: false,
                            avatar: const Icon(Icons.close_rounded, size: 14),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onSelected: (_) {
                              ref.read(lostFoundFilterProvider.notifier).update(
                                    (s) => s.copyWith(clearCustomDateRange: true),
                                  );
                            },
                          ),
                        ),

                      // Vertical Divider
                      Container(
                        height: 18,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                      const SizedBox(width: 4),

                      // Status Filter Chips (Toggles: Open, Matched, Resolved)
                      ...[
                        (label: 'Open', status: ReportStatus.open),
                        (label: 'Matched', status: ReportStatus.matched),
                        (label: 'Resolved', status: ReportStatus.closed),
                      ].map((st) {
                        final isSelected = filter.selectedStatuses.contains(st.status);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: FilterChip(
                            label: Text(st.label, style: const TextStyle(fontSize: 11)),
                            selected: isSelected,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onSelected: (_) {
                              final updated = Set<ReportStatus>.from(filter.selectedStatuses);
                              if (isSelected) {
                                updated.remove(st.status);
                                if (updated.isEmpty) {
                                  updated.add(ReportStatus.open);
                                }
                              } else {
                                updated.add(st.status);
                              }
                              ref.read(lostFoundFilterProvider.notifier).update(
                                    (s) => s.copyWith(selectedStatuses: updated),
                                  );
                            },
                          ),
                        );
                      }),
                    ],
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

              // View Mode Toggle (Large vs Compact)
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: filter.viewMode == ViewMode.grid ? 'Compact view' : 'Large view',
                icon: Icon(
                  filter.viewMode == ViewMode.grid
                      ? Icons.density_medium_rounded
                      : Icons.view_agenda_outlined,
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
