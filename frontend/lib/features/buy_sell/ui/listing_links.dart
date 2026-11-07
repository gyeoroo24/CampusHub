import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/buy_sell_item.dart';
import '../providers/buy_sell_providers.dart';
import 'widgets/buy_sell_detail_dialog.dart';

/// A listing's own address, `/buy/<id>`: opening a listing from the feed or the search puts it in the
/// browser's address bar (so it can be shared, bookmarked or refreshed), and opening that address shows
/// the listing over the Buy & Sell feed. The listing is a page of the router shown as the usual detail
/// dialog, so closing it, browser back and forward all just change the route.
String listingPath(String id) => '/buy/$id';

/// Opens [item] at its address. The summary is passed along so the dialog shows at once.
void showListingDetail(BuildContext context, ListingItem item) =>
    GoRouter.of(context).go(listingPath(item.id), extra: item);

/// The `/buy/<id>` route's page: a dialog over the feed page beneath it.
class ListingDialogPage extends Page<void> {
  final String listingId;
  final ListingItem? summary;

  const ListingDialogPage({super.key, required this.listingId, this.summary});

  @override
  Route<void> createRoute(BuildContext context) => DialogRoute<void>(
        context: context,
        settings: this,
        builder: (_) => _ListingLinkDialog(listingId: listingId, summary: summary),
      );
}

class _ListingLinkDialog extends ConsumerWidget {
  final String listingId;
  final ListingItem? summary;

  const _ListingLinkDialog({required this.listingId, this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> setStatus(ListingStatus status) async {
      await ref.read(buySellRepositoryProvider).updateStatus(listingId, status);
      ref.read(buySellPaginationProvider.notifier).updateItemStatusLocally(listingId, status);
    }

    final known = summary;
    if (known != null) return BuySellDetailDialog(item: known, onStatusChange: setStatus, ownHistoryEntry: false);
    // Opened from a link (or a refresh): nothing to show until the listing loads.
    return ref.watch(listingDetailProvider(listingId)).when(
          data: (item) => item == null
              ? const _Unavailable()
              : BuySellDetailDialog(item: item, onStatusChange: setStatus, ownHistoryEntry: false),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const _Unavailable(),
        );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Listing not available'),
        content: const Text('It may have been sold and removed, or the link is wrong.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to Buy & Sell'))],
      );
}
