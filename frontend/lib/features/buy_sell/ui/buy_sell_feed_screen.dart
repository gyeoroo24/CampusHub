import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/enums/sort_option.dart';
import '../../../core/enums/view_mode.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../providers/buy_sell_providers.dart';
import 'widgets/buy_sell_grid_card.dart';
import 'widgets/buy_sell_list_card.dart';
import 'widgets/create_listing_dialog.dart';

class BuySellFeedScreen extends ConsumerStatefulWidget {
  const BuySellFeedScreen({super.key});

  @override
  ConsumerState<BuySellFeedScreen> createState() => _BuySellFeedScreenState();
}

class _BuySellFeedScreenState extends ConsumerState<BuySellFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  static const _categoryIcons = {
    'All': '🌟',
    'Books': '📚',
    'Cycles': '🚲',
    'Electronics': '💻',
    'Furniture': '🛋️',
    'Lab Equipment': '🔬',
    'Others': '🎒',
  };

  static const _priceFilters = [
    (label: 'All Prices', min: null, max: null),
    (label: 'Under ₹500', min: null, max: 500.0),
    (label: '₹500 - ₹2,000', min: 500.0, max: 2000.0),
    (label: '₹2,000+', min: 2000.0, max: null),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 750;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Amazon-Inspired Spotlight Banner (collapsible/subtle) ───────────
          if (!isMobile)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.verified_rounded, color: theme.colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trusted Campus Exchange',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            'Every listing is posted by an IISc student verified via their IISc email address. Contact the seller to setup a time and place for hassle-free physical handovers.',
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildFeaturePill(context, '🛡️ Verified Email'),
                        _buildFeaturePill(context, '🤝 Face-to-Face'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── Category Pills (Horizontal Scroll with Icons) ───────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.cardColor,
              child: Row(
                mainAxisAlignment: .spaceBetween, 
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
                                ref.read(buySellFilterProvider.notifier).update(
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
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 18,
                        vertical: isMobile ? 8 : 12,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final signedIn = await AuthDialog.ensureSignedIn(
                        context,
                        ref,
                        title: 'Sign In to Post Listing',
                        message: 'Only verified IISc students can post items for sale.',
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
                            ref.read(buySellPaginationProvider.notifier).loadInitial();
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: Text(
                      isMobile ? 'Sell' : 'Sell Item',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Quick Filter Toolbar (Sort, Price chips, View mode) ─────────────
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Price Filter Chips (Single selection)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _priceFilters.map((p) {
                          final isSelected = filter.minPrice == p.min && filter.maxPrice == p.max;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: FilterChip(
                              label: Text(p.label, style: const TextStyle(fontSize: 11)),
                              selected: isSelected,
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              onSelected: (_) {
                                ref.read(buySellFilterProvider.notifier).update(
                                      (s) => s.copyWith(
                                        minPrice: p.min,
                                        clearMinPrice: p.min == null,
                                        maxPrice: p.max,
                                        clearMaxPrice: p.max == null,
                                      ),
                                    );
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Sort Dropdown
                  PopupMenuButton<SortOption>(
                    tooltip: 'Sort Listings',
                    initialValue: filter.sortOption,
                    onSelected: (option) {
                      ref.read(buySellFilterProvider.notifier).update(
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
                            _sortLabel(filter.sortOption),
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
                        value: SortOption.priceLowToHigh,
                        child: Text('Price: Low to High', style: TextStyle(fontSize: 12)),
                      ),
                      const PopupMenuItem(
                        value: SortOption.priceHighToLow,
                        child: Text('Price: High to Low', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),

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
                      ref.read(buySellFilterProvider.notifier).update(
                            (s) => s.copyWith(
                              viewMode: filter.viewMode == ViewMode.grid
                                  ? ViewMode.list
                                  : ViewMode.grid,
                            ),
                          );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Feed Body: Skeletons or Cards with Infinite Scroll ─────────────
          if (paginatedState.isLoadingInitial)
            SliverToBoxAdapter(
              child: filter.viewMode == ViewMode.list
                  ? const SkeletonList(itemCount: 6)
                  : const SkeletonGrid(itemCount: 8),
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
                    final count = width > 1200
                        ? 4
                        : width > 800
                            ? 3
                            : width > 500
                                ? 2
                                : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        childAspectRatio: count == 1 ? 1.05 : 0.72,
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
                              Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.teal.shade700),
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

  static String _sortLabel(SortOption option) {
    switch (option) {
      case SortOption.priceLowToHigh:
        return 'Price: Low';
      case SortOption.priceHighToLow:
        return 'Price: High';
      case SortOption.newest:
      default:
        return 'Newest';
    }
  }
}
