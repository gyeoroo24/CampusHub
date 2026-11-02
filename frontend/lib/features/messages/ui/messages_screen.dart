import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/web_history_support.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../data/messages_repository.dart';
import '../domain/messages_models.dart';
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
  // Opened from a dialog (a listing, a search): close it. From a page (a company), leave the page be.
  final inDialog = ModalRoute.of(context) is PopupRoute;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final started = await repo.startConversation(target);
    ref.invalidate(conversationsProvider);
    if (inDialog && navigator.canPop()) {
      navigator.pop();   // close the listing dialog
      await WebHistoryManager.instance.settled;
    }
    // A general chat (someone picked from search or a company's seniors) starts on no item at all.
    final topic = started.topicId != null
        ? '?topic=${started.topicId}'
        : (target.containsKey('user_id') ? '?topic=$generalTopic' : '');
    // Pushed, so Back returns to where the chat was opened from (a company page, a listing...).
    router.push('/messages/${started.conversation.id}$topic');
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
        onBack: () => context.replace('/messages'),
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
                onPressed: () => context.canPop() ? context.pop() : context.go('/buy'),
              ),
              title: const Text('Messages'),
              actions: [
                if (session?.isReady == true) const _PeopleSearch(),
                if (session?.isReady == true) const _SecurityMenu(),
              ],
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
                'No conversations yet. Tap “Message” on a Buy & Sell listing or a Lost & Found post, or search '
                'for someone by name or email above.',
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
                  // Replace, not go: keeps whatever page opened Messages underneath for Back.
                  context.replace('/messages/${c.id}');
                  ref.invalidate(conversationsProvider);
                },
                onLongPress: () => _confirmDelete(context, ref, c),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Chat options',
                  icon: Icon(Icons.more_vert_rounded, size: 18, color: theme.hintColor),
                  onSelected: (_) => _confirmDelete(context, ref, c),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'delete', child: Text('Delete chat', style: TextStyle(color: Colors.red.shade700))),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Deletes a chat for me only (the other person keeps it; new messages bring it back).
Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Conversation c) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete your chat with ${c.peerName}?'),
      content: Text('It disappears from your messages. ${c.peerName} keeps their copy. If they write again, '
          'you’ll see only the new messages.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete chat'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(messagesRepositoryProvider)!.deleteConversation(c.id);
    ref.invalidate(conversationsProvider);
    if (context.mounted && GoRouterState.of(context).uri.path == '/messages/${c.id}') context.replace('/messages');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
    }
  }
}

/// The search bar in the Messages top bar: find anyone on CampusHub by name or email and open a
/// general chat (about no item) with them.
class _PeopleSearch extends ConsumerStatefulWidget {
  const _PeopleSearch();

  @override
  ConsumerState<_PeopleSearch> createState() => _PeopleSearchState();
}

class _PeopleSearchState extends ConsumerState<_PeopleSearch> {
  final _controller = SearchController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<Iterable<Widget>> _suggestions(BuildContext context, SearchController controller) async {
    final q = controller.text.trim();
    final theme = Theme.of(context);
    if (q.length < 2) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Type a name or email to start a chat.', style: TextStyle(color: theme.hintColor)),
        ),
      ];
    }
    try {
      final people = await ref.read(messagesRepositoryProvider)!.searchUsers(q);
      if (people.isEmpty) {
        return [Padding(padding: const EdgeInsets.all(16), child: Text('Nobody found for “$q”.'))];
      }
      return [
        for (final u in people)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(u.name),
            subtitle: Text([u.email, if (u.programme != null) u.programme!].join(' · '), overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            onTap: () {
              controller.closeView('');
              openChatAbout(this.context, ref, {'user_id': u.id});
            },
          ),
      ];
    } catch (e) {
      return [Padding(padding: const EdgeInsets.all(16), child: Text(errorText(e)))];
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: width < 600 ? width * 0.55 : 340,
        child: SearchAnchor.bar(
          searchController: _controller,
          barHintText: 'Search people to chat with',
          barLeading: const Icon(Icons.search_rounded, size: 20),
          barElevation: const WidgetStatePropertyAll(0),
          constraints: const BoxConstraints(minHeight: 40),
          viewHintText: 'Name or email',
          suggestionsBuilder: _suggestions,
        ),
      ),
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
