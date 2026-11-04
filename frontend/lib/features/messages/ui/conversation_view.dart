import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../domain/messages_models.dart';
import '../providers/messages_providers.dart';

/// "₹2,400" from "2400".
String rupees(String? amount) {
  final value = double.tryParse(amount ?? '');
  if (value == null) return '₹${amount ?? '?'}';
  final whole = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '₹$buffer';
}

void _snack(BuildContext context, Object message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message is String ? message : errorText(message)), behavior: SnackBarBehavior.floating),
  );
}

/// The chat with one person: everything discussed with them, like a WhatsApp chat. Item cards in
/// the thread show where talk about a listing or a Lost & Found report starts; the chips under the
/// header filter to one of them, and the composer says what the next message is about.
/// `?topic=general`: open the chat on no item (a general chat).
const generalTopic = 'general';

class ConversationView extends ConsumerStatefulWidget {
  final String conversationId;

  /// The topic to start on (e.g. the listing whose "Message seller" opened this chat).
  final String? initialTopicId;
  final VoidCallback? onBack;

  const ConversationView({super.key, required this.conversationId, this.initialTopicId, this.onBack});

  @override
  ConsumerState<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends ConsumerState<ConversationView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  /// What the next message is about; null is general chat.
  String? _aboutTopicId;
  bool _aboutChosen = false;

  /// Show only this topic's messages; null shows everything.
  String? _filterTopicId;

