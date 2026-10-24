import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/enums/view_mode.dart';
import '../../../../core/widgets/skeleton_loader.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'lost_found_card.dart';
import 'lost_found_list_card.dart';

class LostFoundColumn extends ConsumerStatefulWidget {
  final Color headerColor;
  final PostType postType;
  final String? title;
  final IconData? icon;
  final String? buttonText;

  const LostFoundColumn({
    super.key,
    required this.headerColor,
    required this.postType,
    this.title,
    this.icon,
    this.buttonText,
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
    final title = widget.title ?? (widget.postType == PostType.lost ? 'Lost Items' : 'Found Items');

    if (paginatedState.isLoadingInitial) {
      return ref.watch(lostFoundFilterProvider).viewMode == ViewMode.list
          ? ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: 4,
              itemBuilder: (_, __) => const ShimmerLoadingCard(isList: true),
            )
          : LayoutBuilder(
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
            );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 38, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No ${title.toLowerCase()} matching filter.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final filter = ref.watch(lostFoundFilterProvider);
    final totalCount = items.length +
        (paginatedState.isLoadingMore || (!paginatedState.hasMore && items.isNotEmpty) ? 1 : 0);

    // If user selected List View mode
    if (filter.viewMode == ViewMode.list) {
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
          return LostFoundListCard(
            item: items[index],
            onStatusChange: (status) {
              if (widget.postType == PostType.lost) {
                ref.read(lostReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
              } else {
                ref.read(foundReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
              }
            },
          );
        },
      );
    }

    // Default: Responsive Grid View
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoCols = constraints.maxWidth > 440;
        if (isTwoCols) {
          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: totalCount,
            itemBuilder: (context, index) {
              if (index == items.length) {
                return paginatedState.isLoadingMore
                    ? _buildLoadingMoreIndicator(headerColor)
                    : _buildAllCaughtUpIndicator(items.length);
              }
              return LostFoundCard(
                item: items[index],
                onStatusChange: (status) {
                  if (widget.postType == PostType.lost) {
                    ref.read(lostReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
                  } else {
                    ref.read(foundReportsPaginationProvider.notifier).updateItemStatusLocally(items[index].id, status);
                  }
                },
              );
            },
          );
        }
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
              padding: const EdgeInsets.only(bottom: 12.0),
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
