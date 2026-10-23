import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
