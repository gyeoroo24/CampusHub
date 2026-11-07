import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/server_config.dart';
import '../theme/app_theme.dart';
import '../widgets/super_search_bar.dart';
import '../../features/auth/domain/user.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/ui/account_menu_button.dart';
import '../../features/buy_sell/domain/buy_sell_item.dart';
import '../../features/buy_sell/ui/buy_sell_feed_screen.dart';
import '../../features/buy_sell/ui/listing_links.dart';
import '../../features/lost_found/ui/lost_found_feed_screen.dart';
import '../../features/admin/ui/admin_controls_screen.dart';
import '../../features/profile/ui/user_profile_screen.dart';
import '../../features/academics/ui/course_guide_screen.dart';
import '../../features/academics/ui/courses_screen.dart';
import '../../features/alerts/ui/notifications_button.dart';
import '../../features/messages/ui/messages_screen.dart';
import '../../features/campus_services/ui/campus_services_dialog.dart';
import '../../features/events/providers/events_providers.dart';
import '../../features/events/ui/event_dialogs.dart';
import '../../features/events/ui/events_screen.dart';
import '../../features/mess/ui/mess_screen.dart';
import '../../features/placement/ui/company_screen.dart';
import '../../features/placement/ui/placement_screen.dart';

// ---------------------------------------------------------------------------
// Tab index provider — drives in-app tab switching WITHOUT browser history
// ---------------------------------------------------------------------------
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// GoRouter — direct routes for /buy and /lost-found with clean path strategy
// ---------------------------------------------------------------------------
// The tabs share one page (same key), so switching tabs updates the shell in place instead
// of building a new page with a route transition.
const _shellPageKey = ValueKey('app-shell');
// Same idea for the inbox and an open conversation: opening a chat swaps the pane, no slide.
const _messagesPageKey = ValueKey('messages');

