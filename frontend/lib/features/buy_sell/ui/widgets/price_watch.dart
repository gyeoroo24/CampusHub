import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/error_text.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';
import 'buy_sell_detail_dialog.dart';

/// "Negotiable" next to a price (future plan §2.3).
class NegotiableBadge extends StatelessWidget {
  final double fontSize;
  const NegotiableBadge({super.key, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Negotiable',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
        ),
      ),
    );
  }
}

/// Shown to the seller (and moderators) on a listing flagged automatically as a possible
/// prohibited item (future plan §1.6): nobody else can see it until a moderator decides.
class HeldForReviewBanner extends StatelessWidget {
  const HeldForReviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hidden until a moderator reviews it: it was flagged automatically as a possible '
              'prohibited item. Only you and moderators can see it.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Watch price" toggle on someone else's listing: notified when the price changes or the seller
/// marks it negotiable.
class WatchPriceButton extends ConsumerStatefulWidget {
  final ListingItem item;
  const WatchPriceButton({super.key, required this.item});

  @override
  ConsumerState<WatchPriceButton> createState() => _WatchPriceButtonState();
}

class _WatchPriceButtonState extends ConsumerState<WatchPriceButton> {
  late bool _watching = widget.item.watching;
  bool _busy = false;

  @override
  void didUpdateWidget(WatchPriceButton old) {
    super.didUpdateWidget(old);
    if (old.item.watching != widget.item.watching) _watching = widget.item.watching;
  }

  Future<void> _toggle() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(buySellRepositoryProvider).setWatching(widget.item.id, !_watching);
      setState(() => _watching = !_watching);
      ref.invalidate(watchedListingsProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(_watching
            ? "Watching. You'll be told if the price changes or it's marked negotiable."
            : 'Stopped watching this listing.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(_watching ? Icons.notifications_active : Icons.notifications_none_rounded, size: 18),
      label: Text(_watching ? 'Watching price' : 'Watch price'),
    );
  }
}

final watchedListingsProvider = FutureProvider.autoDispose<List<ListingItem>>(
    (ref) => ref.watch(buySellRepositoryProvider).fetchWatchedListings());

/// Account menu → "Watched listings".
class WatchedListingsDialog extends ConsumerWidget {
  const WatchedListingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(watchedListingsProvider);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.notifications_active_outlined),
        SizedBox(width: 10),
        Text('Watched listings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
      content: SizedBox(
        width: 420,
        child: watched.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(errorText(e)),
          data: (items) => items.isEmpty
              ? const Text('You aren\'t watching any listings. Open a listing and tap "Watch price" '
                  'to be told when its price changes.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${item.status.label} • ${item.seller.name}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (item.negotiable) ...[const NegotiableBadge(), const SizedBox(width: 6)],
                        Text('₹${item.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                      onTap: () => showDialog(context: context, builder: (_) => BuySellDetailDialog(item: item)),
                    );
                  },
                ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
