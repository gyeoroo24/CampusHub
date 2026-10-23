import '../domain/buy_sell_item.dart';
import '../../../core/enums/sort_option.dart';
import 'buy_sell_repository.dart';

/// In-memory mock repository for Buy & Sell.
class MockBuySellRepository implements IBuySellRepository {
  final List<ListingItem> _mockData = [
    // --- 1 image, landscape 4:3 ---
    ListingItem(
      id: '1',
      sellerId: 'user_aarav',
      sellerEmail: 'aaravs@iisc.ac.in',
      title: 'IISc Chemistry Lab Coat (Size M)',
      description:
          '100% Cotton, clean condition with no chemical stains or tears. '
          'Ideal for first-year lab work. Washed and ironed. Fits 5\'7"–5\'10".',
      costPrice: 850.0,
      sellingPrice: 350.0,
      category: 'Lab Equipment',
      location: 'Sarvam Hostel Block B',
      imageUrls: const ['https://picsum.photos/seed/labcoat/600/450'],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    // --- 3 images: portrait, landscape, square ---
    ListingItem(
      id: '2',
      sellerId: 'user_priya',
      sellerEmail: 'priyan@iisc.ac.in',
      title: 'Ergonomic Mesh Study Chair',
      description:
          'Breathable mesh backrest with adjustable lumbar support and height '
          'pneumatic lever. Armrests intact. Minor scuff on base. '
          'Bought 6 months ago for 4500. Moving out of hostel.',
      costPrice: 4500.0,
      sellingPrice: 1800.0,
      category: 'Furniture',
      location: 'R-Block Hostel Room 204',
      imageUrls: const [
        'https://picsum.photos/seed/chair1/400/600', // portrait
        'https://picsum.photos/seed/chair2/700/400', // landscape wide
        'https://picsum.photos/seed/chair3/500/500', // square
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    // --- 2 images: both landscape ---
    ListingItem(
      id: '3',
      sellerId: 'user_rahul',
      sellerEmail: 'rahulv@iisc.ac.in',
      title: 'Engineering Mathematics by Erwin Kreyszig',
      description:
          '10th Edition Hardcover. Contains neatly highlighted notes and previous '
          'year problem solutions in pencil (erasable). All pages intact, spine tight.',
      costPrice: 1200.0,
      sellingPrice: 600.0,
      category: 'Books',
      location: 'Main Library Lawn',
      imageUrls: const [
        'https://picsum.photos/seed/book1/600/400',
        'https://picsum.photos/seed/book2/600/400',
      ],
      status: ListingStatus.reserved,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // --- 1 image, square ---
    ListingItem(
      id: '4',
      sellerId: 'user_ananya',
      sellerEmail: 'ananyar@iisc.ac.in',
      title: 'Philips 1.5L Electric Kettle',
      description:
          'Stainless steel body with dry-boil auto cut-off protection. '
          'Fast boiling — perfect for hostel tea and instant noodles. '
          'Cord length 0.75m. Sold as-is, works perfectly.',
      costPrice: 1499.0,
      sellingPrice: 750.0,
      category: 'Electronics',
      location: 'E-Block Hostel Room 112',
      imageUrls: const ['https://picsum.photos/seed/kettle/500/500'],
      status: ListingStatus.sold,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    // --- 4 images: varied (ultra-wide, portrait, square, landscape) ---
    ListingItem(
      id: '5',
      sellerId: 'user_vikram',
      sellerEmail: 'vikrams@iisc.ac.in',
      title: 'Hero Sprint 21-Speed Mountain Bicycle',
      description:
          'Dual disc brakes, front suspension fork, comes with dual LED lights '
          'and a sturdy combination lock. Tyres at 85% tread. Recently serviced '
          'and oiled. Ideal for campus commute and weekend rides.',
      costPrice: 12500.0,
      sellingPrice: 5800.0,
      category: 'Cycles',
      location: 'Physics Department Cycle Stand',
      imageUrls: const [
        'https://picsum.photos/seed/cycle1/800/350', // ultra-wide
        'https://picsum.photos/seed/cycle2/400/600', // portrait
        'https://picsum.photos/seed/cycle3/500/500', // square
        'https://picsum.photos/seed/cycle4/600/400', // landscape
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
    // --- 2 images, portrait heavy ---
    ListingItem(
      id: '6',
      sellerId: 'user_sneha',
      sellerEmail: 'snehai@iisc.ac.in',
      title: 'Casio FX-991EX Scientific Calculator',
      description:
          'Full working condition. 552 functions, spreadsheet mode, QR code '
          'display. Original pouch and manual included. Perfect for JEE/exam use.',
      costPrice: 1350.0,
      sellingPrice: 700.0,
      category: 'Electronics',
      location: 'CSA Department Foyer',
      imageUrls: const [
        'https://picsum.photos/seed/calc1/350/600',
        'https://picsum.photos/seed/calc2/350/600',
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 30)),
    ),
    // --- no images (tests empty-state) ---
    ListingItem(
      id: '7',
      sellerId: 'user_karan',
      sellerEmail: 'karanm@iisc.ac.in',
      title: 'Ikea Flisat Children\'s Table (repurposed study table)',
      description:
          'Lightweight flat-pack table repurposed as a bedside/study table. '
          'Height 44cm. White. Some pen marks underneath. Easy to disassemble.',
      costPrice: 2000.0,
      sellingPrice: 800.0,
      category: 'Furniture',
      location: 'New Biological Sciences Hostel',
      imageUrls: const [],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  @override
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
    double? minPrice,
    double? maxPrice,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int limit = 50,
  }) async {
    var items = _mockData.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          item.description.toLowerCase().contains(query.toLowerCase()) ||
          item.location.toLowerCase().contains(query.toLowerCase());
      final matchesCategory = category == 'All' || item.category == category;
      final matchesStatus = statusFilter == null || item.status == statusFilter;
      final matchesMinPrice = minPrice == null || item.sellingPrice >= minPrice;
      final matchesMaxPrice = maxPrice == null || item.sellingPrice <= maxPrice;
      final matchesFromDate = fromDate == null || item.createdAt.isAfter(fromDate);
      final matchesToDate = toDate == null || item.createdAt.isBefore(toDate);
      return matchesQuery &&
          matchesCategory &&
          matchesStatus &&
          matchesMinPrice &&
          matchesMaxPrice &&
          matchesFromDate &&
          matchesToDate;
    }).toList();

    switch (sortOption) {
      case SortOption.oldest:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.priceLowToHigh:
        items.sort((a, b) => a.sellingPrice.compareTo(b.sellingPrice));
        break;
      case SortOption.priceHighToLow:
        items.sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
        break;
      case SortOption.discountHighToLow:
        items.sort((a, b) {
          final discountA = (a.costPrice - a.sellingPrice) / a.costPrice;
          final discountB = (b.costPrice - b.sellingPrice) / b.costPrice;
          return discountB.compareTo(discountA);
        });
        break;
      case SortOption.newest:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    // Basic pagination slice
    final startIndex = (page - 1) * limit;
    if (startIndex >= items.length) return [];
    final endIndex = (startIndex + limit).clamp(0, items.length);
    return items.sublist(startIndex, endIndex);
  }

  @override
  Future<ListingItem?> getListingById(String id) async {
    try {
      return _mockData.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ListingItem> addListing(ListingItem item) async {
    _mockData.insert(0, item);
    return item;
  }

  @override
  Future<void> updateStatus(String id, ListingStatus newStatus) async {
    final index = _mockData.indexWhere((item) => item.id == id);
    if (index != -1) {
      _mockData[index] = _mockData[index].copyWith(status: newStatus);
    }
  }

  @override
  Future<void> deleteListing(String id) async {
    _mockData.removeWhere((item) => item.id == id);
  }
}
