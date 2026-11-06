import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/web_history_support.dart';
import '../domain/seller_strike.dart';
import '../providers/seller_trust_providers.dart';

/// My seller-trust strike history (future plan §1.5): what got removed, why, whether the listing
/// is currently hidden pending review, and a way to contest a strike that hasn't been appealed yet.
/// A blocked seller can also ask the moderators to unblock them.
class MySellerStrikesDialog extends ConsumerWidget {
  const MySellerStrikesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strikesAsync = ref.watch(mySellerStrikesProvider);
    final summary = ref.watch(myStrikeSummaryProvider).valueOrNull;
    final theme = Theme.of(context);

    return ModalHistoryWrapper(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 10),
            const Expanded(child: Text('Seller strikes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            if (summary != null) _StrikeCount(summary: summary),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (summary != null && (summary.suspended || summary.tag == 'blocked')) const _UnblockRequestCard(),
              Flexible(child: strikesAsync.when(
            loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text(errorText(e))),
            data: (strikes) {
              if (strikes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No strikes against your account. A strike is recorded only when a moderator '
                    'removes a listing of yours while resolving a report against it.',
                    style: TextStyle(color: theme.hintColor),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: strikes.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _StrikeTile(strike: strikes[i]),
              );
            },
          )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

/// Shown while I'm blocked: ask the Buy & Sell moderators to unblock me, or see where my request stands.
class _UnblockRequestCard extends ConsumerStatefulWidget {
  const _UnblockRequestCard();

  @override
  ConsumerState<_UnblockRequestCard> createState() => _UnblockRequestCardState();
}

class _UnblockRequestCardState extends ConsumerState<_UnblockRequestCard> {
  final _messageController = TextEditingController();
  bool _isWriting = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(sellerTrustRepositoryProvider).requestUnblock(message);
      ref.invalidate(myUnblockRequestProvider);
      if (mounted) setState(() => _isWriting = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = ref.watch(myUnblockRequestProvider).valueOrNull;
    final pending = request != null && request.isPending;
    final rejected = request != null && request.status == 'rejected';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block_rounded, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('You are blocked as a seller', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (pending)
            Text(
              'You asked to be unblocked on ${DateTimeFormatter.shortDate(request.createdAt)}. A Buy & Sell '
              'moderator will review it; you\'ll get a notification either way.',
              style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.35),
            )
          else ...[
            Text(
              rejected
                  ? 'A moderator kept the block on your last request'
                      '${request.resolutionNote != null ? ': "${request.resolutionNote}"' : ''}. You can ask again.'
                  : 'You can\'t post listings right now. If you think this should change, ask the Buy & Sell '
                      'moderators to unblock you. If they agree, your strikes are reset.',
              style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.35),
            ),
            const SizedBox(height: 8),
            if (_isWriting) ...[
              TextField(
                controller: _messageController,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Why should you be unblocked?',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => setState(() => _isWriting = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send request'),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isWriting = true),
                  icon: const Icon(Icons.lock_open_rounded, size: 16),
                  label: const Text('Request unblocking'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };

/// "Strikes: 1/3" with a (?) that explains the rules on hover (or tap, on a phone).
class _StrikeCount extends StatelessWidget {
  final StrikeSummary summary;

  const _StrikeCount({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final color = s.suspended
        ? theme.colorScheme.error
        : s.nonSevere >= s.negativeAt
            ? Colors.orange.shade800
            : theme.colorScheme.onSurface;
    final rules = 'How strikes work\n'
        '• A strike is added only when a moderator removes your listing after a report.\n'
        '• ${_ordinal(s.negativeAt)} strike: buyers see a "Negative Seller" tag on your listings.\n'
        '• ${_ordinal(s.limit)} strike: "Blocked Seller", and you can\'t post new listings until a moderator '
        'lets you.\n'
        '• Illegal items (drugs, weapons and the like): one strike blocks you at once.\n'
        '• You can appeal each strike once. If a moderator overturns it, it stops counting.';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.severe > 0 ? 'Strikes: ${s.strikes} (blocked)' : 'Strikes: ${s.nonSevere}/${s.limit}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
        Tooltip(
          message: rules,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 12),
          preferBelow: true,
          // Fixed dark box with white text: readable in both themes (the dark theme's default tooltip is
          // light grey, which washed the white text out).
          textStyle: const TextStyle(fontSize: 12, color: Colors.white, height: 1.4),
          decoration: BoxDecoration(color: const Color(0xFF1F2937), borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(10),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: MouseRegion(
              cursor: SystemMouseCursors.help,
              child: Icon(Icons.help_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _StrikeTile extends ConsumerStatefulWidget {
  final SellerStrike strike;
  const _StrikeTile({required this.strike});

  @override
  ConsumerState<_StrikeTile> createState() => _StrikeTileState();
}

class _StrikeTileState extends ConsumerState<_StrikeTile> {
  bool _isAppealing = false;
  bool _isSubmitting = false;
  final _appealController = TextEditingController();

  @override
  void dispose() {
    _appealController.dispose();
    super.dispose();
  }

  Future<void> _submitAppeal() async {
    final message = _appealController.text.trim();
    if (message.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(sellerTrustRepositoryProvider).appealStrike(widget.strike.id, message);
      ref.invalidate(mySellerStrikesProvider);
      if (mounted) setState(() => _isAppealing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strike;
    final severityColor = s.isSevere ? Colors.red.shade700 : Colors.orange.shade800;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(s.listingTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Text(DateTimeFormatter.timeAgo(s.createdAt),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(s.isSevere ? 'Severe' : 'Non-severe', severityColor),
              if (s.excluded)
                _chip('Overturned — no longer counts', Colors.green.shade700)
              else if (s.listingHidden)
                _chip('Hidden pending review', Colors.grey.shade700),
            ],
          ),
          if (s.moderatorNote != null && s.moderatorNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Moderator note: ${s.moderatorNote}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          _appealSection(s),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _appealSection(SellerStrike s) {
    switch (s.appealStatus) {
      case AppealStatus.overturned:
        return const SizedBox.shrink();
      case AppealStatus.rejected:
        return Text('Your appeal was reviewed and the strike stands.',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600));
      case AppealStatus.pending:
        return Text('Appeal submitted — awaiting a moderator\'s review.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w600));
      case AppealStatus.none:
        if (s.excluded) return const SizedBox.shrink();
        if (!_isAppealing) {
          return OutlinedButton.icon(
            onPressed: () => setState(() => _isAppealing = true),
            icon: const Icon(Icons.flag_outlined, size: 14),
            label: const Text('Contest this strike', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _appealController,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                hintText: 'Explain why this removal was a mistake…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => setState(() => _isAppealing = false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submitAppeal,
                    child: _isSubmitting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit appeal'),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }
}
