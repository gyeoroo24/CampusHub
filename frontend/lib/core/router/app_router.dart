import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/server_config.dart';
import '../theme/app_theme.dart';
import '../widgets/super_search_bar.dart';
import '../../features/auth/domain/user.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/ui/auth_dialog.dart';
import '../../features/buy_sell/providers/buy_sell_providers.dart';
import '../../features/buy_sell/ui/buy_sell_feed_screen.dart';
import '../../features/lost_found/providers/lost_found_providers.dart';
import '../../features/lost_found/ui/lost_found_feed_screen.dart';
import '../../features/admin/providers/admin_providers.dart';
import '../../features/admin/ui/admin_controls_screen.dart';
import '../../features/profile/ui/user_profile_screen.dart';

// ---------------------------------------------------------------------------
// Tab index provider — drives in-app tab switching WITHOUT browser history
// ---------------------------------------------------------------------------
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// GoRouter — direct routes for /buy and /lost-found with clean path strategy
// ---------------------------------------------------------------------------
final GoRouter appRouter = GoRouter(
  initialLocation: '/buy',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) => '/buy',
    ),
    GoRoute(
      path: '/buy',
      builder: (context, state) => const AppShellLayout(initialTab: 0),
    ),
    GoRoute(
      path: '/lost-found',
      builder: (context, state) => const AppShellLayout(initialTab: 1),
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
      path: '/profile',
      builder: (context, state) => const UserProfileScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) {
        final tabParam = state.uri.queryParameters['tab'];
        final initialTab = tabParam != null ? int.tryParse(tabParam) : null;
        return AdminControlsScreen(initialTab: initialTab);
      },
    ),
  ],
  errorBuilder: (context, state) => const AppShellLayout(initialTab: 0),
);

// ---------------------------------------------------------------------------
// Tab definitions
// ---------------------------------------------------------------------------
const _tabDestinations = [
  (
    icon: Icons.shopping_bag_outlined,
    selectedIcon: Icons.shopping_bag_rounded,
    label: 'Buy & Sell',
  ),
  (
    icon: Icons.find_in_page_outlined,
    selectedIcon: Icons.find_in_page_rounded,
    label: 'Lost & Found',
  ),
];

const _tabScreens = [
  BuySellFeedScreen(),
  LostFoundFeedScreen(),
];

// ---------------------------------------------------------------------------
// App Refresh Button — Refetches all data and permissions from server
// ---------------------------------------------------------------------------
class AppRefreshButton extends ConsumerStatefulWidget {
  const AppRefreshButton({super.key});

  @override
  ConsumerState<AppRefreshButton> createState() => _AppRefreshButtonState();
}

class _AppRefreshButtonState extends ConsumerState<AppRefreshButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _controller.repeat();

    try {
      // 1. Refetch user profile & updated authority from backend
      await ref.read(authRepositoryProvider).getCurrentUser();
      ref.invalidate(authStateProvider);
      ref.invalidate(moderatorGrantsProvider);
      ref.invalidate(registeredUsersProvider);

      // 2. Refetch Buy & Sell feeds & categories
      ref.read(buySellPaginationProvider.notifier).loadInitial();
      ref.invalidate(buySellCategoriesProvider);

      // 3. Refetch Lost & Found feeds & categories
      ref.read(lostReportsPaginationProvider.notifier).loadInitial();
      ref.read(foundReportsPaginationProvider.notifier).loadInitial();
      ref.invalidate(lostFoundCategoriesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Text('All feeds and user permissions refreshed from server.'),
              ],
            ),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh data: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        _controller.stop();
        _controller.reset();
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: IconButton(
        tooltip: 'Refresh all data from server',
        icon: const Icon(Icons.refresh_rounded, size: 20),
        onPressed: _isRefreshing ? null : _handleRefresh,
      ),
    );
  }
}

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
// Shell layout
// ---------------------------------------------------------------------------
class AppShellLayout extends ConsumerStatefulWidget {
  final int initialTab;
  const AppShellLayout({super.key, this.initialTab = 0});

  @override
  ConsumerState<AppShellLayout> createState() => _AppShellLayoutState();
}

