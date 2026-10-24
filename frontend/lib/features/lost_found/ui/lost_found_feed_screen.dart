import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/lost_found_item.dart';
import 'widgets/lost_found_column.dart';
import 'widgets/lost_found_filter_bar.dart';

class LostFoundFeedScreen extends ConsumerWidget {
  const LostFoundFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 750;

    return Scaffold(
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10, left: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.search_off_rounded, size: 16, color: Color(0xFFBE185D)),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Lost Items',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFBE185D)),
                                    ),
                                  ],
                                ),
                              ),
                              const Expanded(
                                child: LostFoundColumn(
                                  title: 'Lost Items',
                                  headerColor: Color(0xFFBE185D),
                                  postType: PostType.lost,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10, left: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF0F766E)),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Found Items',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F766E)),
                                    ),
                                  ],
                                ),
                              ),
                              const Expanded(
                                child: LostFoundColumn(
                                  title: 'Found Items',
                                  headerColor: Color(0xFF0F766E),
                                  postType: PostType.found,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            tabs: [
                              Tab(icon: Icon(Icons.search_off_rounded), text: 'Lost Items'),
                              Tab(icon: Icon(Icons.check_circle_outline_rounded), text: 'Found Items'),
                            ],
                          ),
                          SizedBox(height: 12),
                          Expanded(
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
