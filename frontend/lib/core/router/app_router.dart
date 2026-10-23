import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/super_search_bar.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/ui/auth_dialog.dart';
import '../../features/buy_sell/ui/buy_sell_feed_screen.dart';
import '../../features/lost_found/ui/lost_found_feed_screen.dart';

// ---------------------------------------------------------------------------
// Tab index provider — drives in-app tab switching WITHOUT browser history
// ---------------------------------------------------------------------------
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// GoRouter — single shell route, no per-tab routes, no history entries
// ---------------------------------------------------------------------------
final GoRouter appRouter = GoRouter(
  initialLocation: '/app',
  routes: [
    ShellRoute(
      builder: (context, state, child) => child,
      routes: [
        GoRoute(
          path: '/app',
          builder: (context, state) => const AppShellLayout(),
        ),
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Tab definitions
// ---------------------------------------------------------------------------
const _tabDestinations = [
  (
    icon: Icons.shopping_bag_outlined,
    selectedIcon: Icons.shopping_bag,
    label: 'Buy & Sell',
  ),
  (
    icon: Icons.find_in_page_outlined,
    selectedIcon: Icons.find_in_page,
    label: 'Lost & Found',
  ),
];

const _tabScreens = [
  BuySellFeedScreen(),
  LostFoundFeedScreen(),
];

// ---------------------------------------------------------------------------
// Theme toggle button
// ---------------------------------------------------------------------------
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return IconButton(
      tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () {
        ref.read(themeModeProvider.notifier).state =
            isDark ? ThemeMode.light : ThemeMode.dark;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shell layout
// ---------------------------------------------------------------------------
class AppShellLayout extends ConsumerStatefulWidget {
  const AppShellLayout({super.key});

  @override
  ConsumerState<AppShellLayout> createState() => _AppShellLayoutState();
}

class _AppShellLayoutState extends ConsumerState<AppShellLayout>
    with SingleTickerProviderStateMixin {
  // Animation controller for vertical slide between tabs
  late final AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_animController);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _switchTab(int newIndex) {
    final currentIndex = ref.read(tabIndexProvider);
    if (newIndex == currentIndex) return;

    // Going from index 0→1 means slide UP (new screen comes from below)
    // Going from index 1→0 means slide DOWN (new screen comes from above)
    final bool goingDown = newIndex < currentIndex;

    // Reset and start: new screen enters from below/above
    _slideAnimation = Tween<Offset>(
      begin: goingDown ? const Offset(0, -1) : const Offset(0, 1),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeInOutCubic)).animate(_animController);

    ref.read(tabIndexProvider.notifier).state = newIndex;
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(tabIndexProvider);
    final isDesktop = MediaQuery.of(context).size.width > 750;
    final currentUser = ref.watch(currentUserProvider);
    final isGuest = currentUser == null || currentUser.isGuest;

    // Build the animated content area
    Widget content = SlideTransition(
      position: _slideAnimation,
      child: RepaintBoundary(
        child: _tabScreens[tabIndex],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Icon(Icons.school_rounded, color: Colors.indigo, size: 26),
            const SizedBox(width: 8),
            const Text(
              'CampusHub',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (isDesktop)
              const Text(
                ' | IISc',
                style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w400),
              ),
            const SizedBox(width: 16),
            if (isDesktop)
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: const SuperSearchBar(),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
          const SizedBox(width: 4),
          if (isDesktop)
            ActionChip(
              avatar: Icon(isGuest ? Icons.person_outline : Icons.person, size: 16),
              label: Text(isGuest ? 'Sign In' : currentUser.email),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
              onPressed: () {
                if (isGuest) {
                  AuthDialog.ensureSignedIn(context, ref);
                } else {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Account'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Logged in as:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(currentUser.email, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Roles: ${currentUser.roles.map((r) => r.name).join(", ")}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ref.read(authRepositoryProvider).signOut();
                          },
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                }
              },
            )
          else
            IconButton(
              tooltip: isGuest ? 'Sign In' : currentUser.email,
              icon: CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  isGuest ? Icons.person_outline : Icons.person,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              onPressed: () {
                if (isGuest) {
                  AuthDialog.ensureSignedIn(context, ref);
                } else {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Account'),
                      content: Text('Logged in as:\n${currentUser.email}'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ref.read(authRepositoryProvider).signOut();
                          },
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (!isDesktop)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SuperSearchBar(),
            ),
          Expanded(
            child: Row(
              children: [
                if (isDesktop)
                  NavigationRail(
                    selectedIndex: tabIndex,
                    onDestinationSelected: _switchTab,
                    labelType: NavigationRailLabelType.all,
                    useIndicator: true,
                    indicatorColor: Theme.of(context).colorScheme.primaryContainer,
                    destinations: [
                      for (final dest in _tabDestinations)
                        NavigationRailDestination(
                          icon: Icon(dest.icon),
                          selectedIcon: Icon(dest.selectedIcon),
                          label: Text(dest.label),
                        ),
                    ],
                  ),
                if (isDesktop) const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: ClipRect(child: content),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: tabIndex,
              onTap: _switchTab,
              items: [
                for (final dest in _tabDestinations)
                  BottomNavigationBarItem(
                    icon: Icon(dest.icon),
                    label: dest.label,
                  ),
              ],
            ),
    );
  }
}
