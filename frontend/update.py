import os

files = {}

# 1. lib/core/enums/sort_option.dart
files["lib/core/enums/sort_option.dart"] = """enum SortOption {
  newest,
  oldest,
  priceLowToHigh,
  priceHighToLow,
  discountHighToLow,
}
"""

# 2. lib/core/theme/app_theme.dart
files["lib/core/theme/app_theme.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class AppTheme {
  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.8),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5),
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.4),
    bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
    bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.3),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.2),
  );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E3A8A),
      primary: const Color(0xFF1E3A8A),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDBEAFE),
      onPrimaryContainer: const Color(0xFF1E40AF),
      secondary: const Color(0xFF0D9488),
      surface: const Color(0xFFFFFFFF),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      primary: const Color(0xFF3B82F6),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF1E3A8A),
      onPrimaryContainer: const Color(0xFFBFDBFE),
      secondary: const Color(0xFF14B8A6),
      surface: const Color(0xFF1E293B),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    textTheme: _textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B),
      foregroundColor: Color(0xFFF8FAFC),
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF8FAFC)),
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF1E293B),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155), width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
    ),
  );
}
"""

# 3. lib/core/widgets/compact_date_range_picker_dialog.dart
files["lib/core/widgets/compact_date_range_picker_dialog.dart"] = """import 'package:flutter/material.dart';

class CompactDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialDateRange;

  const CompactDateRangePickerDialog({super.key, this.initialDateRange});

  @override
  State<CompactDateRangePickerDialog> createState() => _CompactDateRangePickerDialogState();
}

