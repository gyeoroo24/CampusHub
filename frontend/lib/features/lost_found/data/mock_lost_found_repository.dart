import 'package:flutter/material.dart';
import '../../../core/enums/sort_option.dart';
import '../domain/lost_found_item.dart';
import 'lost_found_repository.dart';

/// In-memory mock repository for Lost & Found reports.
class MockLostFoundRepository implements ILostFoundRepository {
  final List<LostFoundItem> _mockReports = [
    // --- 1 image, landscape ---
    LostFoundItem(
      id: '1',
      reporterId: 'user_mukund',
      reporterContact: 'mukundk@iisc.ac.in',
      title: 'IISc Student ID Card (Blue Lanyard)',
      description:
          'Lost somewhere between Physics Canteen and Main Library. '
          'Name on card: Mukund K., Roll No: 24CSE0042. '
          'Blue fabric lanyard with IISc logo clip. Please contact ASAP.',
      category: 'ID Cards',
      location: 'Physics Department / Library Lawn',
      imageUrls: const ['https://picsum.photos/seed/idcard/600/400'],
      type: PostType.lost,
      eventTime: 'Today at 2:15 PM',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    // --- 3 images: landscape, portrait, square ---
    LostFoundItem(
      id: '2',
      reporterId: 'user_sufyan',
      reporterContact: 'sufyana@iisc.ac.in',
      title: 'Sony WH-1000XM4 Noise Cancelling Headphones',
      description:
          'Black carrying case with headphone and auxiliary cable inside. '
          'Left on table near window in the reading room. Serial no. on label inside case. '
          'Model: WH-1000XM4, Colour: Midnight Black. Very urgent — they are expensive.',
      category: 'Electronics',
      location: 'Main Library 2nd Floor Reading Room',
      imageUrls: const [
        'https://picsum.photos/seed/headphones1/700/450', // landscape
        'https://picsum.photos/seed/headphones2/400/550', // portrait
        'https://picsum.photos/seed/headphones3/500/500', // square
      ],
      type: PostType.lost,
      eventTime: 'Yesterday at 7:00 PM',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(days: 1)),
    ),
    // --- 2 images, both square ---
    LostFoundItem(
      id: '3',
      reporterId: 'user_dinky',
      reporterContact: 'dinkyl@iisc.ac.in',
      title: 'BoAt Airdopes Wireless Earbuds Case',
      description:
          'Found black charging case (no earbuds inside) sitting on canteen bench. '
          'Handed over to security guard post #2. Please bring ID proof when claiming.',
      category: 'Electronics',
      location: 'Central Canteen Complex',
      imageUrls: const [
        'https://picsum.photos/seed/earbuds1/500/500',
        'https://picsum.photos/seed/earbuds2/500/500',
      ],
      type: PostType.found,
      eventTime: 'Today at 11:30 AM',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    // --- 1 image, portrait ---
    LostFoundItem(
      id: '4',
      reporterId: 'user_adithya',
      reporterContact: 'adithyac@iisc.ac.in',
      title: 'Leather Wallet (Brown)',
      description:
          'Found brown bifold wallet containing driver\'s licence, IISc mess card, '
          'and some cash. No credit cards found. Kept safely in CSA department office. '
          'Contact CSA office (Room 104) with proof of identity.',
      category: 'Personal Belongings',
      location: 'CSA Department Foyer',
      imageUrls: const ['https://picsum.photos/seed/wallet/400/600'],
      type: PostType.found,
      eventTime: 'Oct 20, 2026 at 5:00 PM',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // --- 4 images: ultra-wide, portrait, landscape, square ---
    LostFoundItem(
      id: '5',
      reporterId: 'user_ramesh',
      reporterContact: 'rameshk@iisc.ac.in',
      title: 'Blue Titan Wristwatch (Analog)',
      description:
          'Lost at the basketball court near SERC building. '
          'Titan Edge series, blue dial, stainless steel strap. '
          'Engraved "Always" on the case back. Sentimental value.',
      category: 'Personal Belongings',
      location: 'SERC Basketball Court',
      imageUrls: const [
        'https://picsum.photos/seed/watch1/800/350',
        'https://picsum.photos/seed/watch2/400/600',
        'https://picsum.photos/seed/watch3/600/400',
        'https://picsum.photos/seed/watch4/500/500',
      ],
      type: PostType.lost,
      eventTime: 'Yesterday at 6:00 PM',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
    ),
    // --- no images (tests empty-state gracefully) ---
    LostFoundItem(
      id: '6',
      reporterId: 'user_pooja',
      reporterContact: 'poojas@iisc.ac.in',
      title: 'Prescription Glasses (Rimless)',
      description:
          'Rimless frameless rectangular glasses in a black hard case. '
          'Power: L -2.5 R -2.0. Left at the Gymkhana chess club table.',
      category: 'Personal Belongings',
      location: 'Gymkhana Building — Chess Club Area',
      imageUrls: const [],
      type: PostType.lost,
      eventTime: '3 days ago',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(days: 3)),
    ),
    // --- 2 images: landscape wide, landscape standard ---
    LostFoundItem(
      id: '7',
      reporterId: 'user_gymkhana',
      reporterContact: 'gymkhana@iisc.ac.in',
      title: 'Decathlon Quechua 20L Hiking Backpack (Red)',
      description:
          'Red and black daypack found near Tata Institute. '
          'Contains a water bottle and a rain cover. '
          'Submitted to Gymkhana reception desk.',
      category: 'Bags',
      location: 'Tata Institute of Fundamental Research Gate Area',
      imageUrls: const [
        'https://picsum.photos/seed/bag1/800/400',
        'https://picsum.photos/seed/bag2/600/400',
      ],
      type: PostType.found,
      eventTime: 'Oct 21, 2026 at 9:00 AM',
      status: ReportStatus.open,
      dateReported: DateTime.now().subtract(const Duration(days: 1, hours: 12)),
    ),
  ];

  @override
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    int page = 1,
    int limit = 50,
  }) async {
    var list = _mockReports.where((item) {
      final matchesType = type == null || item.type == type;
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          item.title.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          item.location.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q);
      final matchesCategory =
          category == 'All' || item.category.toLowerCase() == category.toLowerCase();

      bool matchesDate = true;
      if (dateRange != null) {
        matchesDate = item.dateReported
                .isAfter(dateRange.start.subtract(const Duration(seconds: 1))) &&
            item.dateReported.isBefore(dateRange.end.add(const Duration(seconds: 1)));
      }

      return matchesType && matchesQuery && matchesCategory && matchesDate;
    }).toList();

    if (sortOption == SortOption.oldest) {
      list.sort((a, b) => a.dateReported.compareTo(b.dateReported));
    } else {
      list.sort((a, b) => b.dateReported.compareTo(a.dateReported));
    }

    final startIndex = (page - 1) * limit;
    if (startIndex >= list.length) return [];
    final endIndex = (startIndex + limit).clamp(0, list.length);
    return list.sublist(startIndex, endIndex);
  }

  @override
  Future<LostFoundItem?> getReportById(String id) async {
    try {
      return _mockReports.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LostFoundItem> submitReport(LostFoundItem report) async {
    _mockReports.insert(0, report);
    return report;
  }

  @override
  Future<void> resolveReport(String id) async {
    final index = _mockReports.indexWhere((item) => item.id == id);
    if (index != -1) {
      _mockReports[index] = _mockReports[index].copyWith(status: ReportStatus.resolved);
    }
  }

  @override
  Future<void> deleteReport(String id) async {
    _mockReports.removeWhere((item) => item.id == id);
  }
}