/// For dialogs raised outside the routed widget tree (e.g. SessionKeeper, which wraps
/// MaterialApp.router's `builder` and so sits above the Router/Navigator it builds, not inside it).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/buy',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) => '/buy',
    ),
    GoRoute(
      path: '/buy',
      pageBuilder: (context, state) => const NoTransitionPage(key: _shellPageKey, child: AppShellLayout(initialTab: 0)),
      routes: [
        // One listing's shareable address: its dialog over the feed (see listing_links.dart).
        GoRoute(
          path: ':id',
          pageBuilder: (context, state) => ListingDialogPage(
            key: state.pageKey,
            listingId: state.pathParameters['id']!,
            summary: state.extra is ListingItem ? state.extra as ListingItem : null,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/lost-found',
      pageBuilder: (context, state) => const NoTransitionPage(key: _shellPageKey, child: AppShellLayout(initialTab: 1)),
    ),
    // Aliases and subpath redirects
    GoRoute(
      path: '/app',
      redirect: (_, __) => '/buy',
    ),
    GoRoute(
      path: '/app/:subpath',
      redirect: (context, state) {
        final sub = (state.pathParameters['subpath'] ?? '').toLowerCase();
        if (sub.contains('lost') || sub.contains('lnf') || sub.contains('found')) {
          return '/lost-found';
        }
        return '/buy';
      },
    ),
    GoRoute(
      path: '/buy-sell',
      redirect: (_, __) => '/buy',
    ),
    GoRoute(
      path: '/lost_found',
      redirect: (_, __) => '/lost-found',
    ),
    GoRoute(
      path: '/lnf',
      redirect: (_, __) => '/lost-found',
    ),
    GoRoute(
      path: '/courses',
      pageBuilder: (context, state) => const NoTransitionPage(key: _shellPageKey, child: AppShellLayout(initialTab: 2)),
    ),
    GoRoute(
      path: '/courses/:id',
      builder: (context, state) => CourseGuideScreen(courseId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/placements',
      pageBuilder: (context, state) => const NoTransitionPage(key: _shellPageKey, child: AppShellLayout(initialTab: 3)),
    ),
    GoRoute(
      path: '/placements/:id',
      builder: (context, state) =>
          CompanyScreen(companyId: state.pathParameters['id']!, initialTab: state.uri.queryParameters['tab']),
    ),
    GoRoute(
      path: '/placement',
      redirect: (_, __) => '/placements',
    ),
    GoRoute(
      path: '/events',
      pageBuilder: (context, state) => const NoTransitionPage(key: _shellPageKey, child: AppShellLayout(initialTab: 4)),
    ),
    GoRoute(
      path: '/events/:id',
      builder: (context, state) => EventDetailScreen(eventId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/mess',
      builder: (context, state) => MessScreen(initialMessId: int.tryParse(state.uri.queryParameters['mess'] ?? '')),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const UserProfileScreen(),
    ),
    GoRoute(
      path: '/messages',
      pageBuilder: (context, state) => const NoTransitionPage(key: _messagesPageKey, child: MessagesScreen()),
    ),
    GoRoute(
      path: '/messages/:id',
      pageBuilder: (context, state) => NoTransitionPage(
        key: _messagesPageKey,
        child: MessagesScreen(
            conversationId: state.pathParameters['id'], topicId: state.uri.queryParameters['topic']),
      ),
    ),
    // Admins use /admin; moderators /moderator (the screen moves anyone on the wrong one).
    for (final path in ['/admin', '/moderator'])
      GoRoute(
        path: path,
        builder: (context, state) {
          final tabParam = state.uri.queryParameters['tab'];
          final initialTab = tabParam != null ? int.tryParse(tabParam) : null;
          return AdminControlsScreen(initialTab: initialTab, path: path);
        },
      ),
  ],
  errorBuilder: (context, state) => const AppShellLayout(initialTab: 0),
);

// ---------------------------------------------------------------------------
// Tab definitions
// ---------------------------------------------------------------------------
// shortLabel: for the phone's bottom bar, where five labels share ~75px each.
const _tabDestinations = [
  (
    icon: Icons.shopping_bag_outlined,
    selectedIcon: Icons.shopping_bag_rounded,
    label: 'Buy & Sell',
    shortLabel: 'Buy & Sell',
  ),
  (
    icon: Icons.find_in_page_outlined,
    selectedIcon: Icons.find_in_page_rounded,
    label: 'Lost & Found',
    shortLabel: 'Lost & Found',
  ),
  (
    icon: Icons.school_outlined,
    selectedIcon: Icons.school_rounded,
    label: 'Courses',
    shortLabel: 'Courses',
  ),
  (
    icon: Icons.work_outline_rounded,
    selectedIcon: Icons.work_rounded,
    label: 'Placement Hub',
    shortLabel: 'Placements',
  ),
  (
    icon: Icons.event_outlined,
    selectedIcon: Icons.event_rounded,
    label: 'Events',
    shortLabel: 'Events',
  ),
];

const _tabPaths = ['/buy', '/lost-found', '/courses', '/placements', '/events'];

const _tabScreens = [
  BuySellFeedScreen(),
  LostFoundFeedScreen(),
  CoursesScreen(),
  PlacementScreen(),
  EventsScreen(),
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
      icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 20),
      onPressed: () {
        ref.read(themeModeProvider.notifier).state =
            isDark ? ThemeMode.light : ThemeMode.dark;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Phone overflow menu: campus services, theme, admin / moderator panel
// ---------------------------------------------------------------------------
class _MobileMoreMenu extends ConsumerWidget {
  final User? currentUser;

  const _MobileMoreMenu({required this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final user = currentUser;
    final panel = user == null
        ? null
        : user.isAdmin
            ? 'Admin Panel'
            : user.isModerator
                ? 'Moderator Panel'
                : null;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'services':
            showDialog(context: context, builder: (_) => const CampusServicesDialog());
          case 'theme':
            ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
          case 'panel':
            context.push(user!.controlsPath);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'services',
          child: ListTile(
            leading: Icon(Icons.health_and_safety_outlined),
            title: Text('Campus services'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            leading: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            title: Text(isDark ? 'Light mode' : 'Dark mode'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (panel != null)
          PopupMenuItem(
            value: 'panel',
            child: ListTile(
              leading: Icon(user!.isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_outlined),
              title: Text(panel),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shell layout
// ---------------------------------------------------------------------------
class AppShellLayout extends ConsumerStatefulWidget {
  final int initialTab;
  const AppShellLayout({super.key, this.initialTab = 0});

  @override
  ConsumerState<AppShellLayout> createState() => _AppShellLayoutState();
}

class _AppShellLayoutState extends ConsumerState<AppShellLayout> {
  @override
  void initState() {
    super.initState();
    // Sync tab with initialTab on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(tabIndexProvider) != widget.initialTab) {
        ref.read(tabIndexProvider.notifier).state = widget.initialTab;
      }
    });
  }

  @override
  void didUpdateWidget(AppShellLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The URL changed (e.g. browser back): show that tab. Providers can't change during a build.
    if (widget.initialTab != oldWidget.initialTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(tabIndexProvider) != widget.initialTab) {
          ref.read(tabIndexProvider.notifier).state = widget.initialTab;
        }
      });
    }
  }

  void _switchTab(int newIndex, {bool updateUrl = true}) {
    final currentIndex = ref.read(tabIndexProvider);
    if (newIndex == currentIndex) return;

    // No slide animation: tabs switch instantly.
    ref.read(tabIndexProvider.notifier).state = newIndex;

    if (updateUrl) {
      context.go(_tabPaths[newIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(tabIndexProvider);
    ref.watch(guestBookmarkSyncProvider); // moves a guest's saved events to their account at sign-in
    final isDesktop = MediaQuery.of(context).size.width > 750;
    final currentUser = ref.watch(currentUserProvider);
    final serverConfig = ref.watch(serverConfigProvider);
    final isGuest = currentUser == null || currentUser.isGuest;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget content = RepaintBoundary(child: _tabScreens[tabIndex]);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isDesktop ? 20 : 16,
        elevation: 0,
        backgroundColor: theme.cardColor,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            height: 1,
          ),
        ),
        title: isDesktop
            ? Row(
                children: [
                  // Campus Logo
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'CampusHub',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.5),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'IISc Bangalore',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: const SuperSearchBar(),
                      ),
                    ),
                  ),
                ],
              )
            : const SuperSearchBar(),
        actions: [
          if (isDesktop) const CampusServicesButton(),
          const MessagesButton(),
          const NotificationsButton(),
          if (isDesktop) ...[
            const SizedBox(width: 4),
            const ThemeToggleButton(),
            const SizedBox(width: 8),
          ] else
            // Phones: campus services, theme and the admin/moderator panel share one menu,
            // so the search box keeps its width.
            _MobileMoreMenu(currentUser: isGuest ? null : currentUser),

          // Server Connection Mode Badge (Admin only)
          if (!isGuest && currentUser.isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push('/admin?tab=4'),
                child: Tooltip(
                  message: serverConfig.useMockData
                      ? 'Mock In-Memory Mode active. Click to configure live teammate backend.'
                      : 'Live Backend: ${serverConfig.baseUrl}. Click to configure connection.',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: serverConfig.useMockData
                          ? (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9))
                          : const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: serverConfig.useMockData
                            ? (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1))
                            : const Color(0xFF10B981),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: serverConfig.useMockData ? Colors.amber : const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          serverConfig.useMockData
                              ? 'Mock Mode'
                              : 'Live: ${_formatHost(serverConfig.baseUrl)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: serverConfig.useMockData
                                ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Admin Controls Quick Access
          if (isDesktop && !isGuest && currentUser.isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.admin_panel_settings_rounded, size: 16, color: Colors.red),
                label: const Text('Admin Panel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => context.push('/admin'),
              ),
            )
          else if (isDesktop && !isGuest && currentUser.isModerator)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.shield_outlined, size: 16, color: Colors.blue),
                label: const Text('Moderator', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => context.push('/moderator'),
              ),
            ),

          // Account: Sign in for guests; profile, tools and Sign out for signed-in users
          AccountMenuButton(compact: !isDesktop),
          SizedBox(width: isDesktop ? 16 : 4),
        ],
      ),
      body: Row(
        children: [
          // Desktop Navigation Rail with Modern Pill Highlights
          if (isDesktop)
            NavigationRail(
              selectedIndex: tabIndex,
              onDestinationSelected: _switchTab,
              labelType: NavigationRailLabelType.all,
              useIndicator: true,
              indicatorColor: theme.colorScheme.primaryContainer,
              minWidth: 78,
              destinations: [
                for (final dest in _tabDestinations)
                  NavigationRailDestination(
                    icon: Icon(dest.icon),
                    selectedIcon: Icon(dest.selectedIcon, color: theme.colorScheme.primary),
                    label: Text(dest.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  ),
              ],
            ),
          if (isDesktop)
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          Expanded(
            child: ClipRect(child: content),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              type: BottomNavigationBarType.fixed, // five tabs: keep every label visible
              selectedFontSize: 11,
              unselectedFontSize: 11,
              currentIndex: tabIndex,
              onTap: _switchTab,
              selectedItemColor: theme.colorScheme.primary,
              items: [
                for (final dest in _tabDestinations)
                  BottomNavigationBarItem(
                    icon: Icon(dest.icon),
                    activeIcon: Icon(dest.selectedIcon),
                    label: dest.shortLabel,
                    tooltip: dest.label,
                  ),
              ],
            ),
    );
  }


  String _formatHost(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }
      return url.replaceFirst(RegExp(r'^https?:\/\/'), '');
    } catch (_) {
      return url;
    }
  }
}
