import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/error_text.dart';
import '../../buy_sell/domain/buy_sell_item.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../lost_found/domain/lost_found_item.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../domain/alerts_models.dart';
import '../providers/alerts_providers.dart';

/// My saved searches: open the results, pause alerts, or delete.
class SavedSearchesDialog extends ConsumerWidget {
  const SavedSearchesDialog({super.key});

  /// Shows the search's results in its feed and resets its "new" badge.
  static Future<void> openResults(BuildContext context, WidgetRef ref, SavedSearch search) async {
    if (search.module == SavedSearchModule.buySell) {
      ref.read(buySellSectionProvider.notifier).state = BuySellSection.listings;
      ref.read(buySellFilterProvider.notifier).state = BuySellFilterState(
        query: search.query ?? '',
        category: search.categoryName ?? 'All',
        minPrice: search.minPrice,
        maxPrice: search.maxPrice,
        selectedStatuses: {ListingStatus.available},
      );
      ref.read(tabIndexProvider.notifier).state = 0;
    } else {
      ref.read(lostFoundFilterProvider.notifier).state = LostFoundFilterState(
        query: search.query ?? '',
        category: search.categoryName ?? 'All',
        typeFilter: PostType.found,
      );
      ref.read(tabIndexProvider.notifier).state = 1;
    }
    try {
      await ref.read(alertsRepositoryProvider).markSeen(search.id);
      ref.invalidate(savedSearchesProvider);
    } catch (_) {
      // The badge just stays until next time; the results are already showing.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchesAsync = ref.watch(savedSearchesProvider);
    final theme = Theme.of(context);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(savedSearchesProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700),
          );
        }
      }
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.saved_search_rounded),
          SizedBox(width: 10),
          Text('Saved searches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 460,
        child: searchesAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text(errorText(e))),
          data: (searches) {
            if (searches.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No saved searches yet. Set up filters in Buy & Sell or Lost & Found, '
                  'then tap the bell-plus icon to get alerts for new matches.',
                  style: TextStyle(color: theme.hintColor),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: searches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = searches[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(
                    s.module == SavedSearchModule.buySell
                        ? Icons.shopping_bag_outlined
                        : Icons.find_in_page_outlined,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(s.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      if (s.newCount > 0) ...[
                        const SizedBox(width: 6),
                        Badge(label: Text('${s.newCount} new')),
                      ],
                    ],
                  ),
                  subtitle: Text('${s.module.label} · ${s.filterSummary}', style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    openResults(context, ref, s);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: s.alertsEnabled ? 'Alerts on: tap to pause' : 'Alerts paused: tap to turn on',
                        icon: Icon(
                          s.alertsEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                          color: s.alertsEnabled ? theme.colorScheme.primary : theme.hintColor,
                          size: 20,
                        ),
                        onPressed: () => run(() => ref
                            .read(alertsRepositoryProvider)
                            .updateSavedSearch(s.id, alertsEnabled: !s.alertsEnabled)),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        onPressed: () => run(() => ref.read(alertsRepositoryProvider).deleteSavedSearch(s.id)),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
