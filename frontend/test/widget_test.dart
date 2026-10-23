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
    expect(find.text('Buy & Sell Portal'), findsOneWidget);
  });

  testWidgets('CampusHub mobile responsiveness test (iPhone SE 375x667)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const ProviderScope(child: CampusHubApp()));
    await tester.pumpAndSettle();

    // Verify title and Sell button on mobile
    expect(find.text('CampusHub'), findsWidgets);
    expect(find.text('Buy & Sell'), findsWidgets);
    expect(find.text('Sell'), findsOneWidget);

    // Switch to Lost & Found on bottom nav
    final lnfTab = find.byIcon(Icons.find_in_page_outlined);
    expect(lnfTab, findsOneWidget);
    await tester.tap(lnfTab);
    await tester.pumpAndSettle();

    expect(find.text('Lost & Found Portal'), findsOneWidget);
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
}
