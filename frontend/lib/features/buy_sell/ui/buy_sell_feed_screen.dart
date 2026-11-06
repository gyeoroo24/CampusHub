import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/enums/view_mode.dart';
import '../../../core/utils/category_emoji_helper.dart';
import '../../../core/widgets/compact_price_range_picker_dialog.dart';
import '../../../core/widgets/filter_sheet.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../../alerts/domain/alerts_models.dart';
import '../../alerts/ui/save_search_dialog.dart';
import '../../auth/ui/auth_dialog.dart';
import '../../wanted/ui/create_wanted_dialog.dart';
import '../../wanted/ui/wanted_feed_sliver.dart';
import '../domain/buy_sell_item.dart';
import '../providers/buy_sell_providers.dart';
import 'widgets/buy_sell_grid_card.dart';
import 'widgets/buy_sell_list_card.dart';
import 'widgets/create_listing_dialog.dart';
import 'widgets/listing_bookmarks.dart';

class BuySellFeedScreen extends ConsumerStatefulWidget {
  const BuySellFeedScreen({super.key});

  @override
  ConsumerState<BuySellFeedScreen> createState() => _BuySellFeedScreenState();
}

class _BuySellFeedScreenState extends ConsumerState<BuySellFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  static const _presetCategoryOrder = [
    'Books',
    'Cycles',
    'Electronics',
    'Furniture',
    'Lab Equipment',
    'Others',
  ];

  static const _pricePresets = <({String label, double? min, double? max})>[
    (label: 'Any price', min: null, max: null),
    (label: 'Under ₹500', min: null, max: 500.0),
    (label: '₹500 – ₹2,000', min: 500.0, max: 2000.0),
    (label: '₹2,000 – ₹5,000', min: 2000.0, max: 5000.0),
    (label: '₹5,000+', min: 5000.0, max: null),
  ];

  static const _statusOptions = [
    (value: ListingStatus.available, label: 'Available', icon: null),
    (value: ListingStatus.reserved, label: 'Reserved', icon: null),
    (value: ListingStatus.sold, label: 'Sold', icon: null),
  ];

  static const _sortOptions = [
    (value: SortOption.newest, label: 'Newest first', icon: null),
    (value: SortOption.priceLowToHigh, label: 'Price: low to high', icon: null),
    (value: SortOption.priceHighToLow, label: 'Price: high to low', icon: null),
  ];

  static String _rupees(double v) {
    final whole = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    return '₹$b';
  }

  static String _priceLabel(double? min, double? max) {
    final preset = _pricePresets.where((p) => p.min == min && p.max == max).firstOrNull;
    if (preset != null) return preset.label;
    if (min != null && max != null) return '${_rupees(min)} – ${_rupees(max)}';
    return min != null ? '${_rupees(min)}+' : 'Under ${_rupees(max!)}';
  }

  /// The filters that differ from a fresh feed, as chips: what to show and how to undo each one.
  /// Wanted posts only filter by category.
  static List<({String label, BuySellFilterState Function(BuySellFilterState) remove})> _activeFilters(
    BuySellFilterState f,
    List<({String name, String? icon})> categories,
    bool wanted,
  ) {
    final icon = categories.where((c) => c.name.toLowerCase() == f.category.toLowerCase()).firstOrNull?.icon;
    final statuses = _statusOptions.where((o) => f.selectedStatuses.contains(o.value)).map((o) => o.label);
    return [
      if (f.category != 'All') (label: '${icon ?? ''} ${f.category}'.trim(), remove: (s) => s.copyWith(category: 'All')),
      if (!wanted && (f.minPrice != null || f.maxPrice != null))
        (label: _priceLabel(f.minPrice, f.maxPrice), remove: (s) => s.copyWith(clearMinPrice: true, clearMaxPrice: true)),
      if (!wanted && !setEquals(f.selectedStatuses, BuySellFilterState.defaultStatuses))
        (label: 'Status: ${statuses.join(', ')}', remove: (s) => s.copyWith(clearStatusFilter: true)),
      if (!wanted && f.sortOption != SortOption.newest)
        (
          label: _sortOptions.where((o) => o.value == f.sortOption).firstOrNull?.label ?? 'Sorted',
          remove: (s) => s.copyWith(sortOption: SortOption.newest),
        ),
    ];
  }

  void _openFilters(
    BuildContext context,
    WidgetRef ref,
    BuySellFilterState filter,
    List<({String name, String? icon})> categories,
    bool wanted,
  ) {
    showFilterSheet<BuySellFilterState>(
      context,
      title: wanted ? 'Filter wanted posts' : 'Filter listings',
      initial: filter,
      defaults: BuySellFilterState(query: filter.query, viewMode: filter.viewMode),
      onApply: (next) => ref.read(buySellFilterProvider.notifier).state = next,
      sections: (context, draft, update) => [
        FilterSection(
          title: 'Category',
          child: FilterChoices<String>(
            options: [for (final c in categories) (value: c.name, label: c.name, icon: c.icon)],
            selected: {draft.category},
            onTap: (c) => update(draft.copyWith(category: c)),
          ),
        ),
        if (!wanted) ...[
          FilterSection(
            title: 'Price',
            trailing: TextButton(
              onPressed: () async {
                final result = await showDialog(
                  context: context,
                  builder: (_) => CompactPriceRangePickerDialog(initialMin: draft.minPrice, initialMax: draft.maxPrice),
                );
                if (result == 'CLEAR') {
                  update(draft.copyWith(clearMinPrice: true, clearMaxPrice: true));
                } else if (result is ({double? min, double? max})) {
                  update(draft.copyWith(
                    minPrice: result.min,
                    clearMinPrice: result.min == null,
                    maxPrice: result.max,
                    clearMaxPrice: result.max == null,
                  ));
                }
              },
              child: const Text('Custom range…'),
            ),
            child: FilterChoices<String>(
              options: [
                for (final p in _pricePresets) (value: p.label, label: p.label, icon: null),
                // A custom range shows up as its own selected chip.
                if (!_pricePresets.any((p) => p.min == draft.minPrice && p.max == draft.maxPrice))
                  (value: 'custom', label: _priceLabel(draft.minPrice, draft.maxPrice), icon: null),
              ],
              selected: {
                _pricePresets.where((p) => p.min == draft.minPrice && p.max == draft.maxPrice).firstOrNull?.label ??
                    'custom',
              },
              onTap: (label) {
                final p = _pricePresets.where((p) => p.label == label).firstOrNull;
                if (p == null) return;
                update(draft.copyWith(
                  minPrice: p.min,
                  clearMinPrice: p.min == null,
                  maxPrice: p.max,
                  clearMaxPrice: p.max == null,
                ));
              },
            ),
          ),
          FilterSection(
            title: 'Status',
            child: FilterChoices<ListingStatus>(
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
      ],
    );
  }

  // Captured in initState: `ref` itself is unusable by the time dispose() runs (Riverpod
  // tears it down before calling the widget's dispose), but a notifier obtained earlier is
  // still a plain object we can call into.
  late final StateController<BuySellFilterState> _filterNotifier;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _filterNotifier = ref.read(buySellFilterProvider.notifier);
    // The feed outlives this screen, so pick up changes made while it was away (e.g. a listing reserved by
    // accepting an offer in Messages).
    Future.microtask(() {
      if (mounted) ref.read(buySellPaginationProvider.notifier).refreshQuietly();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // Filters are scoped to a visit of this tab, not the whole session — reset them
    // on the way out so switching tabs and back starts from a clean feed. Riverpod forbids
    // writing a provider while the widget tree is being torn down, so this runs right after it (a
    // microtask, not a timer). If the whole app went away meanwhile (sign-out, tests), there's
    // nothing left to reset.
    Future.microtask(() {
      if (_filterNotifier.mounted) _filterNotifier.state = BuySellFilterState();
    });
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (currentScroll >= maxScroll - 250) {
        ref.read(buySellPaginationProvider.notifier).loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paginatedState = ref.watch(buySellPaginationProvider);
    final filter = ref.watch(buySellFilterProvider);
    final section = ref.watch(buySellSectionProvider);
    final isWanted = section == BuySellSection.wanted;
    final bookmarkCount = ref.watch(listingBookmarksProvider).length;
    final showTrustedExchangeBanner = ref.watch(showTrustedExchangeBannerProvider);
    final categoriesAsync = ref.watch(buySellCategoriesProvider);
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

    final activeFilters = _activeFilters(filter, categoryPills, isWanted);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 750;

    return Scaffold(
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: () =>
                  isWanted ? CreateWantedDialog.show(context, ref) : _handleCreateListing(context, ref),
              icon: Icon(isWanted ? Icons.volunteer_activism_outlined : Icons.add_shopping_cart_rounded),
              label: Text(isWanted ? 'Post Wanted' : 'Sell Item', style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Trusted Campus Exchange Banner (Only for manually logged-in users, dismissible via 'x') ──
          if (showTrustedExchangeBanner)
            SliverToBoxAdapter(
              child: Container(
                margin: EdgeInsets.fromLTRB(16, isMobile ? 8 : 12, 16, 4),
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 18,
                  vertical: isMobile ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFEFF6FF), const Color(0xFFF8FAFC)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFDBEAFE),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.security_rounded, color: theme.colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trusted Campus Exchange',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Every listing is posted by an IISc student authenticated via their IISc email address. Contact the seller to setup a time and place for hassle-free physical handovers.',
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                          ),
                          if (isMobile) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildFeaturePill(context, '🛡️ IISc Email'),
                                _buildFeaturePill(context, '🤝 Face-to-Face'),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildFeaturePill(context, '🛡️ IISc Email'),
                          _buildFeaturePill(context, '🤝 Face-to-Face'),
                        ],
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Dismiss',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(Icons.close_rounded, color: theme.hintColor),
                      onPressed: () {
                        ref.read(showTrustedExchangeBannerProvider.notifier).state = false;
                      },
                    ),
                  ],
                ),
              ),
            ),

          // ── Toolbar: For sale | Wanted, Filters, save search, view, Sell ──
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(
                  bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // On a phone the section toggle and Filters scroll sideways rather than overflow.
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const BuySellSectionToggle(),
                              const SizedBox(width: 10),
                              FiltersButton(
                                compact: isMobile,
                                activeCount: activeFilters.length,
                                onPressed: () => _openFilters(context, ref, filter, categoryPills, isWanted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!isWanted) ...[
                        IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Bookmarks',
                          icon: Badge(
                            isLabelVisible: bookmarkCount > 0,
                            label: Text('$bookmarkCount'),
                            child: const Icon(Icons.bookmarks_outlined),
                          ),
                          onPressed: () => showDialog(context: context, builder: (_) => const BookmarkedListingsDialog()),
                        ),
                        IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Save this search & get alerts',
                          icon: const Icon(Icons.notification_add_outlined),
                          onPressed: () => _handleSaveSearch(context, ref, filter),
                        ),
                        IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: filter.viewMode == ViewMode.grid ? 'Compact view' : 'Large view',
                          icon: Icon(
                            filter.viewMode == ViewMode.grid ? Icons.density_medium_rounded : Icons.view_agenda_outlined,
                          ),
                          onPressed: () => ref.read(buySellFilterProvider.notifier).update(
                                (s) => s.copyWith(
                                  viewMode: filter.viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid,
                                ),
                              ),
                        ),
                      ],
                      if (!isMobile) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () =>
                              isWanted ? CreateWantedDialog.show(context, ref) : _handleCreateListing(context, ref),
                          icon: Icon(
                            isWanted ? Icons.volunteer_activism_outlined : Icons.add_shopping_cart_rounded,
                            size: 18,
                          ),
                          label: Text(
                            isWanted ? 'Post Wanted' : 'Sell Item',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // What's filtered, each removable on its own.
                  if (activeFilters.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in activeFilters)
                            ActiveFilterChip(
                              label: f.label,
                              onRemove: () => ref.read(buySellFilterProvider.notifier).update(f.remove),
                            ),
                          if (activeFilters.length > 1)
                            TextButton(
                              onPressed: () => ref.read(buySellFilterProvider.notifier).update(
                                    (s) => BuySellFilterState(query: s.query, viewMode: s.viewMode),
                                  ),
                              child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Wanted posts replace the listings when the switch is on "Wanted" ──
          if (isWanted)
            const WantedFeedSliver()
          else ...[
          // ── Feed Body: Skeletons or Cards with Infinite Scroll ─────────────
          if (paginatedState.isLoadingInitial)
            SliverToBoxAdapter(
              child: filter.viewMode == ViewMode.list
                  ? const SkeletonList(itemCount: 6)
                  : const SkeletonGrid(itemCount: 8),
            )
          else if (paginatedState.items.isEmpty && paginatedState.errorMessage != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                message: paginatedState.errorMessage!,
                onRetry: () => ref.read(buySellPaginationProvider.notifier).loadInitial(),
              ),
            )
          else if (paginatedState.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, size: 54, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'No listings found matching your criteria.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () {
                        ref.read(buySellFilterProvider.notifier).state = BuySellFilterState();
                      },
                      child: const Text('Reset all filters'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Render Cards based on view mode
            if (filter.viewMode == ViewMode.list)
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = paginatedState.items[index];
                      return BuySellListCard(
                        item: item,
                        onStatusChange: (status) async {
                          await ref.read(buySellRepositoryProvider).updateStatus(item.id, status);
                          ref.read(buySellPaginationProvider.notifier).updateItemStatusLocally(item.id, status);
                        },
                      );
                    },
                    childCount: paginatedState.items.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final count = width > 1200 ? 4 : width > 800 ? 3 : width > 500 ? 2 : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        childAspectRatio: count == 1 ? 0.95 : 0.85,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = paginatedState.items[index];
                          return BuySellGridCard(
                            item: item,
                            onStatusChange: (status) async {
                              await ref.read(buySellRepositoryProvider).updateStatus(item.id, status);
                              ref.read(buySellPaginationProvider.notifier).updateItemStatusLocally(item.id, status);
                            },
                          );
                        },
                        childCount: paginatedState.items.length,
                      ),
                    );
                  },
                ),
              ),

            // ── Infinite Scroll Loading Bottom Indicator / Caught Up Footer ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: paginatedState.isLoadingMore
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Loading more listings...',
                              style: TextStyle(fontSize: 12, color: theme.hintColor),
                            ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.done_all_rounded, size: 14, color: Colors.teal.shade700),
                              const SizedBox(width: 6),
                              Text(
                                "You're all caught up! Showing all ${paginatedState.items.length} items",
                                style: TextStyle(fontSize: 11, color: theme.hintColor, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
          ],
        ],
      ),
    );
  }

  static Future<void> _handleSaveSearch(BuildContext context, WidgetRef ref, BuySellFilterState filter) async {
    final categories = ref.read(buySellCategoriesProvider).valueOrNull ?? const [];
    final picked = filter.category == 'All'
        ? null
        : categories.where((c) => c.name.toLowerCase() == filter.category.toLowerCase()).firstOrNull;
    await SaveSearchDialog.show(
      context,
      ref,
      module: SavedSearchModule.buySell,
      query: filter.query,
      categoryId: picked?.id,
      categoryName: picked?.name,
      minPrice: filter.minPrice,
      maxPrice: filter.maxPrice,
      unsavedCategoryName: filter.category != 'All' && picked == null ? filter.category : null,
    );
  }

  static Future<void> _handleCreateListing(BuildContext context, WidgetRef ref) async {
    final signedIn = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: 'Sign In to Post Listing',
      message: 'Only authenticated IISc students can post items for sale.',
    );
    if (!signedIn || !context.mounted) return;

    final user = ref.read(currentUserProvider);
    showDialog(
      context: context,
      builder: (ctx) => CreateListingDialog(
        userEmail: user?.email,
        userId: user?.id,
        onSubmit: (newItem) async {
          await ref.read(buySellRepositoryProvider).addListing(newItem);
          ref.invalidate(buySellCategoriesProvider);
          ref.read(buySellPaginationProvider.notifier).loadInitial();
        },
      ),
    );
  }

  static Widget _buildFeaturePill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