  ConversationController get _controller => ref.read(conversationControllerProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    _aboutTopicId = widget.initialTopicId == generalTopic ? null : widget.initialTopicId;
    _aboutChosen = widget.initialTopicId != null;
    _scroll.addListener(() {
      // The list is reversed: the top (older messages) is the max scroll extent.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 120) {
        _controller.loadOlder().catchError((Object e) {
          if (mounted) _snack(context, e);
        });
      }
    });
  }

  @override
  void didUpdateWidget(ConversationView old) {
    super.didUpdateWidget(old);
    if (widget.initialTopicId != old.initialTopicId && widget.initialTopicId != null) {
      setState(() {
        _aboutTopicId = widget.initialTopicId == generalTopic ? null : widget.initialTopicId;
        _aboutChosen = true;
        _filterTopicId = null;
      });
    }
  }

  /// Until the user picks, carry on with whatever the latest message was about.
  String? _about(ConversationState state) {
    if (_aboutChosen) return _aboutTopicId;
    final latest = state.ordered.lastOrNull;
    return latest?.topicId ?? (state.conversation!.topics.length == 1 ? state.conversation!.topics.single.id : null);
  }

  void _setAbout(String? topicId) => setState(() {
    _aboutTopicId = topicId;
    _aboutChosen = true;
  });

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _controller.sendText(
        text,
        topicId: _about(ref.read(conversationControllerProvider(widget.conversationId))),
      );
      _input.clear();
      ref.invalidate(conversationsProvider);
    } catch (e) {
      if (mounted) _snack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _makeOffer(ChatTopic topic) async {
    final result = await showDialog<({String amount, String note})>(
      context: context,
      builder: (_) => _OfferDialog(topic: topic),
    );
    if (result == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await _controller.sendOffer(topic.id, result.amount, result.note);
      ref.invalidate(conversationsProvider);
    } catch (e) {
      if (mounted) _snack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openListing(ChatTopic topic) async {
    if (!topic.isListing || topic.isRemoved) return;
    try {
      final item = await ref.read(buySellRepositoryProvider).getListingById(topic.refId);
      if (!mounted) return;
      if (item == null) throw Exception('This listing has been removed.');
      await showDialog(
        context: context,
        builder: (_) => BuySellDetailDialog(item: item),
      );
    } catch (e) {
      if (mounted) _snack(context, e);
    }
  }

  /// Copy, delete for me (any message) and delete for everyone (my own), like WhatsApp.
  Future<void> _messageActions(ChatMessage m) async {
    final red = Colors.red.shade700;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.text != null && !m.isDeleted)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete for me'),
              subtitle: const Text('Only you stop seeing it'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            if (m.mine && !m.isDeleted)
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: red),
                title: Text('Delete for everyone', style: TextStyle(color: red)),
                subtitle: const Text('Erases it for both of you'),
                onTap: () => Navigator.pop(context, 'unsend'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    try {
      if (action == 'copy') await Clipboard.setData(ClipboardData(text: m.text!));
      if (action == 'hide') {
        await _controller.hideForMe(m.id);
        ref.invalidate(conversationsProvider);
      }
      if (action == 'unsend') {
        await _controller.unsend(m.id);
        ref.invalidate(conversationsProvider);
      }
    } catch (e) {
      if (mounted) _snack(context, e);
    }
  }

  Future<void> _answer(ChatMessage m, String action) async {
    try {
      await _controller.answerOffer(m.id, action);
      ref.invalidate(conversationsProvider);
      // Accepting reserves the listing (and withdrawing or declining may free it): update the Buy & Sell feed.
      ref.read(buySellPaginationProvider.notifier).refreshQuietly();
      ref.invalidate(buySellListingsProvider);
      ref.invalidate(myBuySellListingsProvider);
    } catch (e) {
      if (mounted) _snack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationControllerProvider(widget.conversationId));
    final theme = Theme.of(context);
    final c = state.conversation;

    if (c == null) {
      return Center(
        child: state.loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(errorText(state.error ?? 'Couldn’t open this conversation.'), textAlign: TextAlign.center),
              ),
      );
    }
    final all = state.ordered;
    final filter = c.topic(_filterTopicId);
    final messages = filter == null ? all : all.where((m) => m.topicId == filter.id).toList();
    // Read receipts: every message of mine up to the other person's last read one shows two blue ticks, and
    // the word "Seen" goes under the newest of them.
    final seenId = all.where((m) => m.mine && !m.isDeleted && m.seq <= c.peerLastReadSeq).lastOrNull?.id;
    final about = c.topic(_about(state));

    return Column(
      children: [
        _Header(conversation: c, onBack: widget.onBack),
        if (c.topics.isNotEmpty)
          _TopicBar(
            topics: c.topics,
            selectedId: filter?.id,
            onSelected: (topic) => setState(() {
              _filterTopicId = topic?.id;
              if (topic != null) _setAbout(topic.id);
            }),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: messages.length + 1,
            itemBuilder: (context, i) {
              if (i == messages.length) {
                if (state.hasOlder) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                }
                return Column(
                  children: [
                    const _PrivacyNotice(),
                    if (messages.isEmpty && filter != null)
                      _TopicCard(topic: filter, onOpen: () => _openListing(filter)),
                  ],
                );
              }
              final index = messages.length - 1 - i;
              final m = messages[index];
              final previous = index > 0 ? messages[index - 1] : null;
              final peerKeyChanged = previous != null && _peerKeyId(previous) != _peerKeyId(m);
              final topic = c.topic(m.topicId);
              // An item card where talk about something (else) starts.
              final topicStarts = topic != null && (previous == null || previous.topicId != m.topicId);
              return Column(
                children: [
                  if (previous == null || !_sameDay(previous.raw.sentAt, m.raw.sentAt)) _DayDivider(m.raw.sentAt),
                  if (peerKeyChanged) _KeyChangedNotice(name: c.peerName),
                  if (topicStarts) _TopicCard(topic: topic, onOpen: () => _openListing(topic)),
                  _Bubble(
                    message: m,
                    peerName: c.peerName,
                    read: m.mine && m.seq <= c.peerLastReadSeq,
                    seen: m.id == seenId,
                    onLongPress: () => _messageActions(m),
                    onAnswer: (action) => _answer(m, action),
                  ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        _Composer(
          conversation: c,
          about: about,
          onAbout: _setAbout,
          controller: _input,
          sending: _sending,
          onSend: _sendText,
          onOffer: about != null && about.canTakeOffers ? () => _makeOffer(about) : null,
          theme: theme,
        ),
      ],
    );
  }

  static String _peerKeyId(ChatMessage m) => m.mine ? m.raw.recipientKeyId : m.raw.senderKeyId;

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Header extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onBack;

  const _Header({required this.conversation, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final theme = Theme.of(context);
    final n = c.topics.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              c.peerName.isEmpty ? '?' : c.peerName[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.peerName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  n == 0 ? 'General chat' : '$n ${n == 1 ? 'item' : 'items'} discussed',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _topicIcon(ChatTopic t) => switch (t.kind) {
  ChatTopicKind.listing => Icons.shopping_bag_outlined,
  ChatTopicKind.lostReport => Icons.search_rounded,
  ChatTopicKind.foundReport => Icons.volunteer_activism_outlined,
};

/// "All" plus one chip per item discussed; picking one shows only its messages.
class _TopicBar extends StatelessWidget {
  final List<ChatTopic> topics;
  final String? selectedId;
  final ValueChanged<ChatTopic?> onSelected;

  const _TopicBar({required this.topics, required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selectedId == null,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onSelected(null),
          ),
          for (final t in topics) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              key: ValueKey('topic_chip_${t.id}'),
              avatar: Icon(_topicIcon(t), size: 15),
              label: Text(
                t.isRemoved || t.status != 'available' && t.isListing ? '${t.label} · ${t.statusLabel}' : t.label,
                overflow: TextOverflow.ellipsis,
              ),
              selected: selectedId == t.id,
              visualDensity: VisualDensity.compact,
              onSelected: (on) => onSelected(on ? t : null),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where talk about an item starts in the thread: its photo, title, price and status.
class _TopicCard extends StatelessWidget {
  final ChatTopic topic;
  final VoidCallback onOpen;

  const _TopicCard({required this.topic, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = topic;
    final theme = Theme.of(context);
    final details = [
      if (t.price != null) rupees('${t.price}'),
      t.statusLabel,
      if (t.description != null && t.description!.isNotEmpty) t.description!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: t.isListing && !t.isRemoved ? onOpen : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: t.coverPhotoUrl != null
                            ? Image.network(
                                t.coverPhotoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(_topicIcon(t)),
                              )
                            : ColoredBox(color: theme.colorScheme.surfaceContainerHigh, child: Icon(_topicIcon(t))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.label,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            details,
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (t.isListing && !t.isRemoved) Icon(Icons.chevron_right_rounded, color: theme.hintColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_rounded, size: 16, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Messages and offers are private to the two of you. Moderators and admins can’t see them '
                'in the app.',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  final DateTime day;

  const _DayDivider(this.day);

  @override
  Widget build(BuildContext context) {
    final full = DateTimeFormatter.fullDateTime(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        full.substring(0, full.indexOf(',')),
        style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _KeyChangedNotice extends StatelessWidget {
  final String name;

  const _KeyChangedNotice({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key_rounded, size: 14, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'The messaging key in this chat changed, so some earlier messages may not open.',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  final ChatMessage message;
  final String peerName;

  /// The other person has read this message (two blue ticks).
  final bool read;

  /// The newest message the other person has read: also labelled "Seen".
  final bool seen;
  final VoidCallback onLongPress;
  final ValueChanged<String> onAnswer;

  const _Bubble({
    required this.message,
    required this.peerName,
    required this.read,
    required this.seen,
    required this.onLongPress,
    required this.onAnswer,
  });

  @override
  State<_Bubble> createState() => _BubbleState();
}

/// A message. Long-press or right-click opens its actions; with a mouse, a small arrow also appears
/// on hover (as on WhatsApp Web).
class _BubbleState extends State<_Bubble> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final peerName = widget.peerName;
    final read = widget.read;
    final seen = widget.seen;
    final onLongPress = widget.onLongPress;
    final onAnswer = widget.onAnswer;
    final theme = Theme.of(context);
    final mine = m.mine;
    final background = mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final foreground = mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final time = DateTimeFormatter.fullDateTime(m.raw.sentAt);
    final clock = time.substring(time.indexOf(', ') + 2);

    Widget content;
    if (m.isDeleted) {
      content = Text(
        mine ? 'You unsent a message' : 'This message was unsent',
        style: TextStyle(color: foreground.withValues(alpha: 0.75), fontStyle: FontStyle.italic),
      );
    } else if (m.unreadableReason != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              m.unreadableReason!,
              style: TextStyle(color: foreground, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      );
    } else if (m.isOffer) {
      content = _OfferCard(message: m, peerName: peerName, foreground: foreground, onAnswer: onAnswer);
    } else {
      // Plain Text: SelectableText would swallow the long-press / right-click that opens Copy and Unsend.
      content = Text(m.text ?? '', style: TextStyle(color: foreground, fontSize: 14, height: 1.3));
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mine) _menuArrow(theme),
                  Flexible(
                    child: GestureDetector(
                      onLongPress: onLongPress,
                      onSecondaryTap: onLongPress,
                      child: Container(
                        key: ValueKey('message_${m.id}'),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: m.isDeleted ? background.withValues(alpha: 0.5) : background,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(mine ? 14 : 4),
                            bottomRight: Radius.circular(mine ? 4 : 14),
                          ),
                        ),
                        child: content,
                      ),
                    ),
                  ),
                  if (!mine) _menuArrow(theme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(clock, style: TextStyle(fontSize: 10, color: theme.hintColor)),
                  if (mine && !m.isDeleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 13,
                      color: read ? theme.colorScheme.primary : theme.hintColor,
                    ),
                    if (seen) Text(' Seen', style: TextStyle(fontSize: 10, color: theme.colorScheme.primary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuArrow(ThemeData theme) => AnimatedOpacity(
    opacity: _hover ? 1 : 0,
    duration: const Duration(milliseconds: 120),
    child: IconButton(
      tooltip: 'Message options',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: _hover ? widget.onLongPress : null,
      icon: Icon(Icons.expand_more_rounded, color: theme.hintColor),
    ),
  );
}

class _OfferCard extends StatelessWidget {
  final ChatMessage message;
  final String peerName;
  final Color foreground;
  final ValueChanged<String> onAnswer;

  const _OfferCard({required this.message, required this.peerName, required this.foreground, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final status = m.raw.offerStatus ?? OfferStatus.pending;
    final pending = status == OfferStatus.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(m.mine ? 'Your offer' : '$peerName’s offer', style: TextStyle(color: foreground, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          rupees(m.offerAmount),
          style: TextStyle(color: foreground, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        if (m.offerNote != null && m.offerNote!.isNotEmpty)
          Text(m.offerNote!, style: TextStyle(color: foreground, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: foreground.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Text(
            status.label,
            key: ValueKey('offer_status_${m.id}'),
            style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        if (pending) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: m.mine
                ? [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: foreground,
                        side: BorderSide(color: foreground),
                      ),
                      onPressed: () => onAnswer('withdraw'),
                      child: const Text('Withdraw'),
                    ),
                  ]
                : [
                    FilledButton(onPressed: () => onAnswer('accept'), child: const Text('Accept')),
                    OutlinedButton(onPressed: () => onAnswer('decline'), child: const Text('Decline')),
                  ],
          ),
        ],
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  final Conversation conversation;

  /// What the next message is about (null: general chat).
  final ChatTopic? about;
  final ValueChanged<String?> onAbout;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  /// Null when the current topic can't take offers.
  final VoidCallback? onOffer;
  final ThemeData theme;

  const _Composer({
    required this.conversation,
    required this.about,
    required this.onAbout,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onOffer,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    if (!c.canSend) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: theme.hintColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.cantSendReason ?? '', style: TextStyle(color: theme.hintColor)),
            ),
          ],
        ),
      );
    }
    final offerHint = about == null
        ? 'Pick a listing to make an offer'
        : about!.isListing
        ? (onOffer == null ? 'This listing isn’t taking offers' : 'Make an offer on ${about!.label}')
        : 'Offers are for Buy & Sell listings';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.topics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 6),
                child: PopupMenuButton<String>(
                  key: const Key('chat_about'),
                  tooltip: 'What this message is about',
                  onSelected: (v) => onAbout(v.isEmpty ? null : v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: '',
                      child: ListTile(dense: true, leading: Icon(Icons.chat_outlined), title: Text('General chat')),
                    ),
                    for (final t in c.topics)
                      PopupMenuItem(
                        value: t.id,
                        child: ListTile(
                          dense: true,
                          leading: Icon(_topicIcon(t)),
                          title: Text(t.label, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          about == null ? Icons.chat_outlined : _topicIcon(about!),
                          size: 14,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            'About: ${about?.label ?? 'General chat'}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSecondaryContainer),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, size: 18, color: theme.colorScheme.onSecondaryContainer),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: offerHint,
                  icon: const Icon(Icons.local_offer_outlined),
                  onPressed: onOffer != null && !sending ? onOffer : null,
                ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {const SingleActivator(LogicalKeyboardKey.enter): onSend},
                    child: TextField(
                      key: const Key('chat_input'),
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: 'Message ${c.peerName}',
                        counterText: '',
                        isDense: true,
                        prefixIcon: Icon(Icons.lock_rounded, size: 14, color: theme.hintColor),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const Key('chat_send'),
                  tooltip: 'Send',
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferDialog extends StatefulWidget {
  final ChatTopic topic;

  const _OfferDialog({required this.topic});

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0 || value > 99999999) {
      setState(() => _error = 'Enter an amount in rupees.');
      return;
    }
    Navigator.pop(context, (
      amount: value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2),
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Make an offer: ${widget.topic.label}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Listed at ${rupees('${widget.topic.price}')}. The other person can accept or decline. '
              'Only the two of you see the amount.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('offer_amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Your offer',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Send offer')),
      ],
    );
  }
}
