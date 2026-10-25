import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/lost_found_item.dart';
import '../providers/lost_found_providers.dart';
import 'widgets/lost_found_column.dart';
import 'widgets/lost_found_filter_bar.dart';

class LostFoundFeedScreen extends ConsumerStatefulWidget {
  const LostFoundFeedScreen({super.key});

  @override
  ConsumerState<LostFoundFeedScreen> createState() => _LostFoundFeedScreenState();
}

class _LostFoundFeedScreenState extends ConsumerState<LostFoundFeedScreen> {
  // Captured in initState: `ref` itself is unusable by the time dispose() runs (Riverpod
  // tears it down before calling the widget's dispose), but a notifier obtained earlier is
  // still a plain object we can call into.
  late final StateController<LostFoundFilterState> _filterNotifier;

  @override
  void initState() {
    super.initState();
    _filterNotifier = ref.read(lostFoundFilterProvider.notifier);
  }

  @override
  void dispose() {
    // Filters are scoped to a visit of this tab, not the whole session — reset them
    // on the way out so switching tabs and back starts from a clean feed. Riverpod forbids
    // writing a provider while the widget tree is being torn down, so this is deferred a tick.
    Future(() => _filterNotifier.state = LostFoundFilterState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 750;
    final isCompactFab = MediaQuery.of(context).size.width < 420;

    return Scaffold(
      floatingActionButton: isDesktop
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'fab_report_lost',
                    backgroundColor: const Color(0xFFBE185D),
                    foregroundColor: Colors.white,
                    onPressed: () => LostFoundFilterBar.handleReport(context, ref, PostType.lost),
                    icon: const Icon(Icons.search_off_rounded, size: 18),
                    label: Text(
                      isCompactFab ? 'Lost' : 'Report Lost',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  FloatingActionButton.extended(
                    heroTag: 'fab_report_found',
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    onPressed: () => LostFoundFilterBar.handleReport(context, ref, PostType.found),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: Text(
                      isCompactFab ? 'Found' : 'Report Found',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        children: [
          // Filter Bar
          const LostFoundFilterBar(),
          const Divider(height: 1),

          // Portal Feed (Side-by-Side on Desktop, Tabs on Mobile)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: LostFoundColumn(
                            title: 'Lost Items',
                            headerColor: Color(0xFFBE185D),
                            postType: PostType.lost,
                          ),
                        ),
                        const SizedBox(width: 20),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(width: 20),
                        const Expanded(
                          child: LostFoundColumn(
                            title: 'Found Items',
                            headerColor: Color(0xFF0F766E),
                            postType: PostType.found,
                          ),
                        ),
                      ],
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Container(
                            height: 36,
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: TabBar(
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              labelColor: theme.colorScheme.primary,
                              unselectedLabelColor: Colors.grey.shade600,
                              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              tabs: const [
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 15),
                                      SizedBox(width: 6),
                                      Text('Lost'),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_outline_rounded, size: 15),
                                      SizedBox(width: 6),
                                      Text('Found'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Expanded(
                            child: TabBarView(
                              children: [
                                LostFoundColumn(
                                  title: 'Lost Items',
                                  headerColor: Color(0xFFBE185D),
                                  postType: PostType.lost,
                                ),
                                LostFoundColumn(
                                  title: 'Found Items',
                                  headerColor: Color(0xFF0F766E),
                                  postType: PostType.found,
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
