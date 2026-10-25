import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/domain/buy_sell_item.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../domain/wanted_post.dart';
import '../providers/wanted_providers.dart';

/// One Wanted post: details, contact, the listings that already match, and the author's controls.
class WantedDetailDialog extends ConsumerStatefulWidget {
  final WantedPost post;

  const WantedDetailDialog({super.key, required this.post});

  @override
  ConsumerState<WantedDetailDialog> createState() => _WantedDetailDialogState();
}

class _WantedDetailDialogState extends ConsumerState<WantedDetailDialog> {
  late WantedPost _post = widget.post;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Feed cards carry no contact details; the full post does (for signed-in viewers).
    if (_post.authorContact == null) {
      ref.read(wantedRepositoryProvider).getWanted(_post.id).then((full) {
        if (mounted && full != null) setState(() => _post = full);
      }, onError: (_) {});
    }
  }

  Future<void> _setStatus(WantedStatus status) async {
    setState(() => _busy = true);
    try {
      final updated = await ref.read(wantedRepositoryProvider).updateStatus(_post.id, status);
      ref.invalidate(wantedPostsProvider);
      ref.invalidate(myWantedPostsProvider);
      setState(() => _post = _post.copyWith(status: updated.status));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove({required bool asModerator}) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(asModerator ? 'Remove this post?' : 'Delete your post?'),
        content: asModerator
            ? TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason (shown in the moderation log)'),
              )
            : const Text('It disappears from the Wanted feed and its alerts stop.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(asModerator ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true) return;
    try {
      await ref.read(wantedRepositoryProvider).deleteWanted(_post.id, reason: reason);
      ref.invalidate(wantedPostsProvider);
      ref.invalidate(myWantedPostsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final isOwner = user != null && user.isOwnerOf(_post.author.id);
    final canModerate = user != null && !isOwner && (user.canModerateBuySell || user.isAdmin);
    final matches = ref.watch(wantedMatchesProvider(_post.id));

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Pill(text: 'WANTED', color: Colors.deepPurple),
              _Pill(text: _post.category.name, color: theme.colorScheme.primary),
              if (_post.status != WantedStatus.open)
                _Pill(text: _post.status.label, color: Colors.grey.shade600),
            ],
          ),
          const SizedBox(height: 10),
          Text(_post.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.currency_rupee_rounded, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 4),
                  Text(_post.budgetLabel,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  const Spacer(),
                  Text(
                    '${_post.author.name} · ${DateTimeFormatter.timeAgo(_post.createdAt)}',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
              if ((_post.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_post.description!, style: const TextStyle(fontSize: 14)),
              ],
              const SizedBox(height: 14),
              if (_post.authorContact != null && !isOwner)
                _ContactRow(email: _post.authorContact!.email, phone: _post.authorContact!.phone)
              else if (user == null || user.isGuest)
                Text('Sign in to see how to contact the buyer.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              const Divider(height: 28),
              Text('Listings that match', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              matches.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => Text(errorText(e)),
                data: (items) => items.isEmpty
                    ? Text(
                        isOwner
                            ? "Nothing yet. You'll get a notification when a matching listing is posted."
                            : 'No listings match yet. Have one? List it in Buy & Sell.',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      )
                    : Column(children: [for (final l in items) _MatchTile(listing: l)]),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (isOwner)
          Wrap(
            spacing: 6,
            children: [
              for (final s in WantedStatus.values)
                ChoiceChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  selected: _post.status == s,
                  onSelected: _busy || _post.status == s ? null : (_) => _setStatus(s),
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                onPressed: _busy ? null : () => _remove(asModerator: false),
              ),
            ],
          )
        else if (canModerate)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => _remove(asModerator: true),
            icon: const Icon(Icons.gavel_rounded, size: 16),
            label: const Text('Moderator: Remove'),
          )
        else
          const SizedBox.shrink(),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String email;
  final String? phone;

  const _ContactRow({required this.email, this.phone});

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String value) => ActionChip(
          avatar: Icon(icon, size: 16),
          label: Text(value, style: const TextStyle(fontSize: 12)),
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied $value'), behavior: SnackBarBehavior.floating),
            );
          },
        );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        chip(Icons.email_outlined, email),
        if (phone != null && phone!.isNotEmpty) chip(Icons.phone_outlined, phone!),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  final ListingItem listing;

  const _MatchTile({required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: listing.imageUrl.isNotEmpty
              ? Image.network(listing.imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined))
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.shopping_bag_outlined, size: 20),
                ),
        ),
      ),
      title: Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [if (listing.location.isNotEmpty) listing.location, listing.seller.name].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('₹${listing.price.toStringAsFixed(0)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      onTap: () => showDialog(context: context, builder: (_) => BuySellDetailDialog(item: listing)),
    );
  }
}
