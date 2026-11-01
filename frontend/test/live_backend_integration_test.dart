import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/api/api_client.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/core/storage/token_storage.dart';
import 'package:campus_hub/features/auth/data/auth_repository.dart';
import 'package:campus_hub/features/buy_sell/data/buy_sell_repository.dart';
import 'package:campus_hub/features/buy_sell/domain/buy_sell_item.dart';
import 'package:campus_hub/features/lost_found/data/lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';

void main() {
  const liveUrl = String.fromEnvironment('LIVE_BACKEND_URL', defaultValue: 'http://localhost:8000');
  const devKey = String.fromEnvironment('DEV_KEY', defaultValue: '');

  group('Live FastAPI Backend Integration Tests', () {
    late InMemoryTokenStorage storage;
    late ApiClient apiClient;
    late ApiAuthRepository authRepo;
    late ApiBuySellRepository buySellRepo;
    late ApiLostFoundRepository lostFoundRepo;
    bool isServerOnline = false;

    setUpAll(() async {
      try {
        final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
        await dio.get('$liveUrl/docs');
        isServerOnline = true;
      } catch (_) {
        isServerOnline = false;
      }
    });

    setUp(() {
      storage = InMemoryTokenStorage();
      apiClient = ApiClient(
        dioClient: Dio(
          BaseOptions(
            baseUrl: liveUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ),
        storage: storage,
        devKey: devKey,
      );
      authRepo = ApiAuthRepository(apiClient: apiClient, tokenStorage: storage);
      buySellRepo = ApiBuySellRepository(apiClient);
      lostFoundRepo = ApiLostFoundRepository(apiClient);
    });

    test('Scenario 1: Backend connectivity & Buy/Sell categories retrieval', () async {
      if (!isServerOnline) {
        // ignore: avoid_print
        print('Skipping live test: server $liveUrl is unreachable.');
        return;
      }
      final categories = await buySellRepo.fetchCategories();
      expect(categories, isNotEmpty);
      expect(categories.any((c) => c.name.toLowerCase() == 'books'), isTrue);
      // ignore: avoid_print
      print('✓ Loaded ${categories.length} categories: ${categories.map((c) => c.name).toList()}');
    });

    test('Scenario 2: Unauthenticated guest feed browsing', () async {
      if (!isServerOnline) return;
      final feed = await buySellRepo.fetchListingsPage(limit: 10, offset: 0);
      expect(feed, isNotNull);
      expect(feed.limit, equals(10));
      // ignore: avoid_print
      print('✓ Guest successfully queried feed. Total items returned: ${feed.items.length}');
    });

    test('Scenario 3: User Authentication & /me profile retrieval', () async {
      if (!isServerOnline) return;
      const testEmail = 'mukund@iisc.ac.in';
      final user = await authRepo.verifyOtp(testEmail, '123456');

      expect(user, isNotNull);
      expect(user.email, equals(testEmail));
      expect(user.id, isNotEmpty);
      // ignore: avoid_print
      print('✓ User authenticated: ${user.name} (${user.email}) ID: ${user.id}');
    });

    test('Scenario 4: End-to-End Listing Lifecycle (Create, Query, Status Update, Delete)', () async {
      if (!isServerOnline) return;
      const testEmail = 'mukund@iisc.ac.in';
      final user = await authRepo.verifyOtp(testEmail, '123456');

      // 1. Create a listing
      final newItem = ListingItem(
        id: '', // Backend assigns UUID
        title: 'Distributed Systems Course Notes',
        description: 'Comprehensive lecture notes for DS252 Cloud Computing.',
        price: 350.0,
        status: ListingStatus.available,
        category: const CategoryRef(id: 4, name: 'books'),
        seller: UserRef(id: user.id, name: user.name),
        location: 'Department of CSA',
        createdAt: DateTime.now(),
      );

      final created = await buySellRepo.addListing(newItem);
      expect(created.id, isNotEmpty);
      expect(created.title, equals('Distributed Systems Course Notes'));
      expect(created.price, equals(350.0));
      // ignore: avoid_print
      print('✓ Created listing with remote ID: ${created.id}');

      // 2. Fetch by ID as authenticated seller (contact must be visible)
      final fetched = await buySellRepo.getListingById(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.sellerContact?.email, equals(testEmail));
      // ignore: avoid_print
      print('✓ Authenticated fetch revealed contact email: ${fetched.sellerContact?.email}');

      // 3. Status update to reserved
      await buySellRepo.updateStatus(created.id, ListingStatus.reserved);
      final updated = await buySellRepo.getListingById(created.id);
      expect(updated?.status, equals(ListingStatus.reserved));
      // ignore: avoid_print
      print('✓ Updated listing status to: ${updated?.status.name}');

      // 4. Clean up / Delete listing
      await buySellRepo.deleteListing(created.id);
      // ignore: avoid_print
      print('✓ Successfully deleted listing ${created.id}');
    });

    test('Scenario 5: Lost & Found live connectivity check', () async {
      if (!isServerOnline) return;
      final lfCategories = await lostFoundRepo.fetchCategories();
      // ignore: avoid_print
      print('✓ Lost & Found categories count: ${lfCategories.length}');

      final lostFeed = await lostFoundRepo.fetchReportsPage(type: PostType.lost, limit: 5);
      final foundFeed = await lostFoundRepo.fetchReportsPage(type: PostType.found, limit: 5);
      expect(lostFeed, isNotNull);
      expect(foundFeed, isNotNull);
      // ignore: avoid_print
      print('✓ Lost feed items: ${lostFeed.items.length}, Found feed items: ${foundFeed.items.length}');
    });
  });
}
