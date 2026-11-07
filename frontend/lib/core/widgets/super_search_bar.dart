import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';
import '../../features/academics/providers/academics_providers.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/buy_sell/domain/buy_sell_item.dart';
import '../../features/buy_sell/providers/buy_sell_providers.dart';
import '../../features/buy_sell/ui/listing_links.dart';
import '../../features/lost_found/domain/lost_found_item.dart';
import '../../features/lost_found/providers/lost_found_providers.dart';
import '../../features/lost_found/ui/widgets/lost_found_detail_dialog.dart';
import '../../features/events/domain/event_models.dart';
import '../../features/events/providers/events_providers.dart';
import '../../features/mess/mess_models.dart';
import '../../features/placement/domain/placement_models.dart';
import '../../features/placement/providers/placement_providers.dart';

/// Companies whose name or industry matches (Placement Hub), searched on the server.
/// Placement Hub is for signed-in users only (the API answers guests with 401), so guests don't search it.
final _companySearchProvider = FutureProvider.autoDispose.family<List<Company>, String>((ref, q) {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest) return const <Company>[];
  return ref.watch(placementRepositoryProvider).fetchCompanies(query: q, limit: 6);
});

/// Events (now, upcoming and past) whose title, description or place matches, searched on the server.
final _eventSearchProvider = FutureProvider.autoDispose.family<List<CampusEvent>, String>((ref, q) =>
    ref.watch(eventsRepositoryProvider).fetchEvents(
        when: const {EventWhen.present, EventWhen.upcoming, EventWhen.past}, query: q, limit: 6));

/// Listings, lost reports and found reports that match, searched on the server. These are the search's own
/// lookups: typing here doesn't set the Buy & Sell or Lost & Found filters, so those pages stay unfiltered.
final _listingSearchProvider = FutureProvider.autoDispose.family<List<ListingItem>, String>((ref, q) =>
    ref.watch(buySellRepositoryProvider).fetchListings(query: q, limit: 6));
final _lostSearchProvider = FutureProvider.autoDispose.family<List<LostFoundItem>, String>((ref, q) =>
    ref.watch(lostFoundRepositoryProvider).fetchReports(type: PostType.lost, query: q, limit: 6));
final _foundSearchProvider = FutureProvider.autoDispose.family<List<LostFoundItem>, String>((ref, q) =>
    ref.watch(lostFoundRepositoryProvider).fetchReports(type: PostType.found, query: q, limit: 6));

class SuperSearchBar extends ConsumerStatefulWidget {
  const SuperSearchBar({super.key});

  @override
  ConsumerState<SuperSearchBar> createState() => _SuperSearchBarState();
}

