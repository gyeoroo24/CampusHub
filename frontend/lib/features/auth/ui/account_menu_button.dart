import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_providers.dart';
import 'auth_dialog.dart';

/// App-bar account control. Guests get a labelled "Sign in" button; signed-in users get a menu
/// with their profile, their admin or moderation tools (if any) and "Sign out".
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
    final panelLabel = user.isAdmin ? 'Admin panel' : user.isModerator ? 'Moderation tools' : null;

    return PopupMenuButton<String>(
      tooltip: 'Your account',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        switch (value) {
          case 'profile':
            context.push('/profile');
          case 'panel':
            context.push('/admin');
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
        if (panelLabel != null)
          PopupMenuItem(
            value: 'panel',
            child: ListTile(
              leading: Icon(user.isAdmin ? Icons.admin_panel_settings_outlined : Icons.shield_outlined),
              title: Text(panelLabel),
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
