import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/lost_found_item.dart';
import '../providers/lost_found_providers.dart';
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
        title: const Text('Lost & Found Portal', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            icon: Icons.search_off,
                            headerColor: Colors.pinkAccent.shade700,
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
                            icon: Icons.check_circle_outline,
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
                              Tab(icon: Icon(Icons.search_off), text: 'Lost Items'),
                              Tab(icon: Icon(Icons.check_circle_outline), text: 'Found Items'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: TabBarView(
                              children: [
                                LostFoundColumn(
                                  title: 'Lost Items',
                                  icon: Icons.search_off,
                                  headerColor: Colors.pinkAccent.shade700,
                                  buttonText: 'Report Lost',
                                  postType: PostType.lost,
                                  asyncData: lostAsync,
                                ),
                                LostFoundColumn(
                                  title: 'Found Items',
                                  icon: Icons.check_circle_outline,
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
