import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/providers/auth_providers.dart';
import 'package:campus_hub/main.dart';

void main() {
  testWidgets('CampusHub desktop smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const ProviderScope(child: CampusHubApp()));
    await tester.pumpAndSettle();

    expect(find.text('CampusHub'), findsWidgets);
    expect(find.text('Sell Item'), findsOneWidget);
  });

  testWidgets('CampusHub mobile responsiveness test (iPhone SE 375x667)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const ProviderScope(child: CampusHubApp()));
    await tester.pumpAndSettle();

    // Verify title and Sell button on mobile
    expect(find.text('CampusHub'), findsWidgets);
    expect(find.text('Sell'), findsOneWidget);

    // Switch to Lost & Found on bottom nav
    final lnfTab = find.byIcon(Icons.find_in_page_outlined);
    expect(lnfTab, findsOneWidget);
    await tester.tap(lnfTab);
    await tester.pumpAndSettle();

    expect(find.text('Lost Items'), findsWidgets);
    expect(find.text('Found Items'), findsWidgets);
  });

  testWidgets('CampusHub user profile account dialog renders without error', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final testUser = User(
      id: 'test_student',
      email: 'student@iisc.ac.in',
      name: 'Adithya C',
      isAdmin: false,
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
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => testUser),
        ],
        child: const CampusHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Find user profile pill button in app bar
    final profileButton = find.text('Adithya C');
    expect(profileButton, findsOneWidget);

    // Tap it to open account dialog
    await tester.tap(profileButton);
    await tester.pumpAndSettle();

    // Verify account dialog is displayed with email and roles without any crash
    expect(find.text('student@iisc.ac.in'), findsOneWidget);
    expect(find.text('Permissions & Roles:'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Moderator'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);

    // Close the dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('student@iisc.ac.in'), findsNothing);
  });

  testWidgets('Trusted Campus Exchange banner only shows when manually logged in and dismisses on x tap', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
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
  });

  testWidgets('Lost & Found tab supports date presets and view mode toggle', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const ProviderScope(
        child: CampusHubApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Lost & Found
    final lnfNav = find.text('Lost & Found');
    expect(lnfNav, findsOneWidget);
    await tester.tap(lnfNav);
    await tester.pumpAndSettle();

    // Check date preset filter chips are visible
    expect(find.widgetWithText(FilterChip, 'All'), findsWidgets);
    expect(find.widgetWithText(FilterChip, 'Today'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Yesterday'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Last 3 Days'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'This Week'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'This Month'), findsOneWidget);

    // Toggle view mode to List View
    final viewModeToggle = find.byTooltip('List View');
    expect(viewModeToggle, findsOneWidget);
    await tester.tap(viewModeToggle);
    await tester.pumpAndSettle();

    // Now tooltip changes to Grid View
    expect(find.byTooltip('Grid View'), findsOneWidget);
  });

  testWidgets('CampusHub mobile list view for both Buy & Sell and Lost & Found renders without overflows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const ProviderScope(child: CampusHubApp()));
    await tester.pumpAndSettle();

    // In Buy & Sell, switch to List View on mobile
    final bnsListViewBtn = find.byTooltip('List View');
    expect(bnsListViewBtn, findsOneWidget);
    await tester.tap(bnsListViewBtn);
    await tester.pumpAndSettle();

    // Verify it switched without overflow
    expect(find.byTooltip('Grid View'), findsOneWidget);

    // Switch to Lost & Found tab
    final lnfTab = find.byIcon(Icons.find_in_page_outlined);
    expect(lnfTab, findsOneWidget);
    await tester.tap(lnfTab);
    await tester.pumpAndSettle();

    // Switch to List View in LnF on mobile
    final lnfListViewBtn = find.byTooltip('List View');
    expect(lnfListViewBtn, findsOneWidget);
    await tester.tap(lnfListViewBtn);
    await tester.pumpAndSettle();

    // Verify LnF switched without overflow
    expect(find.byTooltip('Grid View'), findsOneWidget);
  });

  testWidgets('Buy & Sell custom price range dialog opens and applies price filter', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const ProviderScope(child: CampusHubApp()));
    await tester.pumpAndSettle();

    // Verify custom price range button exists
    final priceRangeBtn = find.byTooltip('Pick Custom Price Range');
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

    // Dialog closed
    expect(find.text('Custom Price Range'), findsNothing);
    // Button now shows active filter tooltip
    expect(find.byTooltip('Custom: ₹0 - ₹500'), findsOneWidget);
  });

  testWidgets('Lost & Found category row includes Report Lost and Report Found buttons', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const ProviderScope(child: CampusHubApp()));
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
