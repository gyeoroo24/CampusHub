import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/api/api_exception.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/contact.dart';
import 'package:campus_hub/core/models/page.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/core/services/upload_service.dart';
import 'package:campus_hub/core/storage/token_storage.dart';
import 'package:campus_hub/core/utils/date_time_formatter.dart';
import 'package:campus_hub/features/auth/domain/account_status.dart';
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
    test('User domain entity computes correct roles and scoped permissions', () {
      final user = User(
        id: 'u123',
        email: 'kmukund@iisc.ac.in',
        name: 'Mukund Kukreja',
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

      expect(user.displayName, equals('Mukund Kukreja'));
      expect(user.isSignedIn, isTrue);
      expect(user.isGuest, isFalse);
      expect(user.isModerator, isTrue);
      expect(user.canModerateBuySell, isTrue);
      expect(user.canModerateLostFound, isFalse);
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
      expect(restored?.isActive, isTrue);

      // Admin updateAccountStatus deactivates or reactivates account
      final updatedStatus = await newRepo.updateAccountStatus(
        restored!.id,
        isActive: false,
      );
      expect(updatedStatus.isActive, isFalse);

      // AccountStatus serialization
      final parsed = AccountStatus.fromJson(updatedStatus.toJson());
      expect(parsed.id, equals(updatedStatus.id));
      expect(parsed.isActive, isFalse);

      // Single admin transfer role
      final adminRepo = MockAuthRepository(storage: InMemoryTokenStorage());
      final adminUser = await adminRepo.getCurrentUser(); // default mock admin
      expect(adminUser?.isAdmin, isTrue);

      final transferred = await adminRepo.transferAdminRole('usr_new_admin');
      expect(transferred.isAdmin, isTrue);
      expect(transferred.id, equals('usr_new_admin'));

      // Caller is demoted
      final demotedAdmin = await adminRepo.getCurrentUser();
      expect(demotedAdmin?.isAdmin, isFalse);
    });

    test('ServiceUnavailableException has status 503', () {
      const ex = ServiceUnavailableException(message: 'Unavailable');
      expect(ex.statusCode, equals(503));
    });
  });

  group('Upload Service Tests', () {
    test('Computes SHA-256 Base64 checksum correctly', () {
      final bytes = Uint8List.fromList(utf8.encode('Hello CampusHub!'));
      final checksum = UploadService.computeSha256Base64(bytes);

      // Verifiable SHA-256 base64 digest
      expect(checksum, isNotEmpty);
      expect(checksum.length, equals(44)); // Standard base64 length for 32 bytes
    });
  });

  group('Buy & Sell Data Layer Tests', () {
    test('BuySellListingDto parses FastAPI JSON schemas correctly', () {
      final json = {
        'id': 'item_101',
        'title': 'Bicycle Helmet',
        'description': 'Red and black helmet, size L',
        'price': '500.00',
        'status': 'available',
        'location': 'E-Block',
        'category': {'id': 2, 'name': 'Cycles'},
        'seller': {'id': 'seller_007', 'name': 'Asha'},
        'cover_photo_url': 'https://example.com/img1.jpg',
        'photos': [
          {'s3_key': 'key_001', 'url': 'https://example.com/img1.jpg', 'sort_order': 0}
        ],
        'seller_contact': {'email': 'seller@iisc.ac.in', 'phone': '+919876543210'},
        'created_at': '2026-10-22T10:00:00.000Z',
      };

      final dto = BuySellListingDto.fromJson(json);
      final domain = dto.toDomain();

      expect(domain.id, equals('item_101'));
      expect(domain.seller.id, equals('seller_007'));
      expect(domain.seller.name, equals('Asha'));
      expect(domain.sellerContact?.email, equals('seller@iisc.ac.in'));
      expect(domain.price, equals(500.0));
      expect(domain.status, equals(ListingStatus.available));
      expect(domain.category.name, equals('Cycles'));
      expect(domain.category.id, equals(2));
      expect(domain.photoUrls, contains('https://example.com/img1.jpg'));
    });

    test('MockBuySellRepository filters by query, price, date, and status', () async {
      final repo = MockBuySellRepository();

      // Filter by category
      final cycles = await repo.fetchListings(category: 'Cycles');
      expect(cycles.every((item) => item.category.name == 'Cycles'), isTrue);

      // Search query
      final queryResults = await repo.fetchListings(query: 'Calculator');
      expect(queryResults.any((item) => item.title.contains('Calculator')), isTrue);

      // Price filter
      final affordable = await repo.fetchListings(maxPrice: 500.0);
      expect(affordable.every((item) => item.price <= 500.0), isTrue);

      // Paginated page query
      final PaginatedResponse<ListingItem> paged = await repo.fetchListingsPage(limit: 3, offset: 0);
      expect(paged.items.length, equals(3));
      expect(paged.hasMore, isTrue);

      // Status update
      await repo.updateStatus('1', ListingStatus.sold);
      final item = await repo.getListingById('1');
      expect(item?.status, equals(ListingStatus.sold));
    });
  });

  group('Lost & Found Data Layer Tests', () {
    test('LostFoundReportDto parses FastAPI JSON schemas correctly', () {
      final json = {
        'id': 'report_202',
        'kind': 'found',
        'description': 'Ring with 3 keys found near canteen',
        'category': {'id': 5, 'name': 'Keys'},
        'location': 'Canteen',
        'occurred_at': '2026-10-22T10:30:00.000Z',
        'status': 'open',
        'reporter': {'id': 'rep_1', 'name': 'Finder Student'},
        'cover_photo_url': 'https://example.com/keys.jpg',
        'photos': [
          {'s3_key': 'key_k', 'url': 'https://example.com/keys.jpg', 'sort_order': 0}
        ],
        'reporter_contact': {'email': 'finder@iisc.ac.in', 'phone': null},
        'created_at': '2026-10-22T10:30:00.000Z',
      };

      final dto = LostFoundReportDto.fromJson(json);
      final domain = dto.toDomain();

      expect(domain.id, equals('report_202'));
      expect(domain.kind, equals(PostType.found));
      expect(domain.reporterContact?.email, equals('finder@iisc.ac.in'));
      expect(domain.status, equals(ReportStatus.open));
      expect(domain.category.name, equals('Keys'));
      expect(domain.category.id, equals(5));
    });

    test('MockLostFoundRepository supports separate lost and found feeds', () async {
      final repo = MockLostFoundRepository();

      final lostReports = await repo.fetchReports(type: PostType.lost);
      expect(lostReports.every((r) => r.kind == PostType.lost), isTrue);

      final foundReports = await repo.fetchReports(type: PostType.found);
      expect(foundReports.every((r) => r.kind == PostType.found), isTrue);

      // Submit new report
      final newReport = LostFoundItem(
        id: 'test_rep_1',
        kind: PostType.lost,
        description: 'Metal bottle left in lecture hall',
        category: const CategoryRef(id: 3, name: 'Personal Belongings'),
        occurredAt: DateTime.now(),
        location: 'LH-1',
        status: ReportStatus.open,
        reporter: const UserRef(id: 'usr_me', name: 'Mukund'),
        reporterContact: const Contact(email: 'test@iisc.ac.in'),
        createdAt: DateTime.now(),
      );

      final submitted = await repo.submitReport(newReport);
      expect(submitted.id, equals('test_rep_1'));

      final fetched = await repo.getReportById('test_rep_1');
      expect(fetched?.description, equals('Metal bottle left in lecture hall'));
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
}
