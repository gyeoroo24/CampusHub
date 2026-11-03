import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../domain/wanted_post.dart';
import '../providers/wanted_providers.dart';
import 'wanted_detail_dialog.dart';

/// "For sale | Wanted" switch at the top of the Buy & Sell tab.
class BuySellSectionToggle extends ConsumerWidget {
  const BuySellSectionToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(buySellSectionProvider);
    return SegmentedButton<BuySellSection>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: BuySellSection.listings,
          icon: Icon(Icons.sell_outlined, size: 16),
          label: Text('For sale'),
        ),
        ButtonSegment(
          value: BuySellSection.wanted,
          icon: Icon(Icons.volunteer_activism_outlined, size: 16),
          label: Text('Wanted'),
        ),
      ],
      selected: {section},
      onSelectionChanged: (s) => ref.read(buySellSectionProvider.notifier).state = s.first,
    );
  }
}

/// The Wanted feed: what fellow students are looking for. Uses the Buy & Sell search box and
/// category chips; shown in place of the listings when the switch is on "Wanted".
class WantedFeedSliver extends ConsumerWidget {
  const WantedFeedSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(wantedPostsProvider);
    final filter = ref.watch(wantedFilterProvider);
    final listingFilter = ref.watch(buySellFilterProvider);
    final narrowed = listingFilter.category != 'All' || listingFilter.query.isNotEmpty;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);
    final signedIn = user != null && !user.isGuest;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: theme.hintColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'What fellow students are looking for. Have one of these? List it, and the buyer gets notified.',
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Show closed', style: TextStyle(fontSize: 11)),
                      selected: filter.showClosed,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) =>
                          ref.read(wantedFilterProvider.notifier).state = filter.copyWith(showClosed: v),
                    ),
                  ],
                ),
                if (signedIn) ...[
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: true, label: Text('What I want', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: false, label: Text('See what others want', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {filter.mine},
                    onSelectionChanged: (s) =>
                        ref.read(wantedFilterProvider.notifier).state = filter.copyWith(mine: s.first),
                  ),
                ],
              ],
            ),
          ),
        ),
        postsAsync.when(
          loading: () => const SliverToBoxAdapter(child: SkeletonList(itemCount: 4)),
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(errorText(e))),
          ),
          data: (posts) {
            if (posts.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volunteer_activism_outlined, size: 54, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        narrowed
                            ? 'No Wanted requests match ${[
                                if (listingFilter.category != 'All') '“${listingFilter.category}”',
                                if (listingFilter.query.isNotEmpty) '“${listingFilter.query}”',
                              ].join(' and ')}.'
                            : 'No Wanted requests here yet.',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      if (narrowed)
                        TextButton(
                          onPressed: () => ref.read(buySellFilterProvider.notifier).state =
                              listingFilter.copyWith(category: 'All', query: ''),
                          child: const Text('Show all Wanted requests'),
                        )
                      else
                        Text('Post one and sellers will know what you need.',
                            style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 440,
                  mainAxisExtent: 156,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => WantedCard(post: posts[i]),
                  childCount: posts.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class WantedCard extends StatelessWidget {
  final WantedPost post;

  const WantedCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final closed = post.status != WantedStatus.open;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: () => showDialog(context: context, builder: (_) => WantedDetailDialog(post: post)),
        child: Opacity(
          opacity: closed ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.volunteer_activism_outlined, size: 16, color: Colors.deepPurple.shade400),
                    const SizedBox(width: 6),
                    Text(post.category.name,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    const Spacer(),
                    if (closed)
                      Text(post.status.label,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.hintColor)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    post.description ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(post.budgetLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '${post.author.name} · ${DateTimeFormatter.timeAgo(post.createdAt)}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
