import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../alerts/ui/saved_searches_dialog.dart';
import '../../messages/providers/messages_providers.dart';
import '../../seller_trust/ui/my_seller_strikes_dialog.dart';
import '../providers/auth_providers.dart';
import 'auth_dialog.dart';
import '../../buy_sell/ui/widgets/price_watch.dart';

/// App-bar account control. Guests get a labelled "Sign in" button; signed-in users get a menu
/// with their profile, messages, saved searches, their admin or moderation tools (if any) and "Sign out".
class AccountMenuButton extends ConsumerWidget {
  /// Phone layout: avatar only, no name.
  final bool compact;

  const AccountMenuButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    if (user == null || user.isGuest) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          onPressed: () => AuthDialog.ensureSignedIn(context, ref),
          icon: const Icon(Icons.login_rounded, size: 16),
          label: const Text('Sign in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );
    }

    final role = user.isAdmin ? 'Admin' : user.isModerator ? 'Moderator' : 'Student';
    final messagingAvailable = ref.watch(messagesRepositoryProvider) != null;
    final unreadMessages = messagingAvailable ? ref.watch(chatUnreadCountProvider).valueOrNull ?? 0 : 0;

    return PopupMenuButton<String>(
      tooltip: 'Your account',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        switch (value) {
          case 'profile':
            context.push('/profile');
          case 'messages':
            context.go('/messages');
          case 'saved':
            showDialog(context: context, builder: (_) => const SavedSearchesDialog());
          case 'strikes':
            showDialog(context: context, builder: (_) => const MySellerStrikesDialog());
          case 'watched':
            showDialog(context: context, builder: (_) => const WatchedListingsDialog());
          case 'signout':
            ref.read(showTrustedExchangeBannerProvider.notifier).state = false;
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) context.go('/buy');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Signed out.'), behavior: SnackBarBehavior.floating),
              );
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName,
                  style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              Text(user.email, style: TextStyle(fontSize: 12, color: theme.hintColor)),
              const SizedBox(height: 4),
              Text(role, style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'profile',
          child: ListTile(
            leading: Icon(Icons.person_outline_rounded),
            title: Text('My profile'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (messagingAvailable)
          PopupMenuItem(
            value: 'messages',
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('My messages'),
              trailing: unreadMessages > 0
                  ? Badge(label: Text(unreadMessages > 99 ? '99+' : '$unreadMessages'))
                  : null,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'saved',
          child: ListTile(
            leading: Icon(Icons.saved_search_rounded),
            title: Text('Saved searches'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'watched',
          child: ListTile(
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('Watched listings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'strikes',
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Seller strikes'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: Text(user.initials,
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(user.displayName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
            const Icon(Icons.arrow_drop_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
