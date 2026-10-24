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
  static final List<CategoryRef> _categories = [
    const CategoryRef(id: 1, name: 'ID Cards'),
    const CategoryRef(id: 2, name: 'Electronics'),
    const CategoryRef(id: 3, name: 'Personal Belongings'),
    const CategoryRef(id: 4, name: 'Bags'),
    const CategoryRef(id: 5, name: 'Keys'),
    const CategoryRef(id: 6, name: 'Others'),
  ];

  static final List<LostFoundItem> _mockReports = [
    // 1 (Lost)
    LostFoundItem(
      id: '1',
      title: 'IISc Student ID Card (Red Lanyard)',
      kind: PostType.lost,
      description: 'Belongs to Mukund K., Roll No: 24CSE0042. Red CSA lanyard attached with hostel key ring. Misplaced near Physics canteen or library lawn.',
      category: const CategoryRef(id: 1, name: 'ID Cards'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 3)),
      location: 'Physics Department / Library Lawn',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1578852612716-854e51480097?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_1', url: 'https://images.unsplash.com/photo-1578852612716-854e51480097?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_mukund', name: 'Mukund K.'),
      reporterContact: const Contact(email: 'mukundk@iisc.ac.in', phone: '+919876543210'),
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    // 2 (Lost)
    LostFoundItem(
      id: '2',
      title: 'Sony WH-1000XM4 Headphones',
      kind: PostType.lost,
      description: 'Black noise-cancelling over-ear headphones in original zippered case. Left on table near window in the 2nd floor reading room.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1)),
      location: 'Main Library 2nd Floor Reading Room',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_2a', url: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_2b', url: 'https://images.unsplash.com/photo-1583394838336-acd977736f90?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
        Photo(s3Key: 'mock_lf_2c', url: 'https://images.unsplash.com/photo-1484704849700-f032a568e944?w=700&auto=format&fit=crop&q=80', sortOrder: 2),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_sufyan', name: 'Sufyan Azam'),
      reporterContact: const Contact(email: 'sufyana@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    // 3 (Found)
    LostFoundItem(
      id: '3',
      title: 'AirPods Pro Charging Case',
      kind: PostType.found,
      description: 'White charging case (empty inside) found sitting on wooden bench near Nescafe kiosk. Deposited with kiosk manager.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      location: 'Nescafe Kiosk Outdoor Bench',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1588423771073-b8903fbb85b5?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_3a', url: 'https://images.unsplash.com/photo-1588423771073-b8903fbb85b5?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_3b', url: 'https://images.unsplash.com/photo-1600294037681-c80b4cb5b434?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_ananya', name: 'Ananya Roy'),
      reporterContact: const Contact(email: 'ananyar@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
    ),
    // 4 (Found)
    LostFoundItem(
      id: '4',
      title: 'Brass Godrej Door Key',
      kind: PostType.found,
      description: 'Single brass door key with blue plastic ring marker. Found on the pathway heading toward Gymkhana ground.',
      category: const CategoryRef(id: 4, name: 'Keys'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 18)),
      location: 'Pathway near Gymkhana Ground',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1582139329536-e7284fece509?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_4', url: 'https://images.unsplash.com/photo-1582139329536-e7284fece509?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_rahul', name: 'Rahul Verma'),
      reporterContact: const Contact(email: 'rahulv@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(hours: 18)),
    ),
    // 5 (Lost)
    LostFoundItem(
      id: '5',
      title: 'Milton 750ml Thermosteel Flask',
      kind: PostType.lost,
      description: 'Matte black stainless steel flask with "I Love IISc" sticker on side. Left behind in LH-1 lecture hall.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 6)),
      location: 'Old Lecture Hall Complex Room 1',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_5a', url: 'https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_5b', url: 'https://images.unsplash.com/photo-1570784332176-fdd73da66f03?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_sneha', name: 'Sneha Iyer'),
      reporterContact: const Contact(email: 'snehai@iisc.ac.in', phone: '+919876543215'),
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
    // 6 (Found)
    LostFoundItem(
      id: '6',
      title: 'Casio fx-991EX Calculator',
      kind: PostType.found,
      description: 'Scientific calculator with name sticker "Priya N." on back. Found in Department of Mathematics seminar room.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 14)),
      location: 'Dept of Mathematics Seminar Room',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1611125832047-1d7ad1e8e48f?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_6a', url: 'https://images.unsplash.com/photo-1611125832047-1d7ad1e8e48f?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_6b', url: 'https://images.unsplash.com/photo-1587145820266-a5951ee6f620?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_vikram', name: 'Vikram Singh'),
      reporterContact: const Contact(email: 'vikrams@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(hours: 14)),
    ),
    // 7 (Lost - No Photo placeholder test)
    LostFoundItem(
      id: '7',
      title: 'Bunch of 4 Keys with Swiss Knife',
      kind: PostType.lost,
      description: 'Bunch of 4 keys including Godrej room key, cycle lock key, and a red Swiss army knife attached. Lost around Sarvam block. No photos attached.',
      category: const CategoryRef(id: 4, name: 'Keys'),
      occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      location: 'Sarvam Hostel Walkway',
      coverPhotoUrl: null,
      photos: const [],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_karan', name: 'Karan Mehra'),
      reporterContact: const Contact(email: 'karanm@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // 8 (Found)
    LostFoundItem(
      id: '8',
      title: 'IISc Student ID Card (Rohan Sharma)',
      kind: PostType.found,
      description: 'Student ID card of Rohan Sharma (Biological Sciences Dept) found near Biology Canteen. Handed over to security guard.',
      category: const CategoryRef(id: 1, name: 'ID Cards'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 8)),
      location: 'Biological Sciences Canteen',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1578852612716-854e51480097?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_8', url: 'https://images.unsplash.com/photo-1578852612716-854e51480097?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_tanvi', name: 'Tanvi Deshmukh'),
      reporterContact: const Contact(email: 'tanvid@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
    ),
    // 9 (Lost)
    LostFoundItem(
      id: '9',
      title: 'Ray-Ban Wayfarer Glasses',
      kind: PostType.lost,
      description: 'Reading glasses in black matte case. Left on study carrel in library first floor.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
      location: 'Main Library 1st Floor Study Carrels',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1572635196237-14b3f281503f?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_9a', url: 'https://images.unsplash.com/photo-1572635196237-14b3f281503f?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_9b', url: 'https://images.unsplash.com/photo-1511499767150-a48a237f0083?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_aditya', name: 'Aditya Gupta'),
      reporterContact: const Contact(email: 'adityag@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
    ),
    // 10 (Found)
    LostFoundItem(
      id: '10',
      title: 'Lenovo 65W USB-C Charger',
      kind: PostType.found,
      description: 'Laptop charger left plugged into power socket in CDS computer lab room 102. Safe with lab assistant.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
      location: 'CDS Dept Computer Lab 102',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1583863788434-e58a36330cf0?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_10a', url: 'https://images.unsplash.com/photo-1583863788434-e58a36330cf0?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_10b', url: 'https://images.unsplash.com/photo-1609592424368-24cf23055375?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_rohit', name: 'Rohit Kulkarni'),
      reporterContact: const Contact(email: 'rohitk@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
    ),
    // 11 (Lost)
    LostFoundItem(
      id: '11',
      title: 'Blue A4 Clearance Folder',
      kind: PostType.lost,
      description: 'Contains signed hostel clearance form and original fee receipts. Urgent requirement for degree submission.',
      category: const CategoryRef(id: 5, name: 'Documents'),
      occurredAt: DateTime.now().subtract(const Duration(days: 3)),
      location: 'Central Administration Building Unit',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1586075010923-2dd4570fb338?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_11', url: 'https://images.unsplash.com/photo-1586075010923-2dd4570fb338?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_megha', name: 'Megha Rao'),
      reporterContact: const Contact(email: 'meghar@iisc.ac.in', phone: '+919876543225'),
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    // 12 (Found)
    LostFoundItem(
      id: '12',
      title: 'Fastrack Analog Wristwatch',
      kind: PostType.found,
      description: 'Analog wristwatch with silver dial found near Gymkhana badminton court. In working condition.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(days: 2, hours: 8)),
      location: 'Gymkhana Badminton Court Side Bench',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1524805444758-089113d48a6d?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_12a', url: 'https://images.unsplash.com/photo-1524805444758-089113d48a6d?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_12b', url: 'https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_siddharth', name: 'Siddharth Jain'),
      reporterContact: const Contact(email: 'siddharthj@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 8)),
    ),
    // 13 (Lost)
    LostFoundItem(
      id: '13',
      title: 'SanDisk 128GB Type-C Drive',
      kind: PostType.lost,
      description: 'Silver metal dual drive with dissertation LaTeX files and datasets. Left in Aerospace seminar hall.',
      category: const CategoryRef(id: 2, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(days: 3, hours: 4)),
      location: 'Aerospace Dept Seminar Hall',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1624823183493-5f80fa63e1eb?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_13a', url: 'https://images.unsplash.com/photo-1624823183493-5f80fa63e1eb?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_13b', url: 'https://images.unsplash.com/photo-1597872200969-2b65d56bd16b?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_harsh', name: 'Harsh Vardhan'),
      reporterContact: const Contact(email: 'harshv@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 4)),
    ),
    // 14 (Found)
    LostFoundItem(
      id: '14',
      title: 'Navy Blue Curved Umbrella',
      kind: PostType.found,
      description: 'Blue umbrella with curved wooden handle left near Main Library entrance umbrella rack after evening rain.',
      category: const CategoryRef(id: 3, name: 'Personal Belongings'),
      occurredAt: DateTime.now().subtract(const Duration(days: 1, hours: 10)),
      location: 'Main Library Entrance Umbrella Stand',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1534329539061-64caeb388c42?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_14a', url: 'https://images.unsplash.com/photo-1534329539061-64caeb388c42?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_14b', url: 'https://images.unsplash.com/photo-1517400508447-f8dd518b86db?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_divya', name: 'Divya Sen'),
      reporterContact: const Contact(email: 'divyas@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 10)),
    ),
    // 15 (Lost - No Photo placeholder test)
    LostFoundItem(
      id: '15',
      title: 'Gym Locker Padlock Key (L-42)',
      kind: PostType.lost,
      description: 'Small brass padlock key with green plastic tag "L-42". Dropped near Gymkhana gym weights section. No photos attached.',
      category: const CategoryRef(id: 4, name: 'Keys'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 10)),
      location: 'Gymkhana Fitness Center',
      coverPhotoUrl: null,
      photos: const [],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_deepak', name: 'Deepak Mishra'),
      reporterContact: const Contact(email: 'deepakm@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(hours: 10)),
    ),
    // 16 (Found)
    LostFoundItem(
      id: '16',
      title: 'Deep Learning Lecture Notebook',
      kind: PostType.found,
      description: 'Spiral-bound notebook titled "Deep Learning Lecture Notes 2026" found in CSA 254 classroom. Contains detailed diagrams.',
      category: const CategoryRef(id: 5, name: 'Documents'),
      occurredAt: DateTime.now().subtract(const Duration(days: 2, hours: 1)),
      location: 'CSA Department Classroom 254',
      coverPhotoUrl: 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=700&auto=format&fit=crop&q=80',
      photos: const [
        Photo(s3Key: 'mock_lf_16a', url: 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=700&auto=format&fit=crop&q=80', sortOrder: 0),
        Photo(s3Key: 'mock_lf_16b', url: 'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=700&auto=format&fit=crop&q=80', sortOrder: 1),
      ],
      status: ReportStatus.open,
      reporter: const UserRef(id: 'user_tarun', name: 'Tarun Reddy'),
      reporterContact: const Contact(email: 'tarunr@iisc.ac.in'),
      createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 1)),
    )
  ];

  @override
  Future<PaginatedResponse<LostFoundItem>> fetchReportsPage({
    required PostType type,
    String query = '',
    int? categoryId,
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    List<ReportStatus>? statusList,
    String? reporterId,
    int limit = 20,
    int offset = 0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 320));
    final filtered = _mockReports.where((item) {
      final matchesType = item.kind == type;
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          (item.title != null && item.title!.toLowerCase().contains(q)) ||
          item.description.toLowerCase().contains(q) ||
          item.location.toLowerCase().contains(q) ||
          item.category.name.toLowerCase().contains(q);
      final matchesCategory = categoryId == null || item.category.id == categoryId;
      final matchesStatus =
          statusList == null || statusList.isEmpty || statusList.contains(item.status);
      final matchesReporter = reporterId == null || reporterId.isEmpty || item.reporter.id == reporterId;
      final matchesDate = dateRange == null ||
          (item.occurredAt.isAfter(dateRange.start.subtract(const Duration(seconds: 1))) &&
           item.occurredAt.isBefore(dateRange.end.add(const Duration(seconds: 1))));

      return matchesType && matchesQuery && matchesCategory && matchesStatus && matchesReporter && matchesDate;
    }).toList();

    switch (sortOption) {
      case SortOption.oldest:
        filtered.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
        break;
      case SortOption.newest:
      default:
        filtered.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        break;
    }

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
    await Future.delayed(const Duration(milliseconds: 320));
    var list = _mockReports.where((item) {
      final matchesType = type == null || item.kind == type;
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          (item.title != null && item.title!.toLowerCase().contains(q)) ||
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
