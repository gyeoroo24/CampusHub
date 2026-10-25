import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/web_history_support.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../../lost_found/domain/lost_found_item.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../../lost_found/ui/widgets/lost_found_detail_dialog.dart';
import '../domain/alerts_models.dart';
import '../providers/alerts_providers.dart';
import 'saved_searches_dialog.dart';

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

class NotificationsDialog extends ConsumerWidget {
  const NotificationsDialog({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsCountProvider);
    final theme = Theme.of(context);

    return ModalHistoryWrapper(
      child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      title: Row(
        children: [
          const Icon(Icons.notifications_rounded),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (unread > 0)
            TextButton(
              onPressed: () async {
                await ref.read(alertsRepositoryProvider).markAllRead();
                ref.invalidate(notificationsProvider);
              },
              child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
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
                    'Nothing yet. Save a search or post a Wanted request, and matches will show up here.',
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
                final opens = n.listingId != null || n.foundReportId != null;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  tileColor: n.isRead ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                  leading: Icon(_icon(n.type), color: n.isRead ? theme.hintColor : theme.colorScheme.primary),
                  title: Text(
                    n.message,
                    style: TextStyle(fontSize: 13, fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600),
                  ),
                  subtitle: Text(DateTimeFormatter.timeAgo(n.createdAt), style: const TextStyle(fontSize: 11)),
                  trailing: opens ? const Icon(Icons.chevron_right_rounded) : null,
                  onTap: () => open(context, ref, n),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showDialog(context: context, builder: (_) => const SavedSearchesDialog());
          },
          icon: const Icon(Icons.saved_search_rounded, size: 18),
          label: const Text('Saved searches'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ));
  }
}
