import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/enums/view_mode.dart';
import '../../../core/widgets/view_mode_toggle.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../providers/buy_sell_providers.dart';
import 'widgets/buy_sell_card.dart';
import 'widgets/category_filter_bar.dart';
import 'widgets/combined_filter_dropdown.dart';
import 'widgets/create_listing_dialog.dart';

class BuySellFeedScreen extends ConsumerWidget {
  const BuySellFeedScreen({super.key});

  // Alphabetically arranged tags after 'All'
  static const categories = [
    'All',
    'Books',
    'Cycles',
    'Electronics',
    'Furniture',
    'Lab Equipment',
    'Other',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(buySellListingsProvider);
    final filter = ref.watch(buySellFilterProvider);
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMobile ? 'Buy & Sell' : 'Buy & Sell Portal',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 18 : 20,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 8.0 : 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 14,
                  vertical: isMobile ? 8 : 10,
                ),
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
                      ref.invalidate(buySellListingsProvider);
                    },
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(isMobile ? 'Sell' : 'Sell Item'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Responsive Filter, Sort and View Mode Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CategoryFilterBar(
                        categories: categories,
                        selectedCategory: filter.category,
                        onSelected: (cat) {
                          ref.read(buySellFilterProvider.notifier).update(
                                (s) => s.copyWith(category: cat),
                              );
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: CombinedFilterDropdown(
                              filterState: filter,
                              onFilterChanged: (newState) {
                                ref.read(buySellFilterProvider.notifier).state = newState;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ModernViewModeToggle(
                            currentMode: filter.viewMode,
                            onChanged: (mode) {
                              ref.read(buySellFilterProvider.notifier).update(
                                    (s) => s.copyWith(viewMode: mode),
                                  );
                            },
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: CategoryFilterBar(
                          categories: categories,
                          selectedCategory: filter.category,
                          onSelected: (cat) {
                            ref.read(buySellFilterProvider.notifier).update(
                                  (s) => s.copyWith(category: cat),
                                );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      CombinedFilterDropdown(
                        filterState: filter,
                        onFilterChanged: (newState) {
                          ref.read(buySellFilterProvider.notifier).state = newState;
                        },
                      ),
                      const SizedBox(width: 12),
                      ModernViewModeToggle(
                        currentMode: filter.viewMode,
                        onChanged: (mode) {
                          ref.read(buySellFilterProvider.notifier).update(
                                (s) => s.copyWith(viewMode: mode),
                              );
                        },
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          // Listings Content (List or Grid View)
          Expanded(
            child: listingsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No listings found matching your criteria.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                if (filter.viewMode == ViewMode.list) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) => BuySellCard(
                      item: items[index],
                      viewMode: filter.viewMode,
                      onStatusChange: (status) async {
                        await ref.read(buySellRepositoryProvider).updateStatus(items[index].id, status);
                        ref.invalidate(buySellListingsProvider);
                      },
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final count = constraints.maxWidth > 1100
                        ? 4
                        : constraints.maxWidth > 750
                            ? 3
                            : constraints.maxWidth > 500
                                ? 2
                                : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        childAspectRatio: count == 1 ? 1.15 : 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => BuySellCard(
                        item: items[index],
                        viewMode: filter.viewMode,
                        onStatusChange: (status) async {
                          await ref.read(buySellRepositoryProvider).updateStatus(items[index].id, status);
                          ref.invalidate(buySellListingsProvider);
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error loading listings: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
