import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../forums/ui/thread_view.dart';
import '../../../core/utils/web_history_support.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../../lost_found/domain/lost_found_item.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../../lost_found/ui/widgets/lost_found_detail_dialog.dart';
import '../domain/alerts_models.dart';
import '../providers/alerts_providers.dart';

/// App-bar bell with an unread badge; opens the notification inbox. Hidden for guests.
class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isGuestUserProvider)) return const SizedBox.shrink();
    final unread = ref.watch(unreadNotificationsCountProvider);
    return IconButton(
      tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded, size: 22),
      ),
      onPressed: () {
        ref.invalidate(notificationsProvider);
        showDialog(context: context, builder: (_) => const NotificationsDialog());
      },
    );
  }
}

/// The inbox. Each notification has a remove button; "Select" picks several to delete at once,
/// and "Clear all" empties it.
class NotificationsDialog extends ConsumerStatefulWidget {
  const NotificationsDialog({super.key});

  @override
  ConsumerState<NotificationsDialog> createState() => _NotificationsDialogState();


  static IconData _icon(String type) {
    switch (type) {
      case 'saved_search_match':
        return Icons.saved_search_rounded;
      case 'wanted_post_match':
        return Icons.volunteer_activism_outlined;
      case 'lost_found_match':
        return Icons.find_in_page_rounded;
      case 'forum_reply':
        return Icons.forum_outlined;
      case 'chat_message':
        return Icons.chat_bubble_outline_rounded;
      case 'listing_watch':
        return Icons.trending_down_rounded;
      case 'moderation_action':
        return Icons.shield_outlined;
      case 'followed_tag_event':
        return Icons.event_available_rounded;
      case 'bookmarked_event_update':
        return Icons.event_note_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  /// Marks the notification read and opens what it points at (a listing or a found report).
  static Future<void> open(BuildContext context, WidgetRef ref, AppNotification n) async {
    if (!n.isRead) {
      ref.read(alertsRepositoryProvider).markRead(n.id).then((_) => ref.invalidate(notificationsProvider),
          onError: (_) {});
    }
    final conversationId = n.payload['conversation_id']?.toString();
    if (n.type == 'chat_message' && conversationId != null) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      await WebHistoryManager.instance.settled;
      router.go('/messages/$conversationId');
      return;
    }
    final eventId = n.payload['event_id']?.toString();
    if (eventId != null && n.payload['cancelled'] != true) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      await WebHistoryManager.instance.settled;
      router.go('/events/$eventId');
      return;
    }
    final threadId = n.payload['thread_id']?.toString();
    if (n.type == 'forum_reply' && threadId != null) {
      await showDialog(context: context, builder: (_) => ThreadDialog(threadId: threadId));
      return;
    }
    try {
      if (n.listingId != null) {
        final item = await ref.read(buySellRepositoryProvider).getListingById(n.listingId!);
        if (!context.mounted) return;
        if (item == null) throw Exception('This listing has been removed.');
        await showDialog(context: context, builder: (_) => BuySellDetailDialog(item: item));
      } else if (n.foundReportId != null) {
        final item =
            await ref.read(lostFoundRepositoryProvider).getReportById(n.foundReportId!, type: PostType.found);
        if (!context.mounted) return;
        if (item == null) throw Exception('This report has been removed.');
        await showDialog(context: context, builder: (_) => LostFoundDetailDialog(item: item));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

}

class _NotificationsDialogState extends ConsumerState<NotificationsDialog> {
  /// Null: not selecting. Otherwise the ids picked for deletion.
  Set<String>? _selected;
  bool _busy = false;

  Future<void> _delete(List<String> ids) async {
    if (ids.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(alertsRepositoryProvider).deleteNotifications(ids);
      ref.invalidate(notificationsProvider);
      if (mounted) setState(() => _selected = null);
    } catch (e) {
      if (mounted) _snack(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('They’ll be removed for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(alertsRepositoryProvider).clearNotifications();
      ref.invalidate(notificationsProvider);
      if (mounted) setState(() => _selected = null);
    } catch (e) {
      if (mounted) _snack(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(Object e) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsCountProvider);
    final items = notificationsAsync.valueOrNull ?? const <AppNotification>[];
    final theme = Theme.of(context);
    final selected = _selected;
    final selecting = selected != null;

    return ModalHistoryWrapper(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        title: Row(
          children: [
            if (selecting)
              Checkbox(
                tristate: true,
                value: selected.isEmpty ? false : (selected.length == items.length ? true : null),
                onChanged: (_) => setState(() =>
                    _selected = selected.length == items.length ? <String>{} : {for (final n in items) n.id}),
              )
            else
              const Icon(Icons.notifications_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Text(selecting ? '${selected.length} selected' : 'Notifications',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (!selecting && unread > 0)
              TextButton(
                onPressed: () async {
                  await ref.read(alertsRepositoryProvider).markAllRead();
                  ref.invalidate(notificationsProvider);
                },
                child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
              ),
            if (!selecting && items.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (v) => v == 'select' ? setState(() => _selected = <String>{}) : _clearAll(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'select',
                      child: ListTile(dense: true, leading: Icon(Icons.checklist_rounded), title: Text('Select'))),
                  PopupMenuItem(
                      value: 'clear',
                      child: ListTile(
                          dense: true, leading: Icon(Icons.clear_all_rounded), title: Text('Clear all'))),
                ],
              ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        content: SizedBox(
          width: 460,
          // At most 420px, less on short screens so the dialog never overflows.
          height: (MediaQuery.of(context).size.height * 0.6).clamp(160.0, 420.0),
          child: notificationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(errorText(e))),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'You’re all caught up. Save a search or post a Wanted request, and matches will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor),
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = items[i];
                  final opens = n.listingId != null ||
                      n.foundReportId != null ||
                      n.type == 'chat_message' ||
                      (n.type == 'forum_reply' && n.payload['thread_id'] != null) ||
                      (n.payload['event_id'] != null && n.payload['cancelled'] != true);
                  final picked = selected?.contains(n.id) ?? false;
                  void toggle() => setState(() => picked ? selected!.remove(n.id) : selected!.add(n.id));
                  return ListTile(
                    key: ValueKey('notification_${n.id}'),
                    contentPadding: const EdgeInsets.only(left: 12, right: 4),
                    selected: picked,
                    tileColor: n.isRead ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                    leading: selecting
                        ? Checkbox(value: picked, onChanged: (_) => toggle())
                        : Icon(NotificationsDialog._icon(n.type),
                            color: n.isRead ? theme.hintColor : theme.colorScheme.primary),
                    title: Text(
                      n.message,
                      style: TextStyle(fontSize: 13, fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600),
                    ),
                    subtitle: Text(DateTimeFormatter.timeAgo(n.createdAt), style: const TextStyle(fontSize: 11)),
                    trailing: selecting
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (opens) Icon(Icons.chevron_right_rounded, color: theme.hintColor),
                              IconButton(
                                tooltip: 'Remove',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.close_rounded, size: 18, color: theme.hintColor),
                                onPressed: _busy ? null : () => _delete([n.id]),
                              ),
                            ],
                          ),
                    onTap: selecting ? toggle : () => NotificationsDialog.open(context, ref, n),
                    onLongPress: selecting ? null : () => setState(() => _selected = {n.id}),
                  );
                },
              );
            },
          ),
        ),
        actions: selecting
            ? [
                TextButton(onPressed: () => setState(() => _selected = null), child: const Text('Cancel')),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: selected.isEmpty || _busy ? null : () => _delete(selected.toList()),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(selected.isEmpty ? 'Delete' : 'Delete ${selected.length}'),
                ),
              ]
            : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}
