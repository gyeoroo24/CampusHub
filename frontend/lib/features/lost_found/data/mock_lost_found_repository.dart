import 'package:flutter/material.dart' show DateTimeRange;
import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/contact.dart';
import '../../../../core/models/page.dart';
import '../../../../core/models/photo.dart';
import '../../../../core/models/user_ref.dart';
import '../domain/lost_found_item.dart';
import 'lost_found_repository.dart';

/// In-memory mock repository for Lost & Found reports.
class MockLostFoundRepository implements ILostFoundRepository {
  final List<CategoryRef> _categories = [
    const CategoryRef(id: 1, name: 'ID Cards'),
    const CategoryRef(id: 2, name: 'Electronics'),
    const CategoryRef(id: 3, name: 'Personal Belongings'),
    const CategoryRef(id: 4, name: 'Bags'),
    const CategoryRef(id: 5, name: 'Keys'),
    const CategoryRef(id: 6, name: 'Others'),
  ];

  late final List<LostFoundItem> _mockReports = [
    // --- 1 image, landscape ---
    LostFoundItem(
      id: '1',
      kind: PostType.lost,
      description:
          'Lost somewhere between Physics Canteen and Main Library. '
          'Name on card: Mukund K., Roll No: 24CSE0042. '
          'Blue fabric lanyard with IISc logo clip. Please contact ASAP.',
      category: const CategoryRef(id: 1, name: 'ID Cards'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 3)),
      location: 'Physics Department / Library Lawn',
      coverPhotoUrl: 'https://picsum.photos/seed/idcard/600/400',
      photos: const [
        Photo(s3Key: 'mock_lf_1', url: 'https://picsum.photos/seed/idcard/600/400', sortOrder: 0),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_mukund', name: 'Mukund K.'),
      reporterContact: const Contact(email: 'mukundk@iisc.ac.in', phone: '+919876543210'),
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    // --- 3 images: landscape, portrait, square ---
    LostFoundItem(
      id: '2',
      kind: PostType.lost,
      description:
          'Black carrying case with headphone and auxiliary cable inside. '
          'Left on table near window in the reading room. Serial no. on label inside case. '
          'Model: WH-1000XM4, Colour: Midnight Black. Very urgent — they are expensive.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1)),
      location: 'Main Library 2nd Floor Reading Room',
      coverPhotoUrl: 'https://picsum.photos/seed/headphones1/700/450',
      photos: const [
        Photo(s3Key: 'mock_lf_2a', url: 'https://picsum.photos/seed/headphones1/700/450', sortOrder: 0),
        Photo(s3Key: 'mock_lf_2b', url: 'https://picsum.photos/seed/headphones2/400/550', sortOrder: 1),
        Photo(s3Key: 'mock_lf_2c', url: 'https://picsum.photos/seed/headphones3/500/500', sortOrder: 2),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_sufyan', name: 'Sufyan Azam'),
      reporterContact: const Contact(email: 'sufyana@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    // --- 2 images, both square ---
    LostFoundItem(
      id: '3',
      kind: PostType.found,
      description:
          'Found black charging case (no earbuds inside) sitting on canteen bench. '
          'Handed over to security guard post #2. Please bring ID proof when claiming.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 5)),
      location: 'Central Canteen Complex',
      coverPhotoUrl: 'https://picsum.photos/seed/earbuds1/500/500',
      photos: const [
        Photo(s3Key: 'mock_lf_3a', url: 'https://picsum.photos/seed/earbuds1/500/500', sortOrder: 0),
        Photo(s3Key: 'mock_lf_3b', url: 'https://picsum.photos/seed/earbuds2/500/500', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_dinky', name: 'Dinky Lakhani'),
      reporterContact: const Contact(email: 'dinkyl@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    // --- 1 image, portrait ---
    LostFoundItem(
      id: '4',
      kind: PostType.found,
      description:
          'Found brown bifold wallet containing driver\'s licence, IISc mess card, '
          'and some cash. No credit cards found. Kept safely in CSA department office. '
          'Contact CSA office (Room 104) with proof of identity.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      location: 'CSA Department Foyer',
      coverPhotoUrl: 'https://picsum.photos/seed/wallet/400/600',
      photos: const [
        Photo(s3Key: 'mock_lf_4', url: 'https://picsum.photos/seed/wallet/400/600', sortOrder: 0),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_adithya', name: 'Adithya Chippa'),
      reporterContact: const Contact(email: 'adithyac@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // --- 4 images ---
    LostFoundItem(
      id: '5',
      kind: PostType.lost,
      description:
          'Lost at the basketball court near SERC building. '
          'Titan Edge series, blue dial, stainless steel strap. '
          'Engraved "Always" on the case back. Sentimental value.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
      location: 'SERC Basketball Court',
      coverPhotoUrl: 'https://picsum.photos/seed/watch1/800/350',
      photos: const [
        Photo(s3Key: 'mock_lf_5a', url: 'https://picsum.photos/seed/watch1/800/350', sortOrder: 0),
        Photo(s3Key: 'mock_lf_5b', url: 'https://picsum.photos/seed/watch2/400/600', sortOrder: 1),
        Photo(s3Key: 'mock_lf_5c', url: 'https://picsum.photos/seed/watch3/600/400', sortOrder: 2),
        Photo(s3Key: 'mock_lf_5d', url: 'https://picsum.photos/seed/watch4/500/500', sortOrder: 3),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_ramesh', name: 'Ramesh K.'),
      reporterContact: const Contact(email: 'rameshk@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
    ),
    // --- no images ---
    LostFoundItem(
      id: '6',
      kind: PostType.lost,
      description:
          'Rimless frameless rectangular glasses in a black hard case. '
          'Power: L -2.5 R -2.0. Left at the Gymkhana chess club table.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(days: 3)),
      location: 'Gymkhana Building — Chess Club Area',
      coverPhotoUrl: null,
      photos: const [],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_pooja', name: 'Pooja S.'),
      reporterContact: const Contact(email: 'poojas@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    // --- 2 images ---
    LostFoundItem(
      id: '7',
      kind: PostType.found,
      description:
          'Red and black daypack found near Tata Institute. '
          'Contains a water bottle and a rain cover. '
          'Submitted to Gymkhana reception desk.',
      category: const CategoryRef(id: 4, name: 'Bags'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1, hours: 12)),
      location: 'Tata Institute of Fundamental Research Gate Area',
      coverPhotoUrl: 'https://picsum.photos/seed/bag1/800/400',
      photos: const [
        Photo(s3Key: 'mock_lf_7a', url: 'https://picsum.photos/seed/bag1/800/400', sortOrder: 0),
        Photo(s3Key: 'mock_lf_7b', url: 'https://picsum.photos/seed/bag2/600/400', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_gymkhana', name: 'Gymkhana Staff'),
      reporterContact: const Contact(email: 'gymkhana@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 12)),
    ),
  ];

  @override
  Future<PaginatedResponse<LostFoundItem>> fetchReportsPage({
    required PostType type,
    String query = '',
    int? categoryId,
    List<ReportStatus>? statusList,
    String? reporterId,
    int limit = 20,
    int offset = 0,
  }) async {
    final filtered = _mockReports.where((item) {
      final matchesType = item.kind == type;
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          item.description.toLowerCase().contains(q) ||
          item.location.toLowerCase().contains(q) ||
          item.category.name.toLowerCase().contains(q);
      final matchesCategory = categoryId == null || item.category.id == categoryId;
      final matchesStatus =
          statusList == null || statusList.isEmpty || statusList.contains(item.status);
      final matchesReporter = reporterId == null || reporterId.isEmpty || item.reporter.id == reporterId;

      return matchesType && matchesQuery && matchesCategory && matchesStatus && matchesReporter;
    }).toList();

    filtered.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

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
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    int? categoryId,
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    List<ReportStatus>? statusList,
    String? reporterId,
    int page = 1,
    int limit = 50,
    int offset = 0,
  }) async {
    var list = _mockReports.where((item) {
      final matchesType = type == null || item.kind == type;
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          item.description.toLowerCase().contains(q) ||
          item.location.toLowerCase().contains(q) ||
          item.category.name.toLowerCase().contains(q);
      final matchesCategory = category == 'All' ||
          item.category.name.toLowerCase() == category.toLowerCase() ||
          (categoryId != null && item.category.id == categoryId);
      final matchesStatus =
          statusList == null || statusList.isEmpty || statusList.contains(item.status);
      final matchesReporter = reporterId == null || reporterId.isEmpty || item.reporter.id == reporterId;

      bool matchesDate = true;
      if (dateRange != null) {
        matchesDate = item.createdAt
                .isAfter(dateRange.start.subtract(const Duration(seconds: 1))) &&
            item.createdAt.isBefore(dateRange.end.add(const Duration(seconds: 1)));
      }

      return matchesType && matchesQuery && matchesCategory && matchesStatus && matchesReporter && matchesDate;
    }).toList();

    if (sortOption == SortOption.oldest) {
      list.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    } else {
      list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    }

    final effectiveOffset = offset > 0 ? offset : (page > 1 ? (page - 1) * limit : 0);
    if (effectiveOffset >= list.length) return [];
    final endIndex = (effectiveOffset + limit).clamp(0, list.length);
    return list.sublist(effectiveOffset, endIndex);
  }

  @override
  Future<LostFoundItem?> getReportById(String id, {PostType type = PostType.lost}) async {
    try {
      return _mockReports.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LostFoundItem> submitReport(
    LostFoundItem report, {
    List<String> photoKeys = const [],
  }) async {
    // Simulate finding possible matches of opposite kind in the same category
    final oppositeKind = report.kind == PostType.lost ? PostType.found : PostType.lost;
    final matches = _mockReports
        .where(
          (r) =>
              r.kind == oppositeKind &&
              r.category.id == report.category.id &&
              r.status == ReportStatus.open,
        )
        .toList();

    final itemWithMatches = report.copyWith(
      possibleMatches: matches.isNotEmpty ? matches : null,
    );

    _mockReports.insert(0, itemWithMatches);
    return itemWithMatches;
  }

  @override
  Future<LostFoundItem> updateReport(
    String id, {
    required PostType type,
    String? description,
    int? categoryId,
    DateTime? occurredAt,
    String? location,
  }) async {
    final index = _mockReports.indexWhere((it) => it.id == id);
    if (index == -1) throw Exception('Report not found');

    CategoryRef newCat = _mockReports[index].category;
    if (categoryId != null) {
      newCat = _categories.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => CategoryRef(id: categoryId, name: 'Other'),
      );
    }

    final updated = _mockReports[index].copyWith(
      description: description,
      category: newCat,
      occurredAt: occurredAt,
      location: location,
      updatedAt: DateTime.now(),
    );
    _mockReports[index] = updated;
    return updated;
  }

  @override
  Future<void> updateStatus(String id, PostType type, ReportStatus status) async {
    final index = _mockReports.indexWhere((item) => item.id == id);
    if (index != -1) {
      _mockReports[index] = _mockReports[index].copyWith(status: status);
    }
  }

  @override
  Future<void> replacePhotos(String id, PostType type, List<String> photoKeys) async {
    final index = _mockReports.indexWhere((item) => item.id == id);
    if (index != -1) {
      final newPhotos = photoKeys.asMap().entries.map((e) {
        return Photo(
          s3Key: e.value,
          url: 'https://picsum.photos/seed/${e.value}/600/400',
          sortOrder: e.key,
        );
      }).toList();

      _mockReports[index] = _mockReports[index].copyWith(
        photos: newPhotos,
        coverPhotoUrl: newPhotos.isNotEmpty ? newPhotos.first.url : null,
      );
    }
  }

  @override
  Future<void> deleteReport(String id, PostType type, {String? reason}) async {
    _mockReports.removeWhere((item) => item.id == id);
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