class _SuperSearchBarState extends ConsumerState<SuperSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isFocused = false;
  Timer? _debounceTimer;
  bool _isDebouncing = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    _removeOverlay();
    setState(() => _isDebouncing = false);
  }

  void _showOverlay() {
    _removeOverlay();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 6),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).cardColor,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Consumer(
                builder: (context, ref, _) {
                  final query = _searchController.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Type to search listings, lost & found, courses (e.g. DS252), companies, events and messes…',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    );
                  }

                  final activeTab = ref.watch(tabIndexProvider);
                  final buySellAsync = ref.watch(_listingSearchProvider(query));
                  final lostAsync = ref.watch(_lostSearchProvider(query));
                  final foundAsync = ref.watch(_foundSearchProvider(query));

                  final List<ListingItem> buySellMatches =
                      buySellAsync.maybeWhen(data: (items) => items, orElse: () => const <ListingItem>[]);
                  final List<LostFoundItem> lostMatches =
                      lostAsync.maybeWhen(data: (items) => items, orElse: () => const <LostFoundItem>[]);
                  final List<LostFoundItem> foundMatches =
                      foundAsync.maybeWhen(data: (items) => items, orElse: () => const <LostFoundItem>[]);

                  final courseMatchList = ref.watch(allCoursesProvider).maybeWhen(
                    data: (all) => all.where((c) => courseMatches(c, query)).take(8).toList(),
                    orElse: () => const <CourseWithDepartment>[],
                  );
                  final companiesAsync = ref.watch(_companySearchProvider(query));
                  final currentUser = ref.watch(currentUserProvider);
                  final isGuest = currentUser == null || currentUser.isGuest;
                  final eventsAsync = ref.watch(_eventSearchProvider(query));
                  final messMatches = ref.watch(messListProvider).maybeWhen(
                    data: (list) => list.messes.where((m) => m.name.toLowerCase().contains(query)).toList(),
                    orElse: () => const <Mess>[],
                  );

                  // One section per tab, the current tab's first.
                  String header(int tab, String name) =>
                      '$name RESULTS${tab == activeTab ? ' (CURRENT TAB)' : ''}';
                  final sections = <int, List<Widget>>{
                    0: [
                      _buildSectionHeader(header(0, 'BUY & SELL')),
                      ..._buildBuySellItems(context, ref, buySellMatches),
                    ],
                    1: [
                      _buildSectionHeader(header(1, 'LOST & FOUND')),
                      if (lostMatches.isEmpty && foundMatches.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                          child: Text('No matching Lost & Found reports',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      ..._buildLostFoundItems(context, ref, lostMatches, 'Lost'),
                      ..._buildLostFoundItems(context, ref, foundMatches, 'Found'),
                    ],
                    2: [
                      _buildSectionHeader(header(2, 'COURSES')),
                      ..._buildCourseItems(context, courseMatchList),
                    ],
                    3: [
                      _buildSectionHeader(header(3, 'PLACEMENT HUB')),
                      if (isGuest)
                        ..._none('Sign in to search Placement Hub companies')
                      else ...companiesAsync.when(
                        loading: _loading,
                        error: (_, __) => _none('Couldn\'t search companies'),
                        data: (companies) => companies.isEmpty
                            ? _none('No matching companies')
                            : [
                                for (final c in companies)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.business_center_outlined, size: 20),
                                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      [
                                        if (c.industry != null) c.industry!,
                                        if (c.ctcMin != null) formatCtc(c.ctcMin, c.ctcMax),
                                        if (c.latestYear != null) '${c.latestYearSelected} selected in ${c.latestYear}',
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      _removeOverlay();
                                      context.push('/placements/${c.id}');
                                    },
                                  ),
                              ],
                      ),
                    ],
                    4: [
                      _buildSectionHeader(header(4, 'EVENTS & MESS MENUS')),
                      for (final m in messMatches)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.restaurant_menu_rounded, size: 20),
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(m.today.isEmpty ? 'Mess menu' : 'Today: ${m.today.first.items}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            _removeOverlay();
                            context.push('/mess?mess=${m.id}');
                          },
                        ),
                      ...eventsAsync.when(
                        loading: _loading,
                        error: (_, __) => _none('Couldn\'t search events'),
                        data: (events) => events.isEmpty && messMatches.isEmpty
                            ? _none('No matching events')
                            : [
                                for (final e in events)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.event_outlined, size: 20),
                                    title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      [
                                        '${e.startTime.day}/${e.startTime.month}/${e.startTime.year}',
                                        if (e.location != null) e.location!,
                                        if (e.when == EventWhen.past) 'past',
                                      ].join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      _removeOverlay();
                                      context.push('/events/${e.id}');
                                    },
                                  ),
                              ],
                      ),
                    ],
                  };
                  final order = [activeTab, ...[0, 1, 2, 3, 4].where((t) => t != activeTab)];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < order.length; i++) ...[
                          if (i > 0) const Divider(),
                          ...?sections[order[i]],
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  List<Widget> _loading() => const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: SizedBox(height: 2, child: LinearProgressIndicator()),
        ),
      ];

  List<Widget> _none(String text) => [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ];

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.indigo,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  List<Widget> _buildBuySellItems(BuildContext context, WidgetRef ref, List<ListingItem> items) {
    if (items.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Text('No matching Buy & Sell items', style: TextStyle(fontSize: 12, color: Colors.grey)),
        )
      ];
    }
    return items.map((item) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.shopping_bag_outlined, size: 20),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('₹${item.price.toStringAsFixed(0)} • ${item.location}'),
        onTap: () {
          _removeOverlay();
          // Switch to Buy & Sell tab without adding to browser history
          ref.read(tabIndexProvider.notifier).state = 0;
          showListingDetail(context, item);
        },
      );
    }).toList();
  }

  List<Widget> _buildCourseItems(BuildContext context, List<CourseWithDepartment> items) {
    if (items.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Text('No matching courses', style: TextStyle(fontSize: 12, color: Colors.grey)),
        )
      ];
    }
    return items.map((c) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.school_outlined, size: 20),
        title: Text('${c.course.code} · ${c.course.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(c.departmentName, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () {
          _removeOverlay();
          context.go('/courses/${c.course.id}');
        },
      );
    }).toList();
  }

  List<Widget> _buildLostFoundItems(BuildContext context, WidgetRef ref, List<LostFoundItem> items, String type) {
    if (items.isEmpty) return [];
    return items.map((item) {
      final dateStr = '${item.occurredAt.day}/${item.occurredAt.month}/${item.occurredAt.year}';
      return ListTile(
        dense: true,
        leading: Icon(
          type == 'Lost' ? Icons.search_off : Icons.check_circle_outline,
          size: 20,
          color: type == 'Lost' ? Colors.red : Colors.teal,
        ),
        title: Text('[$type] ${item.displayTitle}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${item.category.name} • ${item.location} • $dateStr', maxLines: 1, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        onTap: () {
          _removeOverlay();
          // Switch to Lost & Found tab without adding to browser history
          ref.read(tabIndexProvider.notifier).state = 1;
          showDialog(
            context: context,
            builder: (ctx) => LostFoundDetailDialog(item: item),
          );
        },
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          if (focused) {
            _showOverlay();
          } else {
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && !_isFocused) _removeOverlay();
            });
          }
        },
        child: SizedBox(
          height: 40,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search everything: listings, lost & found, courses, companies, events…',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _isDebouncing
                  ? const Padding(
                      padding: EdgeInsets.all(11.0),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: _clearSearch,
                        )
                      : null),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (val) {
              if (_overlayEntry == null) {
                _showOverlay();
              }
              _debounceTimer?.cancel();
              if (val.trim().isEmpty) {
                setState(() => _isDebouncing = false);
                _overlayEntry?.markNeedsBuild();
              } else {
                setState(() => _isDebouncing = true);
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() => _isDebouncing = false);
                    _overlayEntry?.markNeedsBuild();
                  }
                });
              }
            },
          ),
        ),
      ),
    );
  }
}
