import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/contact.dart';
import 'package:campus_hub/core/models/photo.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/core/widgets/no_photo_placeholder.dart';
import 'package:campus_hub/core/widgets/skeleton_loader.dart';
import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/providers/auth_providers.dart';
import 'package:campus_hub/features/buy_sell/data/mock_buy_sell_repository.dart';
import 'package:campus_hub/features/buy_sell/domain/buy_sell_item.dart';
import 'package:campus_hub/features/buy_sell/providers/buy_sell_providers.dart';
import 'package:campus_hub/features/buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';
import 'package:campus_hub/features/lost_found/providers/lost_found_providers.dart';
import 'package:campus_hub/features/lost_found/ui/widgets/lost_found_detail_dialog.dart';
import 'package:campus_hub/features/lost_found/ui/widgets/report_item_dialog.dart';

void main() {
  final sampleListing = ListingItem(
    id: 'test_l1',
    title: 'Calculus 8th Edition',
    description: 'James Stewart in great condition',
    price: 450.0,
    status: ListingStatus.available,
    location: 'Main Library',
    category: const CategoryRef(id: 1, name: 'Books'),
    seller: const UserRef(id: 'usr_seller_1', name: 'Seller Sam'),
    photos: const [Photo(s3Key: 'key_1', url: 'https://example.com/p1.jpg', sortOrder: 0)],
    sellerContact: const Contact(email: 'sam@iisc.ac.in', phone: '9876543210'),
    createdAt: DateTime.now(),
  );

  final sampleListingGuest = ListingItem(
    id: 'test_l2',
    title: 'Calculus 8th Edition',
    description: 'James Stewart in great condition',
    price: 450.0,
    status: ListingStatus.available,
    location: 'Main Library',
    category: const CategoryRef(id: 1, name: 'Books'),
    seller: const UserRef(id: 'usr_seller_1', name: 'Seller Sam'),
    photos: const [Photo(s3Key: 'key_1', url: 'https://example.com/p1.jpg', sortOrder: 0)],
    sellerContact: null, // Stripped for guest
    createdAt: DateTime.now(),
  );

  final sampleReportGuest = LostFoundItem(
    id: 'test_r1',
    kind: PostType.lost,
    description: 'Blue IISc Student ID Card with red lanyard',
    category: const CategoryRef(id: 1, name: 'ID Cards'),
    occurredAt: DateTime.now().subtract(const Duration(hours: 2)),
    location: 'Gymkhana Grounds',
    status: ReportStatus.open,
    reporter: const UserRef(id: 'usr_rep_1', name: 'Reporter Rita'),
    photos: const [Photo(s3Key: 'key_2', url: 'https://example.com/p2.jpg', sortOrder: 0)],
    reporterContact: null, // Stripped for guest
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  );

  testWidgets('BuySellDetailDialog displays item details and guest privacy prompt', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => null), // Guest user
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BuySellDetailDialog(item: sampleListingGuest),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calculus 8th Edition'), findsOneWidget);
    expect(find.text('₹450'), findsOneWidget);
    expect(find.text('Seller Contact Details Protected'), findsOneWidget);
    expect(find.textContaining('Contact information is visible to authenticated IISc students only'), findsOneWidget);
  });

  testWidgets('BuySellDetailDialog shows seller controls when viewer is seller', (WidgetTester tester) async {
    final sellerUser = User(
      id: 'usr_seller_1',
      email: 'sam@iisc.ac.in',
      name: 'Seller Sam',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => sellerUser),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BuySellDetailDialog(item: sampleListing),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calculus 8th Edition'), findsOneWidget);
    expect(find.text('Listing Owner Controls'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsNWidgets(2));
    expect(find.text('RESERVED'), findsOneWidget);
    expect(find.text('SOLD'), findsOneWidget);
  });

  testWidgets('LostFoundDetailDialog displays report details and guest privacy notice', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LostFoundDetailDialog(item: sampleReportGuest),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOST REPORT'), findsOneWidget);
    expect(find.text('ID Cards'), findsWidgets);
    expect(find.text('Blue IISc Student ID Card with red lanyard'), findsWidgets);
    expect(find.text('Reporter Contact Details Protected'), findsOneWidget);
  });

  testWidgets('SkeletonGrid renders shimmer loading placeholder cards', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SkeletonGrid(itemCount: 4),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShimmerLoadingCard), findsNWidgets(4));
  });

  testWidgets('SkeletonList renders list shimmer loading placeholder cards', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SkeletonList(itemCount: 3),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShimmerLoadingCard), findsNWidgets(3));
  });

  testWidgets('NoPhotoPlaceholder renders intentional placeholder in compact and full modes', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 100, height: 80, child: NoPhotoPlaceholder(compact: true)),
              SizedBox(width: 250, height: 200, child: NoPhotoPlaceholder()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No photo'), findsOneWidget);
    expect(find.text('No photos attached'), findsOneWidget);
    expect(find.text('The author did not attach images'), findsOneWidget);
  });

  test('BuySellPaginationNotifier loads initial page and supports loadMore()', () async {
    final container = ProviderContainer(
      overrides: [
        buySellRepositoryProvider.overrideWithValue(MockBuySellRepository()),
      ],
    );
    addTearDown(container.dispose);

    // Initial state has isLoadingInitial == true
    expect(container.read(buySellPaginationProvider).isLoadingInitial, isTrue);

    // Wait for initial load
    await Future<void>.delayed(const Duration(milliseconds: 450));

    final state1 = container.read(buySellPaginationProvider);
    expect(state1.isLoadingInitial, isFalse);
    expect(state1.items.length, 8);
    expect(state1.hasMore, isTrue);

    // Trigger loadMore
    final notifier = container.read(buySellPaginationProvider.notifier);
    final loadMoreFuture = notifier.loadMore();
    expect(container.read(buySellPaginationProvider).isLoadingMore, isTrue);

    await loadMoreFuture;
    final state2 = container.read(buySellPaginationProvider);
    expect(state2.isLoadingMore, isFalse);
    expect(state2.items.length, 16);
  });

  test('LostFoundPaginationNotifier loads initial reports and supports loadMore()', () async {
    final container = ProviderContainer(
      overrides: [
        lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
      ],
    );
    addTearDown(container.dispose);

    // Initial state has isLoadingInitial == true
    expect(container.read(lostReportsPaginationProvider).isLoadingInitial, isTrue);

    // Wait for initial load
    await Future<void>.delayed(const Duration(milliseconds: 450));

    final state1 = container.read(lostReportsPaginationProvider);
    expect(state1.isLoadingInitial, isFalse);
    expect(state1.items.length, 6);
    expect(state1.hasMore, isTrue);

    // Trigger loadMore
    final notifier = container.read(lostReportsPaginationProvider.notifier);
    final loadMoreFuture = notifier.loadMore();
    expect(container.read(lostReportsPaginationProvider).isLoadingMore, isTrue);

    await loadMoreFuture;
    final state2 = container.read(lostReportsPaginationProvider);
    expect(state2.isLoadingMore, isFalse);
    expect(state2.items.length, 8); // 6 initial + 2 remaining mock reports = 8
    expect(state2.hasMore, isFalse);
  });

  testWidgets('ReportItemDialog possible matches dialog renders properly without viewport intrinsic dimension errors', (WidgetTester tester) async {
    final sampleWithMatches = LostFoundItem(
      id: 'rep_match_1',
      kind: PostType.lost,
      description: 'Lost Backpack with laptop',
      category: const CategoryRef(id: 1, name: 'Bags'),
      occurredAt: DateTime.now(),
      location: 'Gymkhana Grounds',
      status: ReportStatus.open,
      reporter: const UserRef(id: 'usr_rep_1', name: 'Tester'),
      photos: const [],
      createdAt: DateTime.now(),
      possibleMatches: [
        LostFoundItem(
          id: 'rep_match_2',
          kind: PostType.found,
          description: 'Found Black Laptop Bag',
          category: const CategoryRef(id: 1, name: 'Bags'),
          occurredAt: DateTime.now(),
          location: 'Library 1st floor',
          status: ReportStatus.open,
          reporter: const UserRef(id: 'usr_rep_2', name: 'Finder Frank'),
          photos: const [],
          createdAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lostFoundRepositoryProvider.overrideWithValue(MockLostFoundRepository()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (dCtx) => ReportItemDialog(
                      postType: PostType.lost,
                      onSubmit: (item) async {
                        return sampleWithMatches;
                      },
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Fill form
    await tester.enterText(find.byType(TextFormField).first, 'Lost Backpack with laptop');
    await tester.enterText(find.byType(TextFormField).at(1), 'Gymkhana Grounds');

    // Submit
    await tester.tap(find.text('Submit Lost Report'));
    await tester.pumpAndSettle();

    // Verify Possible Matches Found modal rendered and displays matches without intrinsic dimension error
    expect(find.text('Possible Matches Found!'), findsOneWidget);
    expect(find.text('Found Black Laptop Bag'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Close matches modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Possible Matches Found!'), findsNothing);
  });
}
