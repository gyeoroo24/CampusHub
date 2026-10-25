import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/contact.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/features/buy_sell/data/mock_buy_sell_repository.dart';
import 'package:campus_hub/features/buy_sell/domain/buy_sell_item.dart';
import 'package:campus_hub/features/buy_sell/providers/buy_sell_providers.dart';
import 'package:campus_hub/features/buy_sell/ui/widgets/buy_sell_grid_card.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';
import 'package:campus_hub/features/lost_found/ui/widgets/lost_found_card.dart';

void main() {
  group('Buy & Sell Filter & Toolbar State Tests', () {
    test('Default filter state includes all 3 statuses and no price constraints', () {
      final state = BuySellFilterState();
      expect(state.selectedStatuses, containsAll([
        ListingStatus.available,
        ListingStatus.reserved,
        ListingStatus.sold,
      ]));
      expect(state.minPrice, isNull);
      expect(state.maxPrice, isNull);
      expect(state.hasActiveCustomFilters, isFalse);
    });

    test('Selecting status filters updates selectedStatuses as multi-select toggles', () {
      var state = BuySellFilterState();

      // Toggle off sold
      state = state.copyWith(selectedStatuses: {
        ListingStatus.available,
        ListingStatus.reserved,
      });
      expect(state.selectedStatuses.length, 2);
      expect(state.selectedStatuses.contains(ListingStatus.sold), isFalse);
      expect(state.hasActiveCustomFilters, isTrue);

      // Toggle off reserved (only available left)
      state = state.copyWith(selectedStatuses: {
        ListingStatus.available,
      });
      expect(state.selectedStatuses.length, 1);
      expect(state.statusFilter, ListingStatus.available);

      // Attempting to deselect all 3 statuses automatically selects Available
      state = state.copyWith(selectedStatuses: {});
      expect(state.selectedStatuses, {ListingStatus.available});
      expect(state.statusFilter, ListingStatus.available);

      // Reset to All
      state = state.copyWith(
        clearStatusFilter: true,
        clearMinPrice: true,
        clearMaxPrice: true,
      );
      expect(state.selectedStatuses.length, 3);
      expect(state.minPrice, isNull);
      expect(state.maxPrice, isNull);
    });

    test('Price preset toggle sets and clears minPrice and maxPrice', () {
      var state = BuySellFilterState();

      // Apply Under ₹500
      state = state.copyWith(minPrice: null, clearMinPrice: true, maxPrice: 500.0);
      expect(state.minPrice, isNull);
      expect(state.maxPrice, 500.0);

      // Toggle off
      state = state.copyWith(clearMinPrice: true, clearMaxPrice: true);
      expect(state.minPrice, isNull);
      expect(state.maxPrice, isNull);
    });
  });

  group('Dynamic Category Creation Tests', () {
    test('MockBuySellRepository creates new category and persists it in memory', () async {
      final repo = MockBuySellRepository();
      final initialCats = await repo.fetchCategories();
      final initialCount = initialCats.length;

      final newCat = await repo.createCategory('Musical Instruments ${DateTime.now().millisecondsSinceEpoch}');
      expect(newCat.id, greaterThan(0));

      final updatedCats = await repo.fetchCategories();
      expect(updatedCats.length, initialCount + 1);
      expect(updatedCats.any((c) => c.name == newCat.name), isTrue);
    });

    test('MockLostFoundRepository creates new category and persists it in memory', () async {
      final repo = MockLostFoundRepository();
      final initialCats = await repo.fetchCategories();
      final initialCount = initialCats.length;

      final newCat = await repo.createCategory('Watches & Wearables ${DateTime.now().millisecondsSinceEpoch}');
      expect(newCat.id, greaterThan(0));

      final updatedCats = await repo.fetchCategories();
      expect(updatedCats.length, initialCount + 1);
      expect(updatedCats.any((c) => c.name == newCat.name), isTrue);
    });
  });

  group('Seller Edit & Delete Operations Tests', () {
    test('Seller can update listing contents and soft-delete listing', () async {
      final repo = MockBuySellRepository();
      final paged = await repo.fetchListingsPage(limit: 5);
      expect(paged.items, isNotEmpty);

      final original = paged.items.first;
      final updated = await repo.updateListing(
        original.id,
        title: 'Updated Test Title',
        price: 999.0,
        location: 'New Gymkhana Block',
      );

      expect(updated.title, 'Updated Test Title');
      expect(updated.price, 999.0);
      expect(updated.location, 'New Gymkhana Block');

      // Test delete
      await repo.deleteListing(original.id);
      final afterDelete = await repo.getListingById(original.id);
      expect(afterDelete, isNull);
    });

    test('Reporter can update lost/found report contents and delete report', () async {
      final repo = MockLostFoundRepository();
      final paged = await repo.fetchReportsPage(type: PostType.lost, limit: 5);
      expect(paged.items, isNotEmpty);

      final original = paged.items.first;
      final updated = await repo.updateReport(
        original.id,
        type: original.kind,
        description: 'Updated report description with new clues',
        location: 'Main Building Quadrangle',
      );

      expect(updated.description, 'Updated report description with new clues');
      expect(updated.location, 'Main Building Quadrangle');

      // Test delete
      await repo.deleteReport(original.id, original.kind);
      final afterDelete = await repo.getReportById(original.id, type: original.kind);
      expect(afterDelete, isNull);
    });
  });

  group('Phone Contact Display in Tiles Widget Tests', () {
    testWidgets('BuySellGridCard renders both Email and Phone buttons when phone is provided', (tester) async {
      final itemWithPhone = ListingItem(
        id: 'phone_test_1',
        title: 'Bicycle with Helmet',
        description: 'Great condition bicycle.',
        price: 2500.0,
        status: ListingStatus.available,
        category: const CategoryRef(id: 2, name: 'Cycles'),
        location: 'Gymkhana',
        seller: const UserRef(id: 'usr_test', name: 'Rohan Verma'),
        sellerContact: const Contact(email: 'rohanv@iisc.ac.in', phone: '+919876543210'),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 400,
                child: BuySellGridCard(item: itemWithPhone),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('rohanv@iisc.ac.in'), findsNothing);
      expect(find.text('+919876543210'), findsNothing);
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    });

    testWidgets('LostFoundCard renders Email and Call buttons without raw contact info in tile', (tester) async {
      final itemWithPhone = LostFoundItem(
        id: 'lf_phone_test_1',
        title: 'Lost Blue Casio Watch',
        description: 'Blue dial watch lost near library lawn.',
        kind: PostType.lost,
        status: ReportStatus.open,
        category: const CategoryRef(id: 3, name: 'Personal Belongings'),
        location: 'Library Lawn',
        occurredAt: DateTime.now(),
        reporter: const UserRef(id: 'usr_test', name: 'Ananya Sen'),
        reporterContact: const Contact(email: 'ananyas@iisc.ac.in', phone: '+919123456789'),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 400,
                child: LostFoundCard(item: itemWithPhone),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('ananyas@iisc.ac.in'), findsNothing);
      expect(find.text('+919123456789'), findsNothing);
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    });
  });
}
