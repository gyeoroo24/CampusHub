import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'lost_found_card.dart';
import 'report_item_dialog.dart';

class LostFoundColumn extends ConsumerStatefulWidget {
  final String title;
  final IconData icon;
  final Color headerColor;
  final String buttonText;
  final PostType postType;

  const LostFoundColumn({
    super.key,
    required this.title,
    required this.icon,
    required this.headerColor,
    required this.buttonText,
    required this.postType,
  });

  @override
  ConsumerState<LostFoundColumn> createState() => _LostFoundColumnState();
}

class _LostFoundColumnState extends ConsumerState<LostFoundColumn> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (current >= max - 200) {
        if (widget.postType == PostType.lost) {
          ref.read(lostReportsPaginationProvider.notifier).loadMore();
        } else {
          ref.read(foundReportsPaginationProvider.notifier).loadMore();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paginatedState = widget.postType == PostType.lost
        ? ref.watch(lostReportsPaginationProvider)
        : ref.watch(foundReportsPaginationProvider);

    final items = paginatedState.items;
    final headerColor = widget.headerColor;

    return Column(
      children: [
        // Sleek Responsive Column Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: headerColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: headerColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(widget.icon, color: headerColor, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: headerColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: headerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${items.length}${paginatedState.hasMore ? '+' : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: headerColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: headerColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  final signedIn = await AuthDialog.ensureSignedIn(
                    context,
                    ref,
                    title: widget.postType == PostType.lost
                        ? 'Sign In to Report Lost Item'
                        : 'Sign In to Report Found Item',
                    message: 'Only verified IISc students can post lost and found reports.',
                  );
                  if (!signedIn || !context.mounted) return;

                  final user = ref.read(currentUserProvider);
                  showDialog(
                    context: context,
                    builder: (ctx) => ReportItemDialog(
                      postType: widget.postType,
                      userEmail: user?.email,
                      userId: user?.id,
                      userName: user?.name,
                      onSubmit: (report) async {
                        final created = await ref.read(lostFoundRepositoryProvider).submitReport(report);
                        if (widget.postType == PostType.lost) {
                          ref.read(lostReportsPaginationProvider.notifier).loadInitial();
                        } else {
                          ref.read(foundReportsPaginationProvider.notifier).loadInitial();
                        }
                        return created;
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  widget.buttonText,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Content Feed (Adaptive Grid or Skeletons with Infinite Scroll)
        Expanded(
          child: paginatedState.isLoadingInitial
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final isTwoCols = constraints.maxWidth > 440;
                    if (isTwoCols) {
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: 4,
                        itemBuilder: (_, __) => const ShimmerLoadingCard(isList: false),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: 3,
                      itemBuilder: (_, __) => const ShimmerLoadingCard(isList: true),
                    );
                  },
                )
              : items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 38, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No ${widget.title.toLowerCase()} matching filter.',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isTwoCols = constraints.maxWidth > 440;

                        if (isTwoCols) {
                          return ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.72,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, index) => LostFoundCard(
                                  item: items[index],
                                  onStatusChange: (status) {
                                    if (widget.postType == PostType.lost) {
                                      ref.read(lostReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
                                    } else {
                                      ref.read(foundReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
                                    }
                                  },
                                ),
                              ),
                              if (paginatedState.isLoadingMore)
                                _buildLoadingMoreIndicator(headerColor)
                              else if (!paginatedState.hasMore && items.isNotEmpty)
                                _buildAllCaughtUpIndicator(items.length),
                            ],
                          );
                        }

                        // Mobile single-column: uses intrinsic height so cards never overflow
                        final totalCount = items.length + (paginatedState.isLoadingMore || (!paginatedState.hasMore && items.isNotEmpty) ? 1 : 0);
                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: totalCount,
                          itemBuilder: (context, index) {
                            if (index == items.length) {
                              return paginatedState.isLoadingMore
                                  ? _buildLoadingMoreIndicator(headerColor)
                                  : _buildAllCaughtUpIndicator(items.length);
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: LostFoundCard(
                                item: items[index],
                                onStatusChange: (status) {
                                  if (widget.postType == PostType.lost) {
                                    ref.read(lostReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
                                  } else {
                                    ref.read(foundReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
                                  }
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  static Widget _buildLoadingMoreIndicator(Color color) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color,
          ),
        ),
      ),
    );
  }

  static Widget _buildAllCaughtUpIndicator(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Text(
          'Showing all $count items',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ),
    );
  }
}
