import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_hub/core/router/app_router.dart';
import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/providers/auth_providers.dart';
import 'package:campus_hub/features/buy_sell/data/mock_buy_sell_repository.dart';
import 'package:campus_hub/features/buy_sell/providers/buy_sell_providers.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/providers/lost_found_providers.dart';
import 'package:campus_hub/main.dart';

Widget createTestApp({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      buySellRepositoryProvider.overrideWithValue(MockBuySellRepository()),
      lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
      ...overrides,
    ],
    child: const CampusHubApp(),
  );
}

void main() {
  setUp(() {
    appRouter.go('/buy');
  });

  testWidgets('CampusHub desktop smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    expect(find.text('CampusHub'), findsWidgets);
    expect(find.text('Sell Item'), findsOneWidget);
  });

  testWidgets('CampusHub mobile responsiveness test (iPhone SE 375x667)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    // Verify search bar in AppBar on mobile and Sell FAB
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Sell Item'), findsOneWidget);

    // Switch to Lost & Found on bottom nav
    final lnfTab = find.byIcon(Icons.find_in_page_outlined);
    expect(lnfTab, findsOneWidget);
    await tester.tap(lnfTab);
    await tester.pumpAndSettle();

    // Compact tabs and FABs on mobile
    expect(find.text('Lost'), findsWidgets);
    expect(find.text('Found'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNWidgets(2));
  });

  testWidgets('Account menu shows profile and sign out; the admin panel is in the top bar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final testUser = User(
      id: 'test_admin',
      email: 'admin@iisc.ac.in',
      name: 'Adithya C',
      isAdmin: true,
      moderatorGrants: [
        ModeratorGrant(
          id: 'grant_1',
          module: 'buy_sell',
          scopeType: 'all',
          grantedAt: DateTime.now(),
        ),
      ],
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      createTestApp(
        overrides: [
          currentUserProvider.overrideWith((ref) => testUser),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The admin panel has its own button in the top bar, next to the account control.
    expect(find.text('Admin Panel'), findsOneWidget);

    // The account control in the app bar shows the user's name
    final accountButton = find.text('Adithya C');
    expect(accountButton, findsOneWidget);

    await tester.tap(accountButton);
    await tester.pumpAndSettle();

    // Menu: name, email and role, then the actions. No panel link here: it's the top-bar button.
    expect(find.text('admin@iisc.ac.in'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Admin panel'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);

    // Close the menu
    await tester.tapAt(const Offset(10, 600));
    await tester.pumpAndSettle();
    expect(find.text('admin@iisc.ac.in'), findsNothing);
  });

  testWidgets('Trusted Campus Exchange banner only shows when manually logged in and dismisses on x tap', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        buySellRepositoryProvider.overrideWithValue(MockBuySellRepository()),
        lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
        showTrustedExchangeBannerProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CampusHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // By default (persisted session or guest), banner is NOT shown
    expect(find.text('Trusted Campus Exchange'), findsNothing);

    // Simulate manual login: banner becomes visible
    container.read(showTrustedExchangeBannerProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(find.text('Trusted Campus Exchange'), findsOneWidget);

    // Tapping the 'x' button dismisses it
    final dismissBtn = find.byTooltip('Dismiss');
    expect(dismissBtn, findsOneWidget);
    await tester.tap(dismissBtn);
    await tester.pumpAndSettle();

    expect(find.text('Trusted Campus Exchange'), findsNothing);

    // The container outlives the widgets here: leaving the feed resets its filters, which reloads the
    // mock listings (simulated delay), so let that finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Lost & Found tab supports date presets and view mode toggle', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    // Switch to Lost & Found
    final lnfNav = find.text('Lost & Found');
    expect(lnfNav, findsOneWidget);
    await tester.tap(lnfNav);
    await tester.pumpAndSettle();

    // The date presets are in the Filters sheet, under "When"
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('When'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Any time'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Today'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Yesterday'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Last 3 Days'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'This Week'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'This Month'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'This Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(find.text('This Week'), findsWidgets);   // shown as an active-filter chip under the bar

    // Toggle view mode to Compact View
    final viewModeToggle = find.byTooltip('Compact view');
    expect(viewModeToggle, findsOneWidget);
    await tester.tap(viewModeToggle);
    await tester.pumpAndSettle();

    // Now tooltip changes to Large view
    expect(find.byTooltip('Large view'), findsOneWidget);
  });

  testWidgets('CampusHub mobile list view for both Buy & Sell and Lost & Found renders without overflows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    // In Buy & Sell, switch to Compact View on mobile
    final bnsListViewBtn = find.byTooltip('Compact view');
    expect(bnsListViewBtn, findsOneWidget);
    await tester.tap(bnsListViewBtn);
    await tester.pumpAndSettle();

    // Verify it switched without overflow
    expect(find.byTooltip('Large view'), findsOneWidget);

    // Switch to Lost & Found tab
    final lnfTab = find.byIcon(Icons.find_in_page_outlined);
    expect(lnfTab, findsOneWidget);
    await tester.tap(lnfTab);
    await tester.pumpAndSettle();

    // Switch to Compact View in LnF on mobile
    final lnfListViewBtn = find.byTooltip('Compact view');
    expect(lnfListViewBtn, findsOneWidget);
    await tester.tap(lnfListViewBtn);
    await tester.pumpAndSettle();

    // Verify LnF switched without overflow
    expect(find.byTooltip('Large view'), findsOneWidget);
  });

  testWidgets('Buy & Sell custom price range dialog opens and applies price filter', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    // The custom price range is in the Filters sheet, beside the Price presets
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    final priceRangeBtn = find.text('Custom range…');
    expect(priceRangeBtn, findsOneWidget);

    // Tap it to open dialog
    await tester.tap(priceRangeBtn);
    await tester.pumpAndSettle();

    // Check dialog components
    expect(find.text('Custom Price Range'), findsOneWidget);
    expect(find.text('Quick Budget Presets'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Under ₹500'), findsOneWidget);

    // Tap a preset chip in the dialog
    await tester.tap(find.widgetWithText(ActionChip, 'Under ₹500'));
    await tester.pumpAndSettle();

    // Tap Apply
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Dialog closed; apply the filters
    expect(find.text('Custom Price Range'), findsNothing);
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    // The feed shows the price filter as an active-filter chip
    expect(find.textContaining('₹500'), findsWidgets);
    expect(find.text('Filters'), findsNothing);   // the button now counts active filters
  });

  testWidgets('Lost & Found category row includes Report Lost and Report Found buttons', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    // Switch to Lost & Found
    final lnfNav = find.text('Lost & Found');
    expect(lnfNav, findsOneWidget);
    await tester.tap(lnfNav);
    await tester.pumpAndSettle();

    // Verify Report Lost and Report Found action buttons in category row
    expect(find.text('Report Lost'), findsOneWidget);
    expect(find.text('Report Found'), findsOneWidget);
  });
}
