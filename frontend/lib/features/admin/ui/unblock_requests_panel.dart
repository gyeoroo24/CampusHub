import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../seller_trust/domain/seller_strike.dart';
import '../../seller_trust/providers/seller_trust_providers.dart';

/// The Unblock Requests tab (Buy & Sell moderators and the admin): every seller who is blocked right now,
/// with the request they sent if any, and the requests already decided. Unblocking resets the seller's
/// strikes, lifts their posting suspension and notifies them.
class UnblockRequestsPanel extends ConsumerWidget {
  const UnblockRequestsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blockedAsync = ref.watch(blockedSellersProvider);
    final historyAsync = ref.watch(resolvedUnblockRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(blockedSellersProvider);
        ref.invalidate(resolvedUnblockRequestsProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Blocked sellers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  'Sellers who can\'t post listings right now. Those who asked to be unblocked are listed first. '
                  'Unblocking resets their strikes and tells them; the listings that were removed stay hidden.',
                  style: TextStyle(fontSize: 11.5, color: theme.hintColor),
                ),
                const SizedBox(height: 14),
                blockedAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error loading blocked sellers: ${errorText(e)}',
                      style: const TextStyle(color: Colors.red)),
                  data: (sellers) {
                    if (sellers.isEmpty) return const _EmptyState(text: 'No seller is blocked.');
                    final sorted = [...sellers]
                      ..sort((a, b) => (b.pendingRequest != null ? 1 : 0) - (a.pendingRequest != null ? 1 : 0));
                    return Column(
                      children: [
                        for (final s in sorted) ...[
                          _BlockedSellerCard(seller: s),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text('Decided requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                historyAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(errorText(e), style: const TextStyle(color: Colors.red)),
                  data: (requests) => requests.isEmpty
                      ? Text('None yet.', style: TextStyle(color: theme.hintColor, fontSize: 12.5))
                      : Column(children: [for (final r in requests) _DecidedRequestTile(request: r)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 40, color: Colors.green.shade600),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _BlockedSellerCard extends ConsumerStatefulWidget {
  final BlockedSeller seller;
  const _BlockedSellerCard({required this.seller});

  @override
  ConsumerState<_BlockedSellerCard> createState() => _BlockedSellerCardState();
}

class _BlockedSellerCardState extends ConsumerState<_BlockedSellerCard> {
  bool _busy = false;

  /// Asks for an optional note to send the seller. Null if the moderator cancelled.
  Future<String?> _askNote({required String title, required String body, required String action,
                            required Color color}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note to the seller (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(blockedSellersProvider);
      ref.invalidate(resolvedUnblockRequestsProvider);
      ref.invalidate(moderatedSellerStrikesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(done), backgroundColor: Colors.teal.shade700, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unblock() async {
    final s = widget.seller;
    final note = await _askNote(
      title: 'Unblock ${s.seller.name}?',
      body: 'Their ${s.strikes} strike${s.strikes == 1 ? '' : 's'} will be reset and they can post listings '
          'again. They get a notification.',
      action: 'Unblock seller',
      color: Colors.green.shade700,
    );
    if (note == null) return;
    final repo = ref.read(sellerTrustRepositoryProvider);
    final request = s.pendingRequest;
    await _run(
      () => request != null
          ? repo.approveUnblockRequest(request.id, note: note)
          : repo.unblockSeller(s.seller.id, note: note),
      'Unblocked ${s.seller.name} and reset their strikes.',
    );
  }

  Future<void> _decline() async {
    final request = widget.seller.pendingRequest;
    if (request == null) return;
    final note = await _askNote(
      title: 'Decline the request?',
      body: '${widget.seller.seller.name} stays blocked and is told. They can ask again later.',
      action: 'Decline',
      color: Colors.red.shade700,
    );
    if (note == null) return;
    await _run(() => ref.read(sellerTrustRepositoryProvider).rejectUnblockRequest(request.id, note: note),
        'Declined the request.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.seller;
    final request = s.pendingRequest;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: request != null ? Colors.orange.shade300 : theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.red.shade100,
                  child: Icon(Icons.block_rounded, size: 18, color: Colors.red.shade800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.seller.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(s.email, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                ),
                Text(
                  '${s.strikes} strike${s.strikes == 1 ? '' : 's'}${s.severe > 0 ? ' (${s.severe} severe)' : ''}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                ),
              ],
            ),
            if (s.suspendedReason != null) ...[
              const SizedBox(height: 8),
              Text('Blocked: ${s.suspendedReason}', style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ],
            if (request != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Asked to be unblocked · ${DateTimeFormatter.timeAgo(request.createdAt)}',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
                    const SizedBox(height: 4),
                    Text('"${request.message}"', style: const TextStyle(fontSize: 13, height: 1.35)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (request != null)
                  TextButton(
                    onPressed: _busy ? null : _decline,
                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                    child: const Text('Decline request'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _unblock,
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  icon: _busy
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_open_rounded, size: 16),
                  label: const Text('Unblock seller'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DecidedRequestTile extends StatelessWidget {
  final UnblockRequest request;
  const _DecidedRequestTile({required this.request});

  @override
  Widget build(BuildContext context) {
    final approved = request.status == 'approved';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(approved ? Icons.lock_open_rounded : Icons.block_rounded,
          color: approved ? Colors.green.shade700 : Colors.red.shade700),
      title: Text('${request.seller.name} · ${approved ? 'Unblocked' : 'Declined'}'),
      subtitle: Text(
        '"${request.message}"'
        '${request.resolutionNote != null ? '\nNote: ${request.resolutionNote}' : ''}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: request.resolvedAt != null
          ? Text(DateTimeFormatter.timeAgo(request.resolvedAt!), style: const TextStyle(fontSize: 11))
          : null,
    );
  }
}
