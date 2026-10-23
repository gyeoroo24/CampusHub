import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/page.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../domain/buy_sell_item.dart';
import 'buy_sell_repository.dart';

/// In-memory mock repository for Buy & Sell.
class MockBuySellRepository implements IBuySellRepository {
  final List<CategoryRef> _categories = [
    const CategoryRef(id: 1, name: 'Books'),
    const CategoryRef(id: 2, name: 'Cycles'),
    const CategoryRef(id: 3, name: 'Electronics'),
    const CategoryRef(id: 4, name: 'Furniture'),
    const CategoryRef(id: 5, name: 'Lab Equipment'),
    const CategoryRef(id: 6, name: 'Others'),
  ];

  late final List<ListingItem> _mockData = [
    // --- 1 image, landscape 4:3 ---
    ListingItem(
      id: '1',
      seller: const UserRef(id: 'user_aarav', name: 'Aarav Sharma'),
      sellerContact: const Contact(email: 'aaravs@iisc.ac.in', phone: '+919876543211'),
      title: 'IISc Chemistry Lab Coat (Size M)',
      description:
          '100% Cotton, clean condition with no chemical stains or tears. '
          'Ideal for first-year lab work. Washed and ironed. Fits 5\'7"–5\'10".',
      price: 350.0,
      category: const CategoryRef(id: 5, name: 'Lab Equipment'),
      location: 'Sarvam Hostel Block B',
      coverPhotoUrl: 'https://picsum.photos/seed/labcoat/600/450',
      photos: const [
        Photo(s3Key: 'mock_coat_1', url: 'https://picsum.photos/seed/labcoat/600/450', sortOrder: 0),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    // --- 3 images: portrait, landscape, square ---
    ListingItem(
      id: '2',
      seller: const UserRef(id: 'user_priya', name: 'Priya Nair'),
      sellerContact: const Contact(email: 'priyan@iisc.ac.in', phone: '+919876543212'),
      title: 'Ergonomic Mesh Study Chair',
      description:
          'Breathable mesh backrest with adjustable lumbar support and height '
          'pneumatic lever. Armrests intact. Minor scuff on base. '
          'Bought 6 months ago for 4500. Moving out of hostel.',
      price: 1800.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'R-Block Hostel Room 204',
      coverPhotoUrl: 'https://picsum.photos/seed/chair1/400/600',
      photos: const [
        Photo(s3Key: 'mock_chair_1', url: 'https://picsum.photos/seed/chair1/400/600', sortOrder: 0),
        Photo(s3Key: 'mock_chair_2', url: 'https://picsum.photos/seed/chair2/700/400', sortOrder: 1),
        Photo(s3Key: 'mock_chair_3', url: 'https://picsum.photos/seed/chair3/500/500', sortOrder: 2),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    // --- 2 images: both landscape ---
    ListingItem(
      id: '3',
      seller: const UserRef(id: 'user_rahul', name: 'Rahul Verma'),
      sellerContact: const Contact(email: 'rahulv@iisc.ac.in'),
      title: 'Engineering Mathematics by Erwin Kreyszig',
      description:
          '10th Edition Hardcover. Contains neatly highlighted notes and previous '
          'year problem solutions in pencil (erasable). All pages intact, spine tight.',
      price: 600.0,
      category: const CategoryRef(id: 1, name: 'Books'),
      location: 'Main Library Lawn',
      coverPhotoUrl: 'https://picsum.photos/seed/book1/600/400',
      photos: const [
        Photo(s3Key: 'mock_book_1', url: 'https://picsum.photos/seed/book1/600/400', sortOrder: 0),
        Photo(s3Key: 'mock_book_2', url: 'https://picsum.photos/seed/book2/600/400', sortOrder: 1),
      ],
      status: ListingStatus.reserved,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // --- 1 image, square ---
    ListingItem(
      id: '4',
      seller: const UserRef(id: 'user_ananya', name: 'Ananya Roy'),
      sellerContact: const Contact(email: 'ananyar@iisc.ac.in'),
      title: 'Philips 1.5L Electric Kettle',
      description:
          'Stainless steel body with dry-boil auto cut-off protection. '
          'Fast boiling — perfect for hostel tea and instant noodles. '
          'Cord length 0.75m. Sold as-is, works perfectly.',
      price: 750.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'E-Block Hostel Room 112',
      coverPhotoUrl: 'https://picsum.photos/seed/kettle/500/500',
      photos: const [
        Photo(s3Key: 'mock_kettle_1', url: 'https://picsum.photos/seed/kettle/500/500', sortOrder: 0),
      ],
      status: ListingStatus.sold,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    // --- 4 images ---
    ListingItem(
      id: '5',
      seller: const UserRef(id: 'user_vikram', name: 'Vikram Singh'),
      sellerContact: const Contact(email: 'vikrams@iisc.ac.in'),
      title: 'Hero Sprint 21-Speed Mountain Bicycle',
      description:
          'Dual disc brakes, front suspension fork, comes with dual LED lights '
          'and a sturdy combination lock. Tyres at 85% tread. Recently serviced '
          'and oiled. Ideal for campus commute and weekend rides.',
      price: 5800.0,
      category: const CategoryRef(id: 2, name: 'Cycles'),
      location: 'Physics Department Cycle Stand',
      coverPhotoUrl: 'https://picsum.photos/seed/cycle1/800/350',
      photos: const [
        Photo(s3Key: 'mock_cycle_1', url: 'https://picsum.photos/seed/cycle1/800/350', sortOrder: 0),
        Photo(s3Key: 'mock_cycle_2', url: 'https://picsum.photos/seed/cycle2/400/600', sortOrder: 1),
        Photo(s3Key: 'mock_cycle_3', url: 'https://picsum.photos/seed/cycle3/500/500', sortOrder: 2),
        Photo(s3Key: 'mock_cycle_4', url: 'https://picsum.photos/seed/cycle4/600/400', sortOrder: 3),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
    // --- 2 images ---
    ListingItem(
      id: '6',
      seller: const UserRef(id: 'user_sneha', name: 'Sneha Iyer'),
      sellerContact: const Contact(email: 'snehai@iisc.ac.in'),
      title: 'Casio FX-991EX Scientific Calculator',
      description:
          'Full working condition. 552 functions, spreadsheet mode, QR code '
          'display. Original pouch and manual included. Perfect for JEE/exam use.',
      price: 700.0,
      category: const CategoryRef(id: 3, name: 'Electronics'),
      location: 'CSA Department Foyer',
      coverPhotoUrl: 'https://picsum.photos/seed/calc1/350/600',
      photos: const [
        Photo(s3Key: 'mock_calc_1', url: 'https://picsum.photos/seed/calc1/350/600', sortOrder: 0),
        Photo(s3Key: 'mock_calc_2', url: 'https://picsum.photos/seed/calc2/350/600', sortOrder: 1),
      ],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(hours: 30)),
    ),
    // --- no images ---
    ListingItem(
      id: '7',
      seller: const UserRef(id: 'user_karan', name: 'Karan Mehra'),
      sellerContact: const Contact(email: 'karanm@iisc.ac.in'),
      title: 'Ikea Flisat Children\'s Table (repurposed study table)',
      description:
          'Lightweight flat-pack table repurposed as a bedside/study table. '
          'Height 44cm. White. Some pen marks underneath. Easy to disassemble.',
      price: 800.0,
      category: const CategoryRef(id: 4, name: 'Furniture'),
      location: 'New Biological Sciences Hostel',
      coverPhotoUrl: null,
      photos: const [],
      status: ListingStatus.available,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  @override
  Future<PaginatedResponse<ListingItem>> fetchListingsPage({
    String query = '',
    int? categoryId,
    double? minPrice,
    double? maxPrice,
    List<ListingStatus>? statusList,
    String? sellerId,
    int limit = 20,
    int offset = 0,
  }) async {
    final filtered = _mockData.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          item.description.toLowerCase().contains(query.toLowerCase()) ||
          item.location.toLowerCase().contains(query.toLowerCase());
      final matchesCategory = categoryId == null || item.category.id == categoryId;
      final matchesStatus = statusList == null || statusList.isEmpty || statusList.contains(item.status);
      final matchesMinPrice = minPrice == null || item.price >= minPrice;
      final matchesMaxPrice = maxPrice == null || item.price <= maxPrice;
      final matchesSeller = sellerId == null || sellerId.isEmpty || item.seller.id == sellerId;

      return matchesQuery &&
          matchesCategory &&
          matchesStatus &&
          matchesMinPrice &&
          matchesMaxPrice &&
          matchesSeller;
    }).toList();

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (offset >= filtered.length) {
      return PaginatedResponse(items: [], limit: limit, offset: offset, hasMore: false);
    }

    final endIndex = (offset + limit).clamp(0, filtered.length);
    final slice = filtered.sublist(offset, endIndex);
    final hasMore = filtered.length > offset + limit;

    return PaginatedResponse(
      items: slice,
      limit: limit,
      offset: offset,
      hasMore: hasMore,
    );
  }

  @override
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    int? categoryId,
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
    double? minPrice,
    double? maxPrice,
    DateTime? fromDate,
    DateTime? toDate,
    String? sellerId,
    int page = 1,
    int limit = 50,
    int offset = 0,
  }) async {
    var items = _mockData.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          item.description.toLowerCase().contains(query.toLowerCase()) ||
          item.location.toLowerCase().contains(query.toLowerCase());
      final matchesCategory = category == 'All' ||
          item.category.name == category ||
          (categoryId != null && item.category.id == categoryId);
      final matchesStatus = statusFilter == null || item.status == statusFilter;
      final matchesMinPrice = minPrice == null || item.price >= minPrice;
      final matchesMaxPrice = maxPrice == null || item.price <= maxPrice;
      final matchesFromDate = fromDate == null || item.createdAt.isAfter(fromDate);
      final matchesToDate = toDate == null || item.createdAt.isBefore(toDate);
      final matchesSeller = sellerId == null || sellerId.isEmpty || item.seller.id == sellerId;

      return matchesQuery &&
          matchesCategory &&
          matchesStatus &&
          matchesMinPrice &&
          matchesMaxPrice &&
          matchesFromDate &&
          matchesToDate &&
          matchesSeller;
    }).toList();

    switch (sortOption) {
      case SortOption.oldest:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.priceLowToHigh:
        items.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SortOption.priceHighToLow:
        items.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOption.discountHighToLow:
        items.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOption.newest:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    final effectiveOffset = offset > 0 ? offset : (page > 1 ? (page - 1) * limit : 0);
    if (effectiveOffset >= items.length) return [];
    final endIndex = (effectiveOffset + limit).clamp(0, items.length);
    return items.sublist(effectiveOffset, endIndex);
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
  Future<ListingItem> addListing(
    ListingItem item, {
    List<String> photoKeys = const [],
  }) async {
    _mockData.insert(0, item);
    return item;
  }

  @override
  Future<ListingItem> updateListing(
    String id, {
    String? title,
    String? description,
    double? price,
    int? categoryId,
    String? location,
  }) async {
    final index = _mockData.indexWhere((it) => it.id == id);
    if (index == -1) throw Exception('Listing not found');

    CategoryRef newCat = _mockData[index].category;
    if (categoryId != null) {
      newCat = _categories.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => CategoryRef(id: categoryId, name: 'Other'),
      );
    }

    final updated = _mockData[index].copyWith(
      title: title,
      description: description,
      price: price,
      category: newCat,
      location: location,
      updatedAt: DateTime.now(),
    );
    _mockData[index] = updated;
    return updated;
  }

  @override
  Future<void> updateStatus(String id, ListingStatus newStatus) async {
    final index = _mockData.indexWhere((item) => item.id == id);
    if (index != -1) {
      _mockData[index] = _mockData[index].copyWith(status: newStatus);
    }
  }

  @override
  Future<void> replacePhotos(String id, List<String> photoKeys) async {
    final index = _mockData.indexWhere((item) => item.id == id);
    if (index != -1) {
      final newPhotos = photoKeys.asMap().entries.map((e) {
        return Photo(
          s3Key: e.value,
          url: 'https://picsum.photos/seed/${e.value}/600/400',
          sortOrder: e.key,
        );
      }).toList();

      _mockData[index] = _mockData[index].copyWith(
        photos: newPhotos,
        coverPhotoUrl: newPhotos.isNotEmpty ? newPhotos.first.url : null,
      );
    }
  }

  @override
  Future<void> deleteListing(String id, {String? reason}) async {
    _mockData.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<CategoryRef>> fetchCategories() async {
    return List.unmodifiable(_categories);
  }

  @override
  Future<CategoryRef> createCategory(String name) async {
    final clean = name.trim();
    final existing = _categories.where(
      (c) => c.name.toLowerCase() == clean.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first;

    final newCat = CategoryRef(id: _categories.length + 1, name: clean);
    _categories.add(newCat);
    return newCat;
  }
}
