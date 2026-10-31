import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/web_history_support.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../data/messages_repository.dart';
import '../providers/messages_providers.dart';
import 'chat_setup_panel.dart';
import 'conversation_view.dart';

/// App-bar button with the unread-message badge. Hidden for guests and in mock mode.
class MessagesButton extends ConsumerWidget {
  const MessagesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isGuestUserProvider) || ref.watch(messagesRepositoryProvider) == null) {
      return const SizedBox.shrink();
    }
    final unread = ref.watch(chatUnreadCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: unread > 0 ? '$unread unread messages' : 'Messages',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: Icon(unread > 0 ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded, size: 21),
      ),
      onPressed: () => context.go('/messages'),
    );
  }
}

/// "Message seller" on a listing: opens the chat with the seller, about that listing.
Future<void> openChatAboutListing(BuildContext context, WidgetRef ref, String listingId) =>
    openChatAbout(context, ref, {'listing_id': listingId});

/// Opens (or reopens) the chat with whoever owns [target] (`listing_id`, `lost_report_id`,
/// `found_report_id`, or `user_id` for a general chat) and goes to it, on that topic. There is one
/// chat per person, so talking about a second item from the same person adds it to their chat.
Future<void> openChatAbout(BuildContext context, WidgetRef ref, Map<String, String> target) async {
  if (ref.read(isGuestUserProvider)) {
    await showDialog(context: context, builder: (_) => const AuthDialog());
    return;
  }
  final MessagesRepository? repo = ref.read(messagesRepositoryProvider);
  if (repo == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Messaging needs the live backend (there is no mock version).'),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final started = await repo.startConversation(target);
    ref.invalidate(conversationsProvider);
    if (navigator.canPop()) {
      navigator.pop();   // close the listing dialog
      await WebHistoryManager.instance.settled;
    }
    final topic = started.topicId == null ? '' : '?topic=${started.topicId}';
    router.go('/messages/${started.conversation.id}$topic');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
  }
}

/// `/messages` and `/messages/:id`: the inbox, and the open conversation beside it on wide screens.
class MessagesScreen extends ConsumerWidget {
  final String? conversationId;

  /// The topic to open the conversation on (`?topic=`).
  final String? topicId;

  const MessagesScreen({super.key, this.conversationId, this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(isGuestUserProvider);
    final sessionAsync = ref.watch(chatSessionProvider);
    final session = sessionAsync.valueOrNull;
    final wide = MediaQuery.of(context).size.width >= 900;
    final showingThread = conversationId != null && !wide;

    Widget body;
    if (isGuest) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sign in to message buyers and sellers.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => showDialog(context: context, builder: (_) => const AuthDialog()),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    } else if (sessionAsync.hasError && session == null) {
      body = Center(child: Text(errorText(sessionAsync.error!)));
    } else if (session == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (session.status == ChatSessionStatus.unavailable) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Messaging needs the live backend. There is no mock version.',
              textAlign: TextAlign.center),
        ),
      );
    } else if (!session.isReady) {
      body = ChatSetupPanel(session: session);
    } else if (wide) {
      body = Row(
        children: [
          SizedBox(width: 360, child: _Inbox(selectedId: conversationId)),
          const VerticalDivider(width: 1),
          Expanded(
            child: conversationId == null
                ? const _NothingSelected()
                : ConversationView(
                    key: ValueKey(conversationId), conversationId: conversationId!, initialTopicId: topicId),
          ),
        ],
      );
    } else if (conversationId != null) {
      body = ConversationView(
        key: ValueKey(conversationId),
        conversationId: conversationId!,
        initialTopicId: topicId,
        onBack: () => context.go('/messages'),
      );
    } else {
      body = const _Inbox();
    }

    return Scaffold(
      appBar: showingThread && session?.isReady == true
          ? null
          : AppBar(
              leading: IconButton(
                tooltip: 'Back to CampusHub',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/buy'),
              ),
              title: const Text('Messages'),
              actions: [if (session?.isReady == true) const _SecurityMenu()],
            ),
      body: SafeArea(child: body),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 40, color: hint),
          const SizedBox(height: 12),
          Text('Pick a conversation.', style: TextStyle(color: hint)),
        ],
      ),
    );
  }
}

class _Inbox extends ConsumerWidget {
  final String? selectedId;

  const _Inbox({this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(conversationsProvider);
    final theme = Theme.of(context);
    return inbox.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No conversations yet. Tap “Message” on a Buy & Sell listing or a Lost & Found post to start one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(conversationsProvider.future),
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final entry = entries[i];
              final c = entry.conversation;
              final unread = c.unreadCount > 0 && c.id != selectedId;
              final last = entry.lastMessage;
              final lastTopic = c.topic(last?.topicId);
              // "You · Hero Sprint: Is it still available?" (the item only when there are several).
              final prefix = [
                if (last != null && last.mine && !last.isDeleted) 'You',
                if (lastTopic != null && c.topics.length > 1) lastTopic.label,
              ].join(' · ');
              final preview = last == null ? 'No messages yet' : (prefix.isEmpty ? last.preview : '$prefix: ${last.preview}');
              final topicsLine = c.topics.isEmpty
                  ? 'General chat'
                  : c.topics.length <= 2
                      ? c.topics.map((t) => t.label).join(' · ')
                      : '${c.topics.reversed.take(2).map((t) => t.label).join(' · ')} +${c.topics.length - 2} more';
              return ListTile(
                key: ValueKey('conversation_${c.id}'),
                selected: c.id == selectedId,
                selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(c.peerName.isEmpty ? '?' : c.peerName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(c.peerName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w600)),
                    ),
                    Text(DateTimeFormatter.timeAgo(c.sortTime), style: TextStyle(fontSize: 11, color: theme.hintColor)),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topicsLine, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                              color: unread ? theme.colorScheme.onSurface : theme.hintColor,
                            ),
                          ),
                        ),
                        if (unread)
                          Badge(label: Text('${c.unreadCount}'), backgroundColor: theme.colorScheme.primary),
                      ],
                    ),
                  ],
                ),
                isThreeLine: true,
                onTap: () {
                  context.go('/messages/${c.id}');
                  ref.invalidate(conversationsProvider);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _SecurityMenu extends ConsumerWidget {
  const _SecurityMenu();

  Future<void> _showBlocked(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(messagesRepositoryProvider)!;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Blocked people'),
          content: SizedBox(
            width: 360,
            child: FutureBuilder(
              future: repo.fetchBlocked(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
                if (snap.data!.isEmpty) return const Text('You haven’t blocked anyone.');
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final u in snap.data!)
                      ListTile(
                        title: Text(u.name),
                        trailing: TextButton(
                          onPressed: () async {
                            await repo.unblock(u.id);
                            ref.invalidate(conversationsProvider);
                            setState(() {});
                          },
                          child: const Text('Unblock'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Message settings',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) async {
        if (v == 'blocked') await _showBlocked(context, ref);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'blocked', child: Text('Blocked people')),
      ],
    );
  }
}
