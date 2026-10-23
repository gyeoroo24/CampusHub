import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/storage/token_storage.dart';
import 'package:campus_hub/core/utils/date_time_formatter.dart';
import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/data/auth_repository.dart';
import 'package:campus_hub/features/buy_sell/domain/buy_sell_item.dart';
import 'package:campus_hub/features/buy_sell/data/buy_sell_dto.dart';
import 'package:campus_hub/features/buy_sell/data/mock_buy_sell_repository.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';
import 'package:campus_hub/features/lost_found/data/lost_found_dto.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';

void main() {
  group('Auth Data Layer Tests', () {
    test('User domain entity computes correct roles and display name', () {
      final user = User(
        id: 'u123',
        email: 'kmukund@iisc.ac.in',
        roles: const [UserRole.signedIn],
        createdAt: DateTime.now(),
      );

      expect(user.displayName, equals('kmukund'));
      expect(user.isSignedIn, isTrue);
      expect(user.isGuest, isFalse);
      expect(user.isModerator, isFalse);
      expect(user.isOwnerOf('u123'), isTrue);
      expect(user.isOwnerOf('other'), isFalse);
    });

    test('MockAuthRepository supports sendOtp, verifyOtp, and session persistence', () async {
      final storage = InMemoryTokenStorage();
      final repo = MockAuthRepository(storage: storage);

      // Sign out initial default
      await repo.signOut();
      expect(await repo.getCurrentUser(), isNull);
      expect(await storage.getSavedUser(), isNull);

      // Attempt invalid email
      expect(
        () => repo.sendOtp('student@gmail.com'),
        throwsA(isA<Exception>()),
      );

      // Valid email send OTP
      await repo.sendOtp('adithyac@iisc.ac.in');

      // Verify OTP (any 6 digits in mock mode)
      final user = await repo.verifyOtp('adithyac@iisc.ac.in', '654321');
      expect(user.email, equals('adithyac@iisc.ac.in'));
      expect(user.displayName, equals('adithyac'));

      // Check storage persistence
      final savedUser = await storage.getSavedUser();
      expect(savedUser, isNotNull);
      expect(savedUser!['email'], equals('adithyac@iisc.ac.in'));

      // Recreating repo from storage preserves session
      final newRepo = MockAuthRepository(storage: storage);
      final restored = await newRepo.getCurrentUser();
      expect(restored?.email, equals('adithyac@iisc.ac.in'));
    });
  });

  group('Buy & Sell Data Layer Tests', () {
    test('BuySellListingDto parses snake_case JSON correctly', () {
      final json = {
        'id': 'item_101',
        'seller_id': 'seller_007',
        'seller_email': 'seller@iisc.ac.in',
        'title': 'Bicycle Helmet',
        'description': 'Red and black helmet, size L',
        'cost_price': 1200.0,
        'selling_price': 500.0,
        'category': 'Cycles',
        'location': 'E-Block',
        'photo_urls': ['https://example.com/img1.jpg'],
        'status': 'available',
        'created_at': '2026-10-22T10:00:00.000Z',
      };

      final dto = BuySellListingDto.fromJson(json);
      final domain = dto.toDomain();

      expect(domain.id, equals('item_101'));
      expect(domain.sellerId, equals('seller_007'));
      expect(domain.sellerEmail, equals('seller@iisc.ac.in'));
      expect(domain.sellerName, equals('seller@iisc.ac.in'));
      expect(domain.sellingPrice, equals(500.0));
      expect(domain.status, equals(ListingStatus.available));
      expect(domain.imageUrls, contains('https://example.com/img1.jpg'));
    });

    test('MockBuySellRepository filters by query, price, date, and status', () async {
      final repo = MockBuySellRepository();

      // Filter by category
      final cycles = await repo.fetchListings(category: 'Cycles');
      expect(cycles.every((item) => item.category == 'Cycles'), isTrue);

      // Search query
      final queryResults = await repo.fetchListings(query: 'Calculator');
      expect(queryResults.any((item) => item.title.contains('Calculator')), isTrue);

      // Price filter
      final affordable = await repo.fetchListings(maxPrice: 500.0);
      expect(affordable.every((item) => item.sellingPrice <= 500.0), isTrue);

      // Date duration filter (e.g. past 2 days)
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final recent = await repo.fetchListings(fromDate: twoDaysAgo);
      expect(recent.every((item) => item.createdAt.isAfter(twoDaysAgo)), isTrue);

      // Status update
      await repo.updateStatus('1', ListingStatus.sold);
      final item = await repo.getListingById('1');
      expect(item?.status, equals(ListingStatus.sold));
    });
  });

  group('DateTimeFormatter Utility Tests', () {
    test('Formats recent, hours, days, and full datetime correctly', () {
      final now = DateTime.now();
      expect(DateTimeFormatter.timeAgo(now.subtract(const Duration(seconds: 30))), equals('Just now'));
      expect(DateTimeFormatter.timeAgo(now.subtract(const Duration(minutes: 5))), equals('5m ago'));
      expect(DateTimeFormatter.timeAgo(now.subtract(const Duration(hours: 3))), equals('3h ago'));
      expect(DateTimeFormatter.timeAgo(now.subtract(const Duration(days: 1))), equals('Yesterday'));

      final formatted = DateTimeFormatter.fullDateTime(DateTime(2026, 10, 22, 14, 30));
      expect(formatted, contains('22 Oct 2026'));
      expect(formatted, contains('2:30 PM'));
    });
  });

  group('Lost & Found Data Layer Tests', () {
    test('LostFoundReportDto parses snake_case JSON correctly', () {
      final json = {
        'id': 'report_202',
        'reporter_id': 'rep_1',
        'reporter_contact': 'finder@iisc.ac.in',
        'type': 'found',
        'title': 'Keys found',
        'description': 'Ring with 3 keys found near canteen',
        'category': 'Keys',
        'location': 'Canteen',
        'photo_urls': ['https://example.com/keys.jpg'],
        'event_time': '10:30 AM',
        'status': 'open',
        'date_reported': '2026-10-22T10:30:00.000Z',
      };

      final dto = LostFoundReportDto.fromJson(json);
      final domain = dto.toDomain();

      expect(domain.id, equals('report_202'));
      expect(domain.type, equals(PostType.found));
      expect(domain.reporterContact, equals('finder@iisc.ac.in'));
      expect(domain.status, equals(ReportStatus.open));
    });

    test('MockLostFoundRepository supports separate lost and found feeds', () async {
      final repo = MockLostFoundRepository();

      final lostReports = await repo.fetchReports(type: PostType.lost);
      expect(lostReports.every((r) => r.type == PostType.lost), isTrue);

      final foundReports = await repo.fetchReports(type: PostType.found);
      expect(foundReports.every((r) => r.type == PostType.found), isTrue);

      // Submit new report
      final newReport = LostFoundItem(
        id: 'test_rep_1',
        reporterContact: 'test@iisc.ac.in',
        title: 'Lost Water Bottle',
        description: 'Metal bottle left in lecture hall',
        category: 'Personal Belongings',
        location: 'LH-1',
        imageUrls: const [],
        type: PostType.lost,
        eventTime: 'Today',
        dateReported: DateTime.now(),
      );

      await repo.submitReport(newReport);
      final fetched = await repo.getReportById('test_rep_1');
      expect(fetched?.title, equals('Lost Water Bottle'));
    });
  });
}
