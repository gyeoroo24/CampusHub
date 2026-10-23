import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/contact.dart';
import 'package:campus_hub/core/models/photo.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/features/auth/domain/user.dart';
import 'package:campus_hub/features/auth/providers/auth_providers.dart';
import 'package:campus_hub/features/buy_sell/domain/buy_sell_item.dart';
import 'package:campus_hub/features/buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';
import 'package:campus_hub/features/lost_found/ui/widgets/lost_found_detail_dialog.dart';

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
    expect(find.text('Blue IISc Student ID Card with red lanyard'), findsOneWidget);
    expect(find.text('Reporter Contact Details Protected'), findsOneWidget);
  });
}