class _AppShellLayoutState extends ConsumerState<AppShellLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_animController);

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
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != ref.read(tabIndexProvider)) {
      _switchTab(widget.initialTab, updateUrl: false);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _switchTab(int newIndex, {bool updateUrl = true}) {
    final currentIndex = ref.read(tabIndexProvider);
    if (newIndex == currentIndex) return;

    final isDesktop = MediaQuery.of(context).size.width > 750;
    final bool goingForward = newIndex > currentIndex;

    final Offset beginOffset = isDesktop
        ? (goingForward ? const Offset(0, 0.08) : const Offset(0, -0.08))
        : (goingForward ? const Offset(0.12, 0) : const Offset(-0.12, 0));

    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_animController);

    ref.read(tabIndexProvider.notifier).state = newIndex;
    _animController.forward(from: 0);

    if (updateUrl) {
      context.go(newIndex == 0 ? '/buy' : '/lost-found');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(tabIndexProvider);
    final isDesktop = MediaQuery.of(context).size.width > 750;
    final currentUser = ref.watch(currentUserProvider);
    final serverConfig = ref.watch(serverConfigProvider);
    final isGuest = currentUser == null || currentUser.isGuest;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget content = SlideTransition(
      position: _slideAnimation,
      child: RepaintBoundary(
        child: _tabScreens[tabIndex],
      ),
    );

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
          const AppRefreshButton(),
          const SizedBox(width: 4),
          const ThemeToggleButton(),
          const SizedBox(width: 8),

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
          if (!isGuest && currentUser.isAdmin)
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
          else if (!isGuest && currentUser.isModerator)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.shield_outlined, size: 16, color: Colors.blue),
                label: const Text('Moderator', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => context.push('/admin'),
              ),
            ),

          // User Profile / Sign In Pill
          if (isDesktop)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (isGuest) {
                  AuthDialog.ensureSignedIn(context, ref);
                } else {
                  _showAccountDialog(context, currentUser);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isGuest
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        isGuest ? '?' : currentUser.name.isNotEmpty ? currentUser.name[0].toUpperCase() : 'U',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isGuest ? 'Sign In' : (currentUser.name.isNotEmpty ? currentUser.name : currentUser.email.split('@').first),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              tooltip: isGuest ? 'Sign In' : currentUser.email,
              icon: CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  isGuest ? Icons.person_outline_rounded : Icons.person_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              onPressed: () {
                if (isGuest) {
                  AuthDialog.ensureSignedIn(context, ref);
                } else {
                  _showAccountDialog(context, currentUser);
                }
              },
            ),
          const SizedBox(width: 16),
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
              currentIndex: tabIndex,
              onTap: _switchTab,
              selectedItemColor: theme.colorScheme.primary,
              items: [
                for (final dest in _tabDestinations)
                  BottomNavigationBarItem(
                    icon: Icon(dest.icon),
                    activeIcon: Icon(dest.selectedIcon),
                    label: dest.label,
                  ),
              ],
            ),
    );
  }

  void _showAccountDialog(BuildContext context, User currentUser) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleNames = currentUser.roles.map((r) => r.label).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                currentUser.initials,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentUser.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'IISc Campus Member',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.email_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentUser.email,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Permissions & Roles:', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: roleNames.map((role) {
                final isSpecial = role == 'Admin' || role == 'Moderator';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSpecial
                        ? (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE))
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSpecial
                          ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD))
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSpecial ? (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8)) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (currentUser.moderatorGrants.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Active Moderation Scopes:', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 6),
              for (final grant in currentUser.moderatorGrants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 14, color: Colors.blue.shade600),
                      const SizedBox(width: 6),
                      Text(
                        '${grant.module} (${grant.scopeType})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/profile');
                },
                icon: const Icon(Icons.person_outline_rounded, size: 16),
                label: const Text('Open Full Profile & My Postings'),
              ),
            ),
            if (currentUser.isAdmin) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded, size: 16, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  const Text('Admin Management Controls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/admin');
                  },
                  icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
                  label: const Text('Open Admin Controls Panel'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showDeactivateUserDialog(context);
                      },
                      icon: const Icon(Icons.person_off_outlined, size: 16),
                      label: const Text('Account Status', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showTransferAdminDialog(context);
                      },
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('Transfer Role', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ] else if (currentUser.isModerator) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  const Text('Moderator Controls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: isDark ? Colors.teal.shade200 : Colors.teal.shade900,
                    backgroundColor: isDark ? const Color(0xFF134E4A) : Colors.teal.shade50,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/admin');
                  },
                  icon: const Icon(Icons.shield_outlined, size: 16),
                  label: const Text('Open Moderator Controls'),
                ),
              ),
            ],
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
              ref.read(showTrustedExchangeBannerProvider.notifier).state = false;
              ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showDeactivateUserDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isActive = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.manage_accounts_rounded, color: Colors.indigo),
              SizedBox(width: 10),
              Text('Update Account Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the User UUID to activate or deactivate:'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'User UUID',
                  hintText: 'e.g. e3c8fb26-cee3-4c06...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('Account State: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ChoiceChip(
                    label: const Text('Active'),
                    selected: isActive,
                    onSelected: (val) => setState(() => isActive = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Deactivated'),
                    selected: !isActive,
                    onSelected: (val) => setState(() => isActive = false),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final userId = controller.text.trim();
                if (userId.isEmpty) return;
                try {
                  final status = await ref.read(authRepositoryProvider).updateAccountStatus(
                    userId,
                    isActive: isActive,
                  );
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('User ${status.name} is now ${status.isActive ? "active" : "deactivated"}.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransferAdminDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
            const SizedBox(width: 10),
            const Text('Transfer Admin Role', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Notice: CampusHub enforces a single-admin architecture. Once transferred, you will immediately be demoted to a standard student account.',
                style: TextStyle(color: Colors.red.shade900, fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Enter Successor User UUID:'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Successor User ID',
                hintText: 'e.g. f1d6ef8c-164b-438a...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              final targetId = controller.text.trim();
              if (targetId.isEmpty) return;
              try {
                final status = await ref.read(authRepositoryProvider).transferAdminRole(targetId);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Admin role transferred to ${status.name}. You are now a signed-in member.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to transfer: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Confirm Handover'),
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
