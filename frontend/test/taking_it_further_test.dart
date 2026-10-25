// Saved searches & alerts, Wanted posts, campus services and the course survival guide
// (backend rev 6, "Taking it further").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_hub/features/academics/data/academics_repository.dart';
import 'package:campus_hub/features/academics/domain/academics_models.dart';
import 'package:campus_hub/features/academics/providers/academics_providers.dart';
import 'package:campus_hub/features/academics/ui/course_guide_screen.dart';
import 'package:campus_hub/features/academics/ui/sentiment_trend_chart.dart';
import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/providers/auth_providers.dart';
import 'package:campus_hub/features/alerts/data/alerts_repository.dart';
import 'package:campus_hub/features/alerts/domain/alerts_models.dart';
import 'package:campus_hub/features/buy_sell/data/mock_buy_sell_repository.dart';
import 'package:campus_hub/features/buy_sell/providers/buy_sell_providers.dart';
import 'package:campus_hub/features/campus_services/data/campus_services_repository.dart';
import 'package:campus_hub/features/campus_services/domain/campus_service.dart';
import 'package:campus_hub/features/campus_services/ui/campus_services_dialog.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/providers/lost_found_providers.dart';
import 'package:campus_hub/features/wanted/data/wanted_repository.dart';
import 'package:campus_hub/features/wanted/domain/wanted_post.dart';
import 'package:campus_hub/main.dart';

