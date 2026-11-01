import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/date_preset.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/enums/view_mode.dart';
import '../../../../core/utils/category_emoji_helper.dart';
import '../../../../core/widgets/compact_date_range_picker_dialog.dart';
import '../../../../core/widgets/filter_sheet.dart';
import '../../../alerts/domain/alerts_models.dart';
import '../../../alerts/ui/save_search_dialog.dart';
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
    final active = _activeFilters(filter, categoryPills);
    final notifier = ref.read(lostFoundFilterProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FiltersButton(
                activeCount: active.length,
                onPressed: () => _openFilters(context, ref, filter, categoryPills),
              ),
              const Spacer(),
              // Save this search: alerts when a matching item is found
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Alert me when a matching item is found',
                icon: const Icon(Icons.notification_add_outlined),
                onPressed: () {
                  final categories = categoriesAsync.valueOrNull ?? const [];
                  final picked = filter.category == 'All'
                      ? null
                      : categories.where((c) => c.name.toLowerCase() == filter.category.toLowerCase()).firstOrNull;
                  SaveSearchDialog.show(
                    context,
                    ref,
                    module: SavedSearchModule.lostFound,
                    query: filter.query,
                    categoryId: picked?.id,
                    categoryName: picked?.name,
                    unsavedCategoryName: filter.category != 'All' && picked == null ? filter.category : null,
                  );
                },
              ),
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: filter.viewMode == ViewMode.grid ? 'Compact view' : 'Large view',
                icon: Icon(filter.viewMode == ViewMode.grid ? Icons.density_medium_rounded : Icons.view_agenda_outlined),
                onPressed: () => notifier.update(
                  (s) => s.copyWith(viewMode: filter.viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid),
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
                  label: const Text('Report Lost', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                  label: const Text('Report Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ],
          ),
          // What's filtered, each removable on its own.
          if (active.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in active) ActiveFilterChip(label: f.label, onRemove: () => notifier.update(f.remove)),
                  if (active.length > 1)
                    TextButton(
                      onPressed: () => notifier.update(_defaults),
                      child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A fresh feed, keeping the search text and the chosen layout.
  static LostFoundFilterState _defaults(LostFoundFilterState s) =>
      LostFoundFilterState(query: s.query, viewMode: s.viewMode, typeFilter: s.typeFilter);

  static const _statusOptions = [
    (value: ReportStatus.open, label: 'Open', icon: null),
    (value: ReportStatus.closed, label: 'Resolved', icon: null),
  ];

  static const _datePresets = [
    DatePresetFilter.all,
    DatePresetFilter.today,
    DatePresetFilter.yesterday,
    DatePresetFilter.last3Days,
    DatePresetFilter.thisWeek,
    DatePresetFilter.thisMonth,
  ];

  static const _sortOptions = [
    (value: SortOption.newest, label: 'Newest first', icon: null),
    (value: SortOption.oldest, label: 'Oldest first', icon: null),
  ];

  static String _range(DateTimeRange r) => '${r.start.day}/${r.start.month} – ${r.end.day}/${r.end.month}';

  static String _dateLabel(DatePresetFilter p) => p == DatePresetFilter.all ? 'Any time' : p.label;

  /// The filters that differ from a fresh feed, as chips: what to show and how to undo each one.
  static List<({String label, LostFoundFilterState Function(LostFoundFilterState) remove})> _activeFilters(
    LostFoundFilterState f,
    List<({String name, String? icon})> categories,
  ) {
    final icon = categories.where((c) => c.name.toLowerCase() == f.category.toLowerCase()).firstOrNull?.icon;
    final statuses = _statusOptions.where((o) => f.selectedStatuses.contains(o.value)).map((o) => o.label);
    return [
      if (f.category != 'All') (label: '${icon ?? ''} ${f.category}'.trim(), remove: (s) => s.copyWith(category: 'All')),
      if (f.customDateRange != null)
        (label: _range(f.customDateRange!), remove: (s) => s.copyWith(clearCustomDateRange: true))
      else if (f.datePreset != DatePresetFilter.all)
        (label: f.datePreset.label, remove: (s) => s.copyWith(datePreset: DatePresetFilter.all)),
      if (!setEquals(f.selectedStatuses, LostFoundFilterState.defaultStatuses))
        (
          label: 'Status: ${statuses.join(', ')}',
          remove: (s) => s.copyWith(selectedStatuses: LostFoundFilterState.defaultStatuses),
        ),
      if (f.sortOption != SortOption.newest)
        (label: 'Oldest first', remove: (s) => s.copyWith(sortOption: SortOption.newest)),
    ];
  }

  void _openFilters(
    BuildContext context,
    WidgetRef ref,
    LostFoundFilterState filter,
    List<({String name, String? icon})> categories,
  ) {
    showFilterSheet<LostFoundFilterState>(
      context,
      title: 'Filter Lost & Found',
      initial: filter,
      defaults: _defaults(filter),
      onApply: (next) => ref.read(lostFoundFilterProvider.notifier).state = next,
      sections: (context, draft, update) => [
        FilterSection(
          title: 'Category',
          child: FilterChoices<String>(
            options: [for (final c in categories) (value: c.name, label: c.name, icon: c.icon)],
            selected: {draft.category},
            onTap: (c) => update(draft.copyWith(category: c)),
          ),
        ),
        FilterSection(
          title: 'When',
          trailing: TextButton(
            onPressed: () async {
              final result = await showDialog(
                context: context,
                builder: (_) => CompactDateRangePickerDialog(initialDateRange: draft.customDateRange),
              );
              if (result == 'CLEAR') {
                update(draft.copyWith(clearCustomDateRange: true));
              } else if (result is DateTimeRange) {
                update(draft.copyWith(customDateRange: result));
              }
            },
            child: const Text('Custom range…'),
          ),
          child: FilterChoices<String>(
            options: [
              for (final p in _datePresets) (value: p.name, label: _dateLabel(p), icon: null),
              if (draft.customDateRange != null)
                (value: 'custom', label: _range(draft.customDateRange!), icon: null),
            ],
            selected: {draft.customDateRange != null ? 'custom' : draft.datePreset.name},
            onTap: (name) {
              if (name == 'custom') return;
              update(draft.copyWith(
                datePreset: DatePresetFilter.values.byName(name),
                clearCustomDateRange: true,
              ));
            },
          ),
        ),
        FilterSection(
          title: 'Status',
          child: FilterChoices<ReportStatus>(
            options: _statusOptions,
            selected: draft.selectedStatuses,
            onTap: (st) {
              final next = {...draft.selectedStatuses};
              if (!next.remove(st)) next.add(st);
              if (next.isNotEmpty) update(draft.copyWith(selectedStatuses: next)); // keep at least one
            },
          ),
        ),
        FilterSection(
          title: 'Sort by',
          child: FilterChoices<SortOption>(
            options: _sortOptions,
            selected: {draft.sortOption},
            onTap: (o) => update(draft.copyWith(sortOption: o)),
          ),
        ),
      ],
    );
  }
}