class _CompactDateRangePickerDialogState extends State<CompactDateRangePickerDialog> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    final now = DateTime.now();

    if (initial != null) {
      _startDate = initial.start;
      _startTime = TimeOfDay.fromDateTime(initial.start);
      _endDate = initial.end;
      _endTime = TimeOfDay.fromDateTime(initial.end);
    } else {
      _startDate = now.subtract(const Duration(days: 7));
      _startTime = const TimeOfDay(hour: 0, minute: 0);
      _endDate = now;
      _endTime = const TimeOfDay(hour: 23, minute: 59);
    }
  }

  void _applyPreset(int days) {
    final now = DateTime.now();
    setState(() {
      _startDate = now.subtract(Duration(days: days));
      _startTime = const TimeOfDay(hour: 0, minute: 0);
      _endDate = now;
      _endTime = const TimeOfDay(hour: 23, minute: 59);
    });
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) _startDate = _endDate;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  DateTimeRange _getRange() {
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
    final end = DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute);
    return DateTimeRange(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.date_range_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('Filter Date & Time', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 16),
            Text('Quick Presets', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(label: const Text('Today', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(0)),
                ActionChip(label: const Text('Past 3 Days', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(3)),
                ActionChip(label: const Text('Past 7 Days', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(7)),
                ActionChip(label: const Text('Past 30 Days', style: TextStyle(fontSize: 12)), onPressed: () => _applyPreset(30)),
              ],
            ),
            const Divider(height: 24),
            _buildDateTimeBox('Start Date & Time', _startDate, _startTime, () => _pickDate(true), () => _pickTime(true), isDark),
            const SizedBox(height: 12),
            _buildDateTimeBox('End Date & Time', _endDate, _endTime, () => _pickDate(false), () => _pickTime(false), isDark),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.of(context).pop('CLEAR'),
                    child: const Text('Clear Filter'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.of(context).pop(_getRange()),
                    child: const Text('Apply Range'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeBox(String title, DateTime date, TimeOfDay time, VoidCallback onTapDate, VoidCallback onTapTime, bool isDark) {
    final dateStr = '\${date.day.toString().padLeft(2, '0')}/\${date.month.toString().padLeft(2, '0')}/\${date.year}';
    final timeStr = time.format(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade300)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTapDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(dateStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onTapTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(timeStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
"""

# 4. lib/features/buy_sell/data/buy_sell_repository.dart
files["lib/features/buy_sell/data/buy_sell_repository.dart"] = """import '../../../core/enums/sort_option.dart';
import '../domain/buy_sell_item.dart';

abstract class IBuySellRepository {
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
  });
  Future<void> addListing(ListingItem item);
  Future<void> updateStatus(String id, ListingStatus newStatus);
}

class ClientSideBuySellRepository implements IBuySellRepository {
  final List<ListingItem> _mockData = [
    ListingItem(
      id: '1',
      title: 'IISc Chemistry Lab Coat (Size M)',
      description: '100% Cotton, clean condition with no chemical stains or tears. Ideal for first-year lab work.',
      costPrice: 850.0,
      sellingPrice: 350.0,
      category: 'Lab Equipment',
      location: 'Sarvam Hostel Block B',
      imageUrl: 'https://picsum.photos/seed/labcoat/400/300',
      status: ListingStatus.available,
      sellerName: 'Aarav Sharma',
      sellerEmail: 'aaravs@iisc.ac.in',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    ListingItem(
      id: '2',
      title: 'Ergonomic Mesh Study Chair',
      description: 'Breathable mesh backrest with adjustable lumbar support and height pneumatic lever.',
      costPrice: 4500.0,
      sellingPrice: 1800.0,
      category: 'Furniture',
      location: 'R-Block Hostel',
      imageUrl: 'https://picsum.photos/seed/chair/400/300',
      status: ListingStatus.available,
      sellerName: 'Priya Nair',
      sellerEmail: 'priyan@iisc.ac.in',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    ListingItem(
      id: '3',
      title: 'Engineering Mathematics by Erwin Kreyszig',
      description: '10th Edition Hardcover. Contains neatly highlighted notes and previous year problem solutions.',
      costPrice: 1200.0,
      sellingPrice: 600.0,
      category: 'Books',
      location: 'Main Library Lawn',
      imageUrl: 'https://picsum.photos/seed/book/400/300',
      status: ListingStatus.reserved,
      sellerName: 'Rahul Verma',
      sellerEmail: 'rahulv@iisc.ac.in',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    ListingItem(
      id: '4',
      title: 'Philips 1.5L Electric Kettle',
      description: 'Stainless steel body with dry-boil auto cut-off protection. Fast boiling for hostel tea.',
      costPrice: 1499.0,
      sellingPrice: 750.0,
      category: 'Electronics',
      location: 'E-Block Hostel',
      imageUrl: 'https://picsum.photos/seed/kettle/400/300',
      status: ListingStatus.sold,
      sellerName: 'Ananya Roy',
      sellerEmail: 'ananyar@iisc.ac.in',
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    ListingItem(
      id: '5',
      title: 'Hero Sprint 21-Speed Mountain Bicycle',
      description: 'Dual disc brakes, front suspension, comes with dual LED lights and sturdy combination lock.',
      costPrice: 12500.0,
      sellingPrice: 5800.0,
      category: 'Cycles',
      location: 'Physics Department Cycle Stand',
      imageUrl: 'https://picsum.photos/seed/cycle/400/300',
      status: ListingStatus.available,
      sellerName: 'Vikram Singh',
      sellerEmail: 'vikrams@iisc.ac.in',
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
  ];

  @override
  Future<List<ListingItem>> fetchListings({
    String query = '',
    String category = 'All',
    SortOption sortOption = SortOption.newest,
    ListingStatus? statusFilter,
  }) async {
    var items = _mockData.where((item) {
      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query.toLowerCase()) ||
          item.description.toLowerCase().contains(query.toLowerCase()) ||
          item.location.toLowerCase().contains(query.toLowerCase());
      final matchesCategory = category == 'All' || item.category == category;
      final matchesStatus = statusFilter == null || item.status == statusFilter;
      return matchesQuery && matchesCategory && matchesStatus;
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
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    return items;
  }

  @override
  Future<void> addListing(ListingItem item) async {
    _mockData.insert(0, item);
  }

  @override
  Future<void> updateStatus(String id, ListingStatus newStatus) async {
    final index = _mockData.indexWhere((item) => item.id == id);
    if (index != -1) {
      _mockData[index] = _mockData[index].copyWith(status: newStatus);
    }
  }
}
"""

# 5. lib/features/buy_sell/providers/buy_sell_providers.dart
files["lib/features/buy_sell/providers/buy_sell_providers.dart"] = """import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/enums/sort_option.dart';
import '../data/buy_sell_repository.dart';
import '../domain/buy_sell_item.dart';

enum ViewMode { grid, list }

final buySellRepositoryProvider = Provider<IBuySellRepository>((ref) {
  return ClientSideBuySellRepository();
});

class BuySellFilterState {
  final String query;
  final String category;
  final SortOption sortOption;
  final ListingStatus? statusFilter;
  final ViewMode viewMode;

  BuySellFilterState({
    this.query = '',
    this.category = 'All',
    this.sortOption = SortOption.newest,
    this.statusFilter,
    this.viewMode = ViewMode.grid,
  });

  BuySellFilterState copyWith({
    String? query,
    String? category,
    SortOption? sortOption,
    ListingStatus? statusFilter,
    bool clearStatusFilter = false,
    ViewMode? viewMode,
  }) {
    return BuySellFilterState(
      query: query ?? this.query,
      category: category ?? this.category,
      sortOption: sortOption ?? this.sortOption,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

final buySellFilterProvider = StateProvider<BuySellFilterState>((ref) => BuySellFilterState());

final buySellListingsProvider = FutureProvider<List<ListingItem>>((ref) async {
  final repo = ref.watch(buySellRepositoryProvider);
  final filter = ref.watch(buySellFilterProvider);

  return repo.fetchListings(
    query: filter.query,
    category: filter.category,
    sortOption: filter.sortOption,
    statusFilter: filter.statusFilter,
  );
});
"""

# 6. lib/features/buy_sell/ui/widgets/buy_sell_filter_controls.dart
files["lib/features/buy_sell/ui/widgets/buy_sell_filter_controls.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/sort_option.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';

class BuySellFilterControls extends ConsumerWidget {
  const BuySellFilterControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(buySellFilterProvider);

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<SortOption>(
            value: filter.sortOption,
            decoration: InputDecoration(
              labelText: 'Sort By',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: const [
              DropdownMenuItem(value: SortOption.newest, child: Text('Newest First')),
              DropdownMenuItem(value: SortOption.oldest, child: Text('Oldest First')),
              DropdownMenuItem(value: SortOption.priceLowToHigh, child: Text('Price: Low to High')),
              DropdownMenuItem(value: SortOption.priceHighToLow, child: Text('Price: High to Low')),
              DropdownMenuItem(value: SortOption.discountHighToLow, child: Text('Highest Discount')),
            ],
            onChanged: (val) {
              if (val != null) {
                ref.read(buySellFilterProvider.notifier).update((state) => state.copyWith(sortOption: val));
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<ListingStatus?>(
            value: filter.statusFilter,
            decoration: InputDecoration(
              labelText: 'Status Filter',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Statuses')),
              DropdownMenuItem(value: ListingStatus.available, child: Text('Available Only')),
              DropdownMenuItem(value: ListingStatus.reserved, child: Text('Reserved Only')),
              DropdownMenuItem(value: ListingStatus.sold, child: Text('Sold Only')),
            ],
            onChanged: (val) {
              ref.read(buySellFilterProvider.notifier).update((state) => state.copyWith(
                statusFilter: val,
                clearStatusFilter: val == null,
              ));
            },
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<ViewMode>(
          segments: const [
            ButtonSegment(value: ViewMode.grid, icon: Icon(Icons.grid_view_rounded, size: 20)),
            ButtonSegment(value: ViewMode.list, icon: Icon(Icons.view_list_rounded, size: 20)),
          ],
          selected: {filter.viewMode},
          onSelectionChanged: (Set<ViewMode> selected) {
            ref.read(buySellFilterProvider.notifier).update((state) => state.copyWith(viewMode: selected.first));
          },
        ),
      ],
    );
  }
}
"""

# 7. lib/features/buy_sell/ui/buy_sell_feed_screen.dart
files["lib/features/buy_sell/ui/buy_sell_feed_screen.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/buy_sell_providers.dart';
import 'widgets/buy_sell_card.dart';
import 'widgets/buy_sell_filter_controls.dart';
import 'widgets/category_filter_bar.dart';
import 'widgets/create_listing_dialog.dart';

class BuySellFeedScreen extends ConsumerWidget {
  const BuySellFeedScreen({super.key});

  static const rawCategories = ['All', 'Lab Equipment', 'Furniture', 'Books', 'Electronics', 'Cycles', 'Other'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(buySellListingsProvider);
    final filter = ref.watch(buySellFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy & Sell Portal'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => CreateListingDialog(
                    onSubmit: (newItem) async {
                      await ref.read(buySellRepositoryProvider).addListing(newItem);
                      ref.invalidate(buySellListingsProvider);
                    },
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Sell Item'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                CategoryFilterBar(
                  categories: rawCategories,
                  selectedCategory: filter.category,
                  onSelected: (cat) {
                    ref.read(buySellFilterProvider.notifier).update((state) => state.copyWith(category: cat));
                  },
                ),
                const SizedBox(height: 12),
                const BuySellFilterControls(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: listingsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No listings found matching criteria.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                if (filter.viewMode == ViewMode.list) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) => BuySellCard(
                      item: items[index],
                      viewMode: filter.viewMode,
                      onStatusChange: (status) async {
                        await ref.read(buySellRepositoryProvider).updateStatus(items[index].id, status);
                        ref.invalidate(buySellListingsProvider);
                      },
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final count = constraints.maxWidth > 1100
                        ? 4
                        : constraints.maxWidth > 750
                            ? 3
                            : constraints.maxWidth > 500
                                ? 2
                                : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        childAspectRatio: 0.82,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => BuySellCard(
                        item: items[index],
                        viewMode: filter.viewMode,
                        onStatusChange: (status) async {
                          await ref.read(buySellRepositoryProvider).updateStatus(items[index].id, status);
                          ref.invalidate(buySellListingsProvider);
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error loading listings: \$err')),
            ),
          ),
        ],
      ),
    );
  }
}
"""

# 8. lib/features/buy_sell/ui/widgets/buy_sell_card.dart
files["lib/features/buy_sell/ui/widgets/buy_sell_card.dart"] = """import 'package:flutter/material.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';
import 'buy_sell_detail_dialog.dart';

class BuySellCard extends StatelessWidget {
  final ListingItem item;
  final ViewMode viewMode;
  final ValueChanged<ListingStatus> onStatusChange;

  const BuySellCard({
    super.key,
    required this.item,
    required this.viewMode,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color cardBg;
    Color borderColor;
    Color statusColor;
    String statusLabel;

    switch (item.status) {
      case ListingStatus.available:
        cardBg = isDark ? const Color(0xFF062E1B) : const Color(0xFFF0FDF4);
        borderColor = isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0);
        statusColor = const Color(0xFF059669);
        statusLabel = 'AVAILABLE';
        break;
      case ListingStatus.reserved:
        cardBg = isDark ? const Color(0xFF2E2406) : const Color(0xFFFEFCE8);
        borderColor = isDark ? Colors.amber.shade800 : Colors.amber.shade300;
        statusColor = Colors.amber.shade800;
        statusLabel = 'RESERVED';
        break;
      case ListingStatus.sold:
        cardBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF3F4F6); // Neutral Grey
        borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB);
        statusColor = const Color(0xFF6B7280);
        statusLabel = 'SOLD OUT';
        break;
    }

    final isSold = item.status == ListingStatus.sold;

    return Card(
      color: cardBg,
      elevation: isSold ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => BuySellDetailDialog(item: item, onStatusChange: onStatusChange),
          );
        },
        child: viewMode == ViewMode.list
            ? Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Opacity(
                        opacity: isSold ? 0.55 : 1.0,
                        child: Image.network(
                          item.imageUrl,
                          width: 110,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 110, height: 90, color: Colors.grey[300], child: const Icon(Icons.image)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isSold ? Colors.grey : null,
                                    decoration: isSold ? TextDecoration.lineThrough : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('₹\${item.sellingPrice.toStringAsFixed(0)}', style: TextStyle(color: isSold ? Colors.grey : Colors.indigo, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text('\${item.sellerName} • \${item.location}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: Opacity(
                            opacity: isSold ? 0.55 : 1.0,
                            child: Image.network(
                              item.imageUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: Colors.grey[300], child: const Icon(Icons.image)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                            child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSold ? Colors.grey : null, decoration: isSold ? TextDecoration.lineThrough : null),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('₹\${item.sellingPrice.toStringAsFixed(0)}', style: TextStyle(color: isSold ? Colors.grey : Colors.indigo, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
"""

# 9. lib/features/lost_found/data/lost_found_repository.dart
files["lib/features/lost_found/data/lost_found_repository.dart"] = """import 'package:flutter/material.dart';
import '../../../core/enums/sort_option.dart';
import '../domain/lost_found_item.dart';

abstract class ILostFoundRepository {
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
  });
  Future<void> submitReport(LostFoundItem report);
}

class ClientSideLostFoundRepository implements ILostFoundRepository {
  final List<LostFoundItem> _mockReports = [
    LostFoundItem(
      id: '1',
      title: 'IISc Student ID Card (Blue Lanyard)',
      description: 'Lost somewhere between Physics Canteen and Main Library. Name on card: Mukund K.',
      category: 'ID Cards',
      location: 'Physics Department / Library Lawn',
      imageUrl: 'https://picsum.photos/seed/idcard/400/300',
      type: PostType.lost,
      eventTime: 'Today at 2:15 PM',
      dateReported: DateTime.now().subtract(const Duration(hours: 3)),
      reporterContact: 'mukundk@iisc.ac.in',
    ),
    LostFoundItem(
      id: '2',
      title: 'Sony WH-1000XM4 Noise Cancelling Headphones',
      description: 'Black carrying case with headphone and auxiliary cable. Left on table near window.',
      category: 'Electronics',
      location: 'Main Library 2nd Floor Reading Room',
      imageUrl: 'https://picsum.photos/seed/headphones/400/300',
      type: PostType.lost,
      eventTime: 'Yesterday at 7:00 PM',
      dateReported: DateTime.now().subtract(const Duration(days: 1)),
      reporterContact: 'sufyana@iisc.ac.in',
    ),
    LostFoundItem(
      id: '3',
      title: 'BoAt Airdopes Wireless Earbuds Case',
      description: 'Found black charging case sitting on bench. Handed over to security guard post #2.',
      category: 'Electronics',
      location: 'Central Canteen Complex',
      imageUrl: 'https://picsum.photos/seed/earbuds/400/300',
      type: PostType.found,
      eventTime: 'Today at 11:30 AM',
      dateReported: DateTime.now().subtract(const Duration(hours: 5)),
      reporterContact: 'dinkyl@iisc.ac.in',
    ),
    LostFoundItem(
      id: '4',
      title: 'Leather Wallet (Brown)',
      description: 'Found brown wallet with driver license and IISc mess card. Kept safely in department office.',
      category: 'Personal Belongings',
      location: 'CSA Department Foyer',
      imageUrl: 'https://picsum.photos/seed/wallet/400/300',
      type: PostType.found,
      eventTime: 'Oct 20, 2026 at 5:00 PM',
      dateReported: DateTime.now().subtract(const Duration(days: 1)),
      reporterContact: 'adithyac@iisc.ac.in',
    ),
  ];

  @override
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
  }) async {
    var list = _mockReports.where((item) {
      final matchesType = type == null || item.type == type;
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          item.title.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          item.location.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q);
      final matchesCategory = category == 'All' || item.category.toLowerCase() == category.toLowerCase();

      bool matchesDate = true;
      if (dateRange != null) {
        matchesDate = item.dateReported.isAfter(dateRange.start.subtract(const Duration(seconds: 1))) &&
            item.dateReported.isBefore(dateRange.end.add(const Duration(seconds: 1)));
      }

      return matchesType && matchesQuery && matchesCategory && matchesDate;
    }).toList();

    if (sortOption == SortOption.oldest) {
      list.sort((a, b) => a.dateReported.compareTo(b.dateReported));
    } else {
      list.sort((a, b) => b.dateReported.compareTo(a.dateReported));
    }

    return list;
  }

  @override
  Future<void> submitReport(LostFoundItem report) async {
    _mockReports.insert(0, report);
  }
}
"""

# 10. lib/features/lost_found/providers/lost_found_providers.dart
files["lib/features/lost_found/providers/lost_found_providers.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/enums/sort_option.dart';
import '../data/lost_found_repository.dart';
import '../domain/lost_found_item.dart';

class LostFoundFilterState {
  final String query;
  final String category;
  final DateTimeRange? dateRange;
  final SortOption sortOption;
  final PostType? typeFilter;

  LostFoundFilterState({
    this.query = '',
    this.category = 'All',
    this.dateRange,
    this.sortOption = SortOption.newest,
    this.typeFilter,
  });

  LostFoundFilterState copyWith({
    String? query,
    String? category,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    SortOption? sortOption,
    PostType? typeFilter,
    bool clearTypeFilter = false,
  }) {
    return LostFoundFilterState(
      query: query ?? this.query,
      category: category ?? this.category,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      sortOption: sortOption ?? this.sortOption,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
    );
  }
}

final lostFoundFilterProvider = StateProvider<LostFoundFilterState>((ref) => LostFoundFilterState());

final lostFoundRepositoryProvider = Provider<ILostFoundRepository>((ref) {
  return ClientSideLostFoundRepository();
});

final lostReportsProvider = FutureProvider<List<LostFoundItem>>((ref) async {
  final repo = ref.watch(lostFoundRepositoryProvider);
  final filter = ref.watch(lostFoundFilterProvider);

  return repo.fetchReports(
    type: PostType.lost,
    query: filter.query,
    category: filter.category,
    dateRange: filter.dateRange,
    sortOption: filter.sortOption,
  );
});

final foundReportsProvider = FutureProvider<List<LostFoundItem>>((ref) async {
  final repo = ref.watch(lostFoundRepositoryProvider);
  final filter = ref.watch(lostFoundFilterProvider);

  return repo.fetchReports(
    type: PostType.found,
    query: filter.query,
    category: filter.category,
    dateRange: filter.dateRange,
    sortOption: filter.sortOption,
  );
});
"""

# 11. lib/features/lost_found/ui/widgets/lost_found_filter_bar.dart
files["lib/features/lost_found/ui/widgets/lost_found_filter_bar.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/widgets/compact_date_range_picker_dialog.dart';
import '../../providers/lost_found_providers.dart';

class LostFoundFilterBar extends ConsumerWidget {
  const LostFoundFilterBar({super.key});

  static const categories = ['All', 'ID Cards', 'Electronics', 'Personal Belongings', 'Keys', 'Documents', 'Other'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(lostFoundFilterProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = filter.category == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: isSelected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onSelected: (selected) {
                      ref.read(lostFoundFilterProvider.notifier).update(
                        (state) => state.copyWith(category: selected ? cat : 'All'),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<SortOption>(
                  value: filter.sortOption,
                  decoration: InputDecoration(
                    labelText: 'Sort By',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: SortOption.newest, child: Text('Newest First')),
                    DropdownMenuItem(value: SortOption.oldest, child: Text('Oldest First')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(lostFoundFilterProvider.notifier).update(
                        (state) => state.copyWith(sortOption: val),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  filter.dateRange == null
                      ? 'Date & Time'
                      : '\${filter.dateRange!.start.day}/\${filter.dateRange!.start.month} - \${filter.dateRange!.end.day}/\${filter.dateRange!.end.month}',
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: () async {
                  final result = await showDialog(
                    context: context,
                    builder: (ctx) => CompactDateRangePickerDialog(initialDateRange: filter.dateRange),
                  );
                  if (result == 'CLEAR') {
                    ref.read(lostFoundFilterProvider.notifier).update(
                      (state) => state.copyWith(clearDateRange: true),
                    );
                  } else if (result is DateTimeRange) {
                    ref.read(lostFoundFilterProvider.notifier).update(
                      (state) => state.copyWith(dateRange: result),
                    );
                  }
                },
              ),
              if (filter.dateRange != null || filter.category != 'All' || filter.query.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear All Filters',
                  icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.red),
                  onPressed: () {
                    ref.read(lostFoundFilterProvider.notifier).state = LostFoundFilterState();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
"""

# 12. lib/features/lost_found/ui/widgets/lost_found_column.dart
files["lib/features/lost_found/ui/widgets/lost_found_column.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'lost_found_card.dart';
import 'report_item_dialog.dart';

class LostFoundColumn extends ConsumerWidget {
  final String title;
  final IconData icon;
  final Color headerColor;
  final String buttonText;
  final PostType postType;
  final AsyncValue<List<LostFoundItem>> asyncData;

  const LostFoundColumn({
    super.key,
    required this.title,
    required this.icon,
    required this.headerColor,
    required this.buttonText,
    required this.postType,
    required this.asyncData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: headerColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: headerColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: headerColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: headerColor,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: headerColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => ReportItemDialog(
                      postType: postType,
                      onSubmit: (report) async {
                        await ref.read(lostFoundRepositoryProvider).submitReport(report);
                        ref.invalidate(lostReportsProvider);
                        ref.invalidate(foundReportsProvider);
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: Text(buttonText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: asyncData.when(
            data: (items) => items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('No \${title.toLowerCase()} matching filter.', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => LostFoundCard(item: items[index]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: \$err')),
          ),
        ),
      ],
    );
  }
}
"""

# 13. lib/features/lost_found/ui/lost_found_feed_screen.dart
files["lib/features/lost_found/ui/lost_found_feed_screen.dart"] = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'widgets/lost_found_column.dart';
import 'widgets/lost_found_filter_bar.dart';

class LostFoundFeedScreen extends ConsumerWidget {
  const LostFoundFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lostAsync = ref.watch(lostReportsProvider);
    final foundAsync = ref.watch(foundReportsProvider);

    final isDesktop = MediaQuery.of(context).size.width > 750;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lost & Found Portal'),
      ),
      body: Column(
        children: [
          const LostFoundFilterBar(),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: LostFoundColumn(
                            title: 'Lost Items',
                            icon: Icons.search_off_rounded,
                            headerColor: Colors.rose.shade700,
                            buttonText: 'Report Lost',
                            postType: PostType.lost,
                            asyncData: lostAsync,
                          ),
                        ),
                        const SizedBox(width: 20),
                        const VerticalDivider(width: 1, thickness: 1),
                        const SizedBox(width: 20),
                        Expanded(
                          child: LostFoundColumn(
                            title: 'Found Items',
                            icon: Icons.check_circle_outline_rounded,
                            headerColor: Colors.teal.shade700,
                            buttonText: 'Report Found',
                            postType: PostType.found,
                            asyncData: foundAsync,
                          ),
                        ),
                      ],
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(icon: Icon(Icons.search_off_rounded), text: 'Lost Items'),
                              Tab(icon: Icon(Icons.check_circle_outline_rounded), text: 'Found Items'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: TabBarView(
                              children: [
                                LostFoundColumn(
                                  title: 'Lost Items',
                                  icon: Icons.search_off_rounded,
                                  headerColor: Colors.rose.shade700,
                                  buttonText: 'Report Lost',
                                  postType: PostType.lost,
                                  asyncData: lostAsync,
                                ),
                                LostFoundColumn(
                                  title: 'Found Items',
                                  icon: Icons.check_circle_outline_rounded,
                                  headerColor: Colors.teal.shade700,
                                  buttonText: 'Report Found',
                                  postType: PostType.found,
                                  asyncData: foundAsync,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
"""

# 14. lib/features/lost_found/ui/widgets/lost_found_card.dart
files["lib/features/lost_found/ui/widgets/lost_found_card.dart"] = """import 'package:flutter/material.dart';
import '../../domain/lost_found_item.dart';
import 'lost_found_detail_dialog.dart';

class LostFoundCard extends StatelessWidget {
  final LostFoundItem item;

  const LostFoundCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final isLost = item.type == PostType.lost;
    final badgeColor = isLost ? Colors.rose.shade700 : Colors.teal.shade700;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => LostFoundDetailDialog(item: item),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(
                  item.imageUrl,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: Colors.grey[200],
                    child: const Center(child: Icon(Icons.broken_image, size: 40)),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isLost ? 'LOST' : 'FOUND',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          item.eventTime,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.location,
                          style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        label: Text(item.category, style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(
                        'Contact: \${item.reporterContact}',
                        style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""

# 15. lib/features/lost_found/ui/widgets/lost_found_detail_dialog.dart
files["lib/features/lost_found/ui/widgets/lost_found_detail_dialog.dart"] = """import 'package:flutter/material.dart';
import '../../domain/lost_found_item.dart';

class LostFoundDetailDialog extends StatelessWidget {
  final LostFoundItem item;

  const LostFoundDetailDialog({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLost = item.type == PostType.lost;
    final themeColor = isLost ? Colors.rose.shade700 : Colors.teal.shade700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(
                  item.imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    child: Icon(isLost ? Icons.search_off : Icons.check_circle, size: 50, color: Colors.grey),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: themeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isLost ? 'LOST ITEM' : 'FOUND ITEM',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withOpacity(0.5),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(item.title, style: Theme.of(context).textTheme.headlineMedium),
                        ),
                        Chip(label: Text(item.category), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 18, color: themeColor),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Location: \${item.location}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 18, color: themeColor),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Time: \${item.eventTime}', style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.contacts_outlined, size: 18, color: themeColor),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Reporter: \${item.reporterContact}', style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Description', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(item.description, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                border: Border(top: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Contact info copied: \${item.reporterContact}')),
                    );
                  },
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: Text('Contact Reporter (\${item.reporterContact})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""

# Apply all files
modified_files = []
for path, code in files.items():
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "w") as f:
        f.write(code)
    modified_files.append(path)

print("=== EXPORTED UPDATES SUMMARY ===")
print(f"Successfully generated/updated {len(modified_files)} files in total:")
for i, f in enumerate(modified_files, 1):
    print(f" {i:2d}. {f}")
