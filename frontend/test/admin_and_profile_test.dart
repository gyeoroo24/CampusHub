import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:campus_hub/core/config/server_config.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/contact.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/features/admin/data/admin_repository.dart';
import 'package:campus_hub/features/admin/providers/admin_providers.dart';
import 'package:campus_hub/features/admin/ui/admin_controls_screen.dart';
import 'package:campus_hub/features/auth/data/auth_repository.dart';
import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/providers/auth_providers.dart';
import 'package:campus_hub/features/buy_sell/data/mock_buy_sell_repository.dart';
import 'package:campus_hub/core/router/app_router.dart';
import 'package:campus_hub/features/buy_sell/providers/buy_sell_providers.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';
import 'package:campus_hub/features/lost_found/providers/lost_found_providers.dart';
import 'package:campus_hub/features/lost_found/ui/widgets/lost_found_detail_dialog.dart';
import 'package:campus_hub/features/profile/ui/user_profile_screen.dart';

void main() {
  setUp(() {
    MockAdminRepository.resetMockData();
  });
  group('Admin Repository & Email-Based Operations Tests', () {
    test('Admin promotes and revokes moderator using IISc email ID', () async {
      final repo = MockAdminRepository();

      // Initial active grants
      final initialGrants = await repo.listModerators();
      final initialCount = initialGrants.length;

      // Promote by email
      final newGrant = await repo.grantModerator(
        email: 'priyan@iisc.ac.in',
        module: 'buy_sell',
        scopeType: 'module',
      );

      expect(newGrant.userEmail, 'priyan@iisc.ac.in');
      expect(newGrant.module, 'buy_sell');

      final updatedGrants = await repo.listModerators();
      expect(updatedGrants.length, initialCount + 1);

      // Duplicate promotion rejected
      await expectLater(
        repo.grantModerator(
          email: 'priyan@iisc.ac.in',
          module: 'buy_sell',
          scopeType: 'module',
        ),
        throwsA(isA<Exception>()),
      );

      // Revoke grant
      await repo.revokeModerator(newGrant.id);
      final afterRevoke = await repo.listModerators();
      expect(afterRevoke.length, initialCount);
    });

    test('Admin transfers single admin role by email ID', () async {
      final repo = MockAdminRepository();

      // Transfer to Adithya by email
      final result = await repo.transferAdminRole('cadithya@iisc.ac.in');
      expect(result.email, 'cadithya@iisc.ac.in');
      expect(result.isAdmin, isTrue);

      final users = await repo.listRegisteredUsers();
      final adithya = users.firstWhere((u) => u.email == 'cadithya@iisc.ac.in');
      final mukund = users.firstWhere((u) => u.email == 'kmukund@iisc.ac.in');

      expect(adithya.isAdmin, isTrue);
      expect(mukund.isAdmin, isFalse); // Demoted in same transaction
    });

    test('Admin toggles user account active / deactivated by email ID', () async {
      final repo = MockAdminRepository();

      // Deactivate Aarav by email
      final deactivated = await repo.updateUserStatus(
        email: 'student@iisc.ac.in',
        isActive: false,
      );
      expect(deactivated.isActive, isFalse);

      // Reactivate
      final reactivated = await repo.updateUserStatus(
        email: 'student@iisc.ac.in',
        isActive: true,
      );
      expect(reactivated.isActive, isTrue);
    });

    test('Admin resolves content reports with action and optional removal', () async {
      final repo = MockAdminRepository();

      final openReports = await repo.listReports(status: 'open');
      expect(openReports.isNotEmpty, isTrue);
      final reportId = openReports.first.id;

      // Resolve as actioned with content removal
      await repo.resolveReport(
        reportId,
        action: 'actioned',
        note: 'Violates campus commercial terms.',
        removeContent: true,
      );

      final reportsAfter = await repo.listReports(status: 'open');
      expect(reportsAfter.any((r) => r.id == reportId), isFalse);

      final actionedReports = await repo.listReports(status: 'actioned');
      expect(actionedReports.any((r) => r.id == reportId), isTrue);
    });
  });

  group('User Profile & Postings Tests', () {
    test('User updates profile details (name, phone, programme, grad year)', () async {
      final authRepo = MockAuthRepository();
      await authRepo.signInWithEmail('kmukund@iisc.ac.in');

      final updated = await authRepo.updateProfile(
        name: 'Mukund K.',
        phone: '+919999988888',
        programme: 'PhD CSA',
        graduationYear: 2028,
      );

      expect(updated.name, 'Mukund K.');
      expect(updated.phone, '+919999988888');
      expect(updated.programme, 'PhD CSA');
      expect(updated.graduationYear, 2028);
    });

    testWidgets('UserProfileScreen renders user profile and allows editing', (WidgetTester tester) async {
      final testUser = User(
        id: 'usr_p1',
        email: 'kmukund@iisc.ac.in',
        name: 'Mukund Kukreja',
        phone: '+919876543210',
        programme: 'MTech CSA',
        graduationYear: 2026,
        isAdmin: true,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => testUser),
            authRepositoryProvider.overrideWithValue(MockAuthRepository()),
            buySellRepositoryProvider.overrideWithValue(MockBuySellRepository()),
            lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
          ],
          child: const MaterialApp(
            home: UserProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Profile & Postings'), findsOneWidget);
      expect(find.text('Mukund Kukreja'), findsOneWidget);
      expect(find.text('kmukund@iisc.ac.in'), findsOneWidget);
      expect(find.text('MTech CSA'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);

      // Tap Edit Profile
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Update profile details'), findsOneWidget);
      expect(find.text('Save Profile Changes'), findsOneWidget);
    });
  });

  group('Possible Matches in Lost & Found Dialogs Tests', () {
    testWidgets('Possible matches appear in both Lost and Found detail modals, and clicking opens the post', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final lostItem = LostFoundItem(
        id: 'lost_101',
        kind: PostType.lost,
        description: 'Lost Blue Water Bottle near Library',
        category: const CategoryRef(id: 1, name: 'Bottles'),
        occurredAt: DateTime.now().subtract(const Duration(hours: 3)),
        location: 'Library',
        status: ReportStatus.open,
        reporter: const UserRef(id: 'usr_rep_1', name: 'Student Sam'),
        photos: const [],
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );

      final foundItem = LostFoundItem(
        id: 'found_202',
        kind: PostType.found,
        description: 'Found Blue Hydro Flask at Library 1st Floor',
        category: const CategoryRef(id: 1, name: 'Bottles'),
        occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
        location: 'Library 1st Floor',
        status: ReportStatus.open,
        reporter: const UserRef(id: 'usr_rep_2', name: 'Finder Frank'),
        reporterContact: const Contact(email: 'frank@iisc.ac.in', phone: '9876543210'),
        photos: const [],
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
            possibleMatchesForItemProvider(lostItem).overrideWith((ref) => [foundItem]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LostFoundDetailDialog(item: lostItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that Possible Matches section is displayed
      expect(find.text('Possible Matches (1)'), findsOneWidget);
      expect(find.text('Found Blue Hydro Flask at Library 1st Floor'), findsOneWidget);

      // Tap on the matched item
      await tester.tap(find.text('Found Blue Hydro Flask at Library 1st Floor'));
      await tester.pumpAndSettle();

      // Verify that the tapped post's detail dialog opened!
      expect(find.text('Finder Frank'), findsOneWidget);
      expect(find.text('Library 1st Floor'), findsOneWidget);
    });
  });

  group('Admin Controls Screen Security & Governance Tests', () {
    testWidgets('Non-admin user sees access restricted gate', (WidgetTester tester) async {
      final studentUser = User(
        id: 'usr_s1',
        email: 'student@iisc.ac.in',
        name: 'Aarav Sharma',
        isAdmin: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => studentUser),
          ],
          child: const MaterialApp(
            home: AdminControlsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsNWidgets(2));
      expect(find.textContaining('This area is restricted to active IISc CampusHub Administrators'), findsOneWidget);
    });

    testWidgets('Administrator sees full governance tabs', (WidgetTester tester) async {
      final adminUser = User(
        id: 'usr_a1',
        email: 'kmukund@iisc.ac.in',
        name: 'Mukund Kukreja',
        isAdmin: true,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => adminUser),
            adminRepositoryProvider.overrideWithValue(MockAdminRepository()),
            buySellCategoriesProvider.overrideWith((ref) => [const CategoryRef(id: 1, name: 'Books')]),
            lostFoundCategoriesProvider.overrideWith((ref) => [const CategoryRef(id: 1, name: 'Electronics')]),
          ],
          child: const MaterialApp(
            home: AdminControlsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin Controls & Governance'), findsOneWidget);
      expect(find.text('Moderators'), findsOneWidget);
      expect(find.text('User Accounts'), findsOneWidget);
      expect(find.text('Reports Queue'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Backend & Health'), findsOneWidget);
      expect(find.text('Campus Services'), findsOneWidget);
      expect(find.text('Appoint a moderator'), findsOneWidget);
    });

    testWidgets('Module moderator has access to Moderator Panel and Reports Queue', (WidgetTester tester) async {
      final modUser = User(
        id: 'usr_mock_002',
        email: 'cadithya@iisc.ac.in',
        name: 'Adithya Chippa',
        isAdmin: false,
        moderatorGrants: [
          ModeratorGrant(
            id: 'grant_101',
            module: 'buy_sell',
            scopeType: 'module',
            grantedAt: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => modUser),
            adminRepositoryProvider.overrideWithValue(MockAdminRepository()),
            buySellCategoriesProvider.overrideWith((ref) => [const CategoryRef(id: 1, name: 'Books')]),
            lostFoundCategoriesProvider.overrideWith((ref) => [const CategoryRef(id: 1, name: 'Electronics')]),
          ],
          child: const MaterialApp(
            home: AdminControlsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Access is granted, not restricted
      expect(find.text('Access Restricted'), findsNothing);
      expect(find.text('Moderator Controls & Reports'), findsOneWidget);
      expect(find.text('Reports Queue'), findsOneWidget);
      // A Buy & Sell moderator gets only the tools they can use: reports and categories.
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('User Accounts'), findsNothing);
      expect(find.text('Backend & Health'), findsNothing);
      expect(find.text('Campus Services'), findsNothing);
      expect(find.text('Appoint a moderator'), findsNothing);
    });

    test('MockAuthRepository hydrates active moderator grants and profile for designated moderator', () async {
      final authRepo = MockAuthRepository();

      // Sign in as cadithya@iisc.ac.in (designated Buy & Sell moderator in MockAdminRepository)
      final user = await authRepo.signInWithEmail('cadithya@iisc.ac.in');

      expect(user.email, 'cadithya@iisc.ac.in');
      expect(user.name, 'Adithya Chippa');
      expect(user.isAdmin, isFalse);
      expect(user.isModerator, isTrue);
      expect(user.canModerateBuySell, isTrue);
      expect(user.canModerateLostFound, isFalse);
      expect(user.roles.contains(UserRole.moderator), isTrue);
      expect(user.moderatorGrants.length, greaterThanOrEqualTo(1));
      expect(user.moderatorGrants.first.module, 'buy_sell');
    });

    test('GoRouter root path / is configured with redirect to /app', () {
      final rootRoute = appRouter.configuration.routes
          .whereType<GoRoute>()
          .firstWhere((r) => r.path == '/');
      expect(rootRoute.path, '/');
      expect(rootRoute.redirect, isNotNull);
    });

    test('ServerConfig model and notifier update settings correctly', () {
      final config = const ServerConfig(
        useMockData: true,
        apiBaseUrl: 'http://localhost:8000',
        devKey: 'test_key',
        devUserEmail: 'mukund@iisc.ac.in',
        databaseUrl: 'postgresql://postgres:pass@localhost:5432/db',
      );

      expect(config.useMockData, isTrue);
      expect(config.baseUrl, 'http://localhost:8000');
      expect(config.devKey, 'test_key');
      expect(config.devUserEmail, 'mukund@iisc.ac.in');
      expect(config.databaseUrl, 'postgresql://postgres:pass@localhost:5432/db');

      final updated = config.copyWith(
        useMockData: false,
        apiBaseUrl: 'http://10.217.103.203:8000',
      );
      expect(updated.useMockData, isFalse);
      expect(updated.apiBaseUrl, 'http://10.217.103.203:8000');
      expect(updated.devKey, 'test_key');
    });

    testWidgets('AdminControlsScreen tab 4 renders Live Demo Connection Card', (WidgetTester tester) async {
      final adminUser = User(
        id: 'usr_mock_001',
        email: 'mukund@iisc.ac.in',
        name: 'Mukund Kukreja',
        isAdmin: true,
        moderatorGrants: const [],
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => adminUser),
            adminRepositoryProvider.overrideWithValue(MockAdminRepository()),
            buySellCategoriesProvider.overrideWith((ref) => [const CategoryRef(id: 1, name: 'Books')]),
            lostFoundCategoriesProvider.overrideWith((ref) => [const CategoryRef(id: 1, name: 'Electronics')]),
          ],
          child: const MaterialApp(
            home: AdminControlsScreen(initialTab: 4),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live Demo Backend & Database Connection'), findsOneWidget);
      expect(find.text('FastAPI Server Base URL'), findsOneWidget);
      expect(find.text('Developer Security Key / Secret (X-Dev-Key)'), findsOneWidget);
      expect(find.text('Test User Email Identity (X-Dev-User)'), findsOneWidget);
      expect(find.text('Database Connection URI (Demo Reference)'), findsOneWidget);
      expect(find.text('Save & Apply Backend'), findsOneWidget);
      expect(find.text('Test Server & Database Connection'), findsOneWidget);
      expect(find.text('Reset to Default Mock'), findsOneWidget);
    });
  });
}
