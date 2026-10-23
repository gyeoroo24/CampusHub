import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../router/app_router.dart';
import '../../features/buy_sell/providers/buy_sell_providers.dart';
import '../../features/buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../../features/lost_found/providers/lost_found_providers.dart';
import '../../features/lost_found/ui/widgets/lost_found_detail_dialog.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _clearSearch() {
    _searchController.clear();
    _removeOverlay();
    ref.read(buySellFilterProvider.notifier).state =
        ref.read(buySellFilterProvider).copyWith(query: '');
    ref.read(lostFoundFilterProvider.notifier).state =
        ref.read(lostFoundFilterProvider).copyWith(query: '');
    setState(() {});
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
                        'Type to search across all CampusHub modules...',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    );
                  }

                  final activeTab = ref.watch(tabIndexProvider);
                  final buySellAsync = ref.watch(buySellListingsProvider);
                  final lostAsync = ref.watch(lostReportsProvider);
                  final foundAsync = ref.watch(foundReportsProvider);

                  final buySellMatches = buySellAsync.maybeWhen(
                    data: (items) => items.where((i) =>
                        i.title.toLowerCase().contains(query) ||
                        i.description.toLowerCase().contains(query)).toList(),
                    orElse: () => [],
                  );

                  final lostMatches = lostAsync.maybeWhen(
                    data: (items) => items.where((i) =>
                        i.title.toLowerCase().contains(query) ||
                        i.description.toLowerCase().contains(query)).toList(),
                    orElse: () => [],
                  );

                  final foundMatches = foundAsync.maybeWhen(
                    data: (items) => items.where((i) =>
                        i.title.toLowerCase().contains(query) ||
                        i.description.toLowerCase().contains(query)).toList(),
                    orElse: () => [],
                  );

                  final isBuySellActive = activeTab == 0;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isBuySellActive) ...[
                          _buildSectionHeader('BUY & SELL RESULTS (CURRENT TAB)'),
                          ..._buildBuySellItems(context, ref, buySellMatches),
                          const Divider(),
                          _buildSectionHeader('LOST & FOUND RESULTS (OTHER TABS)'),
                          ..._buildLostFoundItems(context, ref, lostMatches, 'Lost'),
                          ..._buildLostFoundItems(context, ref, foundMatches, 'Found'),
                        ] else ...[
                          _buildSectionHeader('LOST & FOUND RESULTS (CURRENT TAB)'),
                          ..._buildLostFoundItems(context, ref, lostMatches, 'Lost'),
                          ..._buildLostFoundItems(context, ref, foundMatches, 'Found'),
                          const Divider(),
                          _buildSectionHeader('BUY & SELL RESULTS (OTHER TABS)'),
                          ..._buildBuySellItems(context, ref, buySellMatches),
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

  List<Widget> _buildBuySellItems(BuildContext context, WidgetRef ref, List items) {
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
        subtitle: Text('₹${item.sellingPrice.toStringAsFixed(0)} • ${item.location}'),
        onTap: () {
          _removeOverlay();
          // Switch to Buy & Sell tab without adding to browser history
          ref.read(tabIndexProvider.notifier).state = 0;
          showDialog(
            context: context,
            builder: (ctx) => BuySellDetailDialog(
              item: item,
              onStatusChange: (status) async {
                await ref.read(buySellRepositoryProvider).updateStatus(item.id, status);
                ref.invalidate(buySellListingsProvider);
              },
            ),
          );
        },
      );
    }).toList();
  }

  List<Widget> _buildLostFoundItems(BuildContext context, WidgetRef ref, List items, String type) {
    if (items.isEmpty) return [];
    return items.map((item) {
      return ListTile(
        dense: true,
        leading: Icon(
          type == 'Lost' ? Icons.search_off : Icons.check_circle_outline,
          size: 20,
          color: type == 'Lost' ? Colors.red : Colors.teal,
        ),
        title: Text('[$type] ${item.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${item.location} • ${item.eventTime}'),
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
              hintText: 'Super Search across all modules...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _clearSearch,
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              if (_overlayEntry == null) {
                _showOverlay();
              } else {
                _overlayEntry!.markNeedsBuild();
              }
              ref.read(buySellFilterProvider.notifier).state =
                  ref.read(buySellFilterProvider).copyWith(query: val);
              ref.read(lostFoundFilterProvider.notifier).state =
                  ref.read(lostFoundFilterProvider).copyWith(query: val);
            },
          ),
        ),
      ),
    );
  }
}