void main() {
  setUp(() {
    MockAlertsRepository.resetMockData();
    MockWantedRepository.resetMockData();
    MockCampusServicesRepository.resetMockData();
  });

  group('Parsing backend responses', () {
    test('SavedSearch reads the API shape and describes its filters', () {
      final s = SavedSearch.fromJson({
        'id': 'a1', 'module': 'buy_sell', 'name': 'Cycle under ₹3,000', 'q': 'cycle', 'category_id': 4,
        'category_name': 'Cycles', 'min_price': null, 'max_price': '3000.00', 'alerts_enabled': true,
        'new_count': 2, 'last_seen_at': '2026-10-20T10:00:00Z', 'created_at': '2026-10-01T10:00:00Z',
        'updated_at': '2026-10-20T10:00:00Z',
      });
      expect(s.module, SavedSearchModule.buySell);
      expect(s.maxPrice, 3000);
      expect(s.newCount, 2);
      expect(s.filterSummary, '“cycle” · Cycles · up to ₹3,000');
      expect(describeFilters(), 'Everything new');
      expect(describeFilters(minPrice: 500, maxPrice: 12000), '₹500 – ₹12,000');
    });

    test('AppNotification exposes where tapping goes', () {
      final n = AppNotification.fromJson({
        'id': 'n', 'type': 'wanted_post_match', 'is_read': false, 'created_at': '2026-10-24T10:00:00Z',
        'payload': {'listing_id': 'L1', 'wanted_post_id': 'W1', 'message': 'Someone listed a cycle'},
      });
      expect(n.listingId, 'L1');
      expect(n.foundReportId, isNull);
      expect(n.message, 'Someone listed a cycle');
      expect(n.markedRead().isRead, isTrue);
    });

    test('WantedPost reads budget, contact and possible matches', () {
      final post = WantedPost.fromJson({
        'id': 'w', 'title': 'Need a Hero cycle', 'description': null, 'category': {'id': 4, 'name': 'Cycles'},
        'max_price': null, 'status': 'fulfilled', 'author': {'id': 'u', 'name': 'Ravi'},
        'author_contact': {'email': 'ravi@iisc.ac.in', 'phone': null}, 'created_at': '2026-10-24T10:00:00Z',
        'updated_at': '2026-10-24T10:00:00Z',
        'possible_matches': [
          {
            'id': 'l', 'title': 'Hero Sprint', 'price': '2500.00', 'status': 'available', 'location': 'N Block',
            'category': {'id': 4, 'name': 'Cycles'}, 'seller': {'id': 's', 'name': 'Asha'},
            'cover_photo_url': null, 'created_at': '2026-10-24T09:00:00Z',
          },
        ],
      });
      expect(post.status, WantedStatus.fulfilled);
      expect(post.budgetLabel, 'Open to offers');
      expect(post.authorContact?.email, 'ravi@iisc.ac.in');
      expect(post.possibleMatches.single.price, 2500);
    });

    test('SurvivalGuide reads semesters, highlights and trend', () {
      final guide = SurvivalGuide.fromJson({
        'course': {'id': 'c', 'code': 'DS 252', 'name': 'Cloud Computing', 'department_id': 'd',
                   'department_name': 'CDS'},
        'feedback_count': 9, 'summary': 'Students are mixed about DS 252.', 'trend': 'improving',
        'overall': {'score': 0.1, 'label': 'mixed', 'positive_share': 0.4, 'negative_share': 0.3},
        'themes': [{'theme': 'workload', 'mentions': 4, 'score': -0.3, 'label': 'negative'}],
        'advice': ['Start the project early.'],
        'semesters': [
          {
            'term': 'Aug 2025', 'starts_on': '2025-08-01', 'in_progress': false, 'feedback_count': 9,
            'sentiment': {'score': 0.1, 'label': 'mixed', 'positive_share': 0.4, 'negative_share': 0.3},
            'top_themes': [], 'highlights': {'positive': 'Great TAs.', 'negative': null},
          },
        ],
        'method': 'lexicon', 'generated_at': '2026-10-24T10:00:00Z',
      });
      expect(guide.trend, GuideTrend.improving);
      expect(guide.overall?.label, SentimentLabel.mixed);
      expect(guide.themes.single.label, SentimentLabel.negative);
      expect(guide.semesters.single.positiveQuote, 'Great TAs.');
      expect(guide.semesters.single.negativeQuote, isNull);
    });

    test('CampusService sends empty fields as null', () {
      const s = CampusService(id: 'x', name: 'Emergency', category: CampusServiceCategory.health,
          phone: '080-2293-4444', url: '', description: '');
      expect(s.toJson(), containsPair('url', null));
      expect(s.toJson(), containsPair('category', 'health'));
      expect(CampusService.fromJson({'id': 'y', 'name': 'n', 'category': 'unknown', 'url': 'https://x'}).category,
          CampusServiceCategory.other);
    });
  });

  group('Mock repositories', () {
    test('saved searches: create, mark seen, pause and delete', () async {
      final repo = MockAlertsRepository();
      final created = await repo.createSavedSearch(
          module: SavedSearchModule.lostFound, name: 'My ID card', query: '  ', categoryId: 3);
      expect(created.query, isNull);
      expect((await repo.fetchSavedSearches()).length, 2);
      expect((await repo.markSeen('ss_1')).newCount, 0);
      expect((await repo.updateSavedSearch(created.id, alertsEnabled: false)).alertsEnabled, isFalse);
      await repo.deleteSavedSearch(created.id);
      expect((await repo.fetchSavedSearches()).length, 1);
    });

    test('notifications: mark one and all read', () async {
      final repo = MockAlertsRepository();
      expect((await repo.fetchNotifications(unreadOnly: true)).length, 1);
      await repo.markRead('n_1');
      expect(await repo.fetchNotifications(unreadOnly: true), isEmpty);
    });

    test('Wanted: posting returns listings that already match, and fulfilled posts leave the feed', () async {
      final repo = MockWantedRepository();
      final post = await repo.createWanted(title: 'Need a lab coat', categoryId: 5, maxPrice: 500);
      expect(post.possibleMatches.map((l) => l.category.id).toSet(), {5});
      expect(post.possibleMatches.every((l) => l.price <= 500), isTrue);
      await repo.updateStatus(post.id, WantedStatus.fulfilled);
      expect((await repo.fetchWanted()).any((p) => p.id == post.id), isFalse);
      expect((await repo.fetchWanted(statuses: WantedStatus.values)).any((p) => p.id == post.id), isTrue);
    });

    test('campus services: hidden ones only with includeInactive, grouped by category', () async {
      final repo = MockCampusServicesRepository();
      final wellness = (await repo.fetchServices()).firstWhere((s) => s.name == 'Wellness Centre');
      await repo.updateService(wellness.copyWith(isActive: false));
      expect((await repo.fetchServices()).any((s) => s.name == 'Wellness Centre'), isFalse);
      final all = await repo.fetchServices(includeInactive: true);
      expect(all.map((s) => s.category.index).toList(), orderedEquals([...all.map((s) => s.category.index)]..sort()));
    });
  });

  group('Screens', () {
    Widget app({Widget? home, List<Override> overrides = const []}) => ProviderScope(
          overrides: [
            buySellRepositoryProvider.overrideWithValue(MockBuySellRepository()),
            lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
            academicsRepositoryProvider.overrideWithValue(MockAcademicsRepository()),
            ...overrides,
          ],
          child: home == null ? const CampusHubApp() : MaterialApp(home: home),
        );

    testWidgets('Buy & Sell switches to the Wanted feed and back', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Sell Item'), findsOneWidget);
      expect(find.byTooltip('Save this search & get alerts'), findsOneWidget);

      await tester.tap(find.text('Wanted'));
      await tester.pumpAndSettle();
      expect(find.text('Post Wanted'), findsOneWidget);
      expect(find.text('Looking for a cycle for campus rides'), findsOneWidget);

      await tester.tap(find.text('For sale'));
      await tester.pumpAndSettle();
      expect(find.text('Sell Item'), findsOneWidget);
    });

    testWidgets('A Wanted feed hidden by a category chip says so and can show everything', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wanted'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Furniture'));
      await tester.pumpAndSettle();
      expect(find.text('No Wanted requests match “Furniture”.'), findsOneWidget);

      await tester.tap(find.text('Show all Wanted requests'));
      await tester.pumpAndSettle();
      expect(find.text('Looking for a cycle for campus rides'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1)); // the mock listings feed reloads with a simulated delay
    });

    testWidgets('Campus services button lists services grouped by category', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CampusServicesButton));
      await tester.pumpAndSettle();
      expect(find.text('Campus services'), findsOneWidget);
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('Wellness Centre'), findsOneWidget);
      expect(find.text('080-2293-4444'), findsOneWidget);
    });

    testWidgets('Courses tab opens a course survival guide with the trend chart', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Courses'));
      await tester.pumpAndSettle();
      expect(find.text('Course survival guides'), findsOneWidget);
      await tester.tap(find.text('Cloud Computing'));
      await tester.pumpAndSettle();

      expect(find.byType(CourseGuideScreen), findsOneWidget);
      expect(find.byType(SentimentTrendChart), findsOneWidget);
      expect(find.textContaining('Students are mostly positive about DS 252'), findsOneWidget);
      expect(find.text('Improving'), findsOneWidget);
      expect(find.text('Start the project early.'), findsOneWidget);
    });

    testWidgets('A signed-in student writes, edits and deletes their one review', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(MockAcademicsRepository.resetMockData);
      final student = User(id: 'u1', email: 'asha@iisc.ac.in', name: 'Asha', createdAt: DateTime(2026));
      await tester.pumpWidget(app(
        home: const CourseGuideScreen(courseId: 'c_252'),
        overrides: [currentUserProvider.overrideWith((ref) => student), isGuestUserProvider.overrideWith((ref) => false)],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share your feedback'));
      await tester.pumpAndSettle();
      expect(find.text('How did this course go?'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Clear lectures.');
      await tester.tap(find.text('Post anonymously'));
      await tester.pump();
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();

      expect(find.text('Your review'), findsOneWidget);
      expect(find.text('posted anonymously'), findsOneWidget);
      expect(find.text('Share your feedback'), findsNothing); // one review per course

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Share your feedback'), findsOneWidget);
    });

    testWidgets('The feedback form fits a short phone screen', (tester) async {
      tester.view.physicalSize = const Size(375, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final student = User(id: 'u1', email: 'asha@iisc.ac.in', name: 'Asha', createdAt: DateTime(2026));
      await tester.pumpWidget(app(
        home: const CourseGuideScreen(courseId: 'c_221'),
        overrides: [currentUserProvider.overrideWith((ref) => student), isGuestUserProvider.overrideWith((ref) => false)],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share your feedback'));
      await tester.pumpAndSettle();
      expect(find.text('How did this course go?'), findsOneWidget); // and no overflow exception
    });

    testWidgets('A course with no feedback shows the empty guide', (tester) async {
      await tester.pumpWidget(app(home: const CourseGuideScreen(courseId: 'c_221')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No feedback on DS 221 yet'), findsOneWidget);
      expect(find.byType(SentimentTrendChart), findsNothing);
    });
  });
}
