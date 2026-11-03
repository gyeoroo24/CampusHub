import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/report_content_dialog.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/forum_models.dart';
import '../providers/forum_providers.dart';
import 'forum_widgets.dart';
import 'thread_view.dart';

/// A Reddit-style board for a company or an event: a "Create post" bar, Hot / New / Top, search,
/// and post cards with a vote rail. Opening a post shows it with its comment tree.
///
/// [embedded] lays the board out as a plain column for a page that already scrolls (the event page);
/// otherwise it scrolls itself (a tab).
class ForumBoard extends ConsumerStatefulWidget {
  final ForumScope scope;
  final String scopeId;

  /// Shown as the board's name, e.g. "IBM" or "Diwali night".
  final String placeName;
  final String blurb;
  final bool embedded;

  const ForumBoard({
    super.key,
    required this.scope,
    required this.scopeId,
    required this.placeName,
    required this.blurb,
    this.embedded = false,
  });

  @override
  ConsumerState<ForumBoard> createState() => _ForumBoardState();
}

class _ForumBoardState extends ConsumerState<ForumBoard> {
  ForumSort _sort = ForumSort.newest;
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createPost(String forumId) async {
    // Everything after an await goes through the container, never this widget's ref: signing in or a
    // page refresh can rebuild the board while the dialog is open.
    final container = ProviderScope.containerOf(context, listen: false);
    final signedIn = await AuthDialog.ensureSignedIn(context, ref,
        title: 'Sign in to post', message: 'Sign in with your IISc email to start a discussion.');
    if (!signedIn || !mounted) return;
    final repo = container.read(forumRepositoryProvider);
    final created = await showDialog<ForumThread>(
      context: context,
      builder: (_) => CreatePostDialog(
        placeName: widget.placeName,
        onPost: (title, body) => repo.createThread(forumId, title, body),
      ),
    );
    if (created == null) return;
    container.invalidate(forumThreadsProvider);
    if (mounted) await _open(created.id);
  }

  Future<void> _open(String threadId) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await showDialog(context: context, builder: (_) => ThreadDialog(threadId: threadId));
    container.invalidate(forumThreadsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forumAsync = ref.watch(forumIdProvider((widget.scope, widget.scopeId)));
    return forumAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorState(
          message: errorText(e), onRetry: () => ref.invalidate(forumIdProvider((widget.scope, widget.scopeId)))),
      data: (forumId) {
        final query = ThreadQuery(forumId, sort: _sort, search: _search);
        final threadsAsync = ref.watch(forumThreadsProvider(query));
        final children = <Widget>[
          _CreatePostBar(onTap: () => _createPost(forumId), blurb: widget.blurb),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in ForumSort.values)
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    switch (s) {
                      ForumSort.newest => Icons.new_releases_outlined,
                      ForumSort.top => Icons.leaderboard_rounded,
                    },
                    size: 16,
                  ),
                  label: Text(s.label),
                  selected: _sort == s,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _sort = s),
                ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: 'Search posts',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _search = '';
                            }),
                          ),
                  ),
                  onSubmitted: (v) => setState(() => _search = v),
                  onChanged: (v) {
                    if (v.isEmpty) setState(() => _search = '');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...threadsAsync.when<List<Widget>>(
            skipLoadingOnReload: true,
            loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [ErrorState(message: errorText(e), onRetry: () => ref.invalidate(forumThreadsProvider(query)))],
            data: (threads) => threads.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.forum_outlined, size: 40, color: theme.hintColor),
                          const SizedBox(height: 8),
                          Text(_search.isEmpty ? 'No posts yet. Start the conversation!' : 'No posts match.',
                              style: TextStyle(color: theme.hintColor)),
                        ],
                      ),
                    ),
                  ]
                : [for (final t in threads) _PostCard(thread: t, onOpen: () => _open(t.id))],
          ),
        ];
        if (widget.embedded) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(forumThreadsProvider(query)),
              child: ListView(padding: const EdgeInsets.all(16), children: children),
            ),
          ),
        );
      },
    );
  }
}

class _CreatePostBar extends ConsumerWidget {
  final VoidCallback onTap;
  final String blurb;

  const _CreatePostBar({required this.onTap, required this.blurb});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ForumAvatar(name: user == null || user.isGuest ? '?' : user.name, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: Text('Create a post · $blurb',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.hintColor)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(tooltip: 'Create a post', onPressed: onTap, icon: const Icon(Icons.edit_note_rounded)),
          ],
        ),
      ),
    );
  }
}

/// One post in the list: vote rail on the left, then who/when, title, preview and the comment count.
class _PostCard extends ConsumerWidget {
  final ForumThread thread;
  final VoidCallback onOpen;

  const _PostCard({required this.thread, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final t = thread;
    final repo = ref.read(forumRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    final mine = user != null && !user.isGuest && user.id == t.authorId;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 46,
                padding: const EdgeInsets.only(top: 8),
                color: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F7F8),
                alignment: Alignment.topCenter,
                child: VoteControl(
                  direction: Axis.vertical,
                  compact: true,
                  score: t.score,
                  viewerVote: t.viewerVote,
                  onVote: (v) => repo.voteThread(t.id, v),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ForumAvatar(name: t.authorName, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Posted by u/${t.authorName} · ${DateTimeFormatter.timeAgo(t.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: theme.hintColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(t.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (t.preview != null) ...[
                        const SizedBox(height: 4),
                        Text(t.preview!, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85))),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                                foregroundColor: theme.hintColor, visualDensity: VisualDensity.compact),
                            onPressed: onOpen,
                            icon: const Icon(Icons.mode_comment_outlined, size: 16),
                            label: Text('${t.replyCount} ${t.replyCount == 1 ? 'Comment' : 'Comments'}'),
                          ),
                          const Spacer(),
                          if (user != null && !user.isGuest && !mine)
                            IconButton(
                              tooltip: 'Report',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.outlined_flag_rounded, size: 18, color: theme.hintColor),
                              onPressed: () => ReportContentDialog.show(context, ref,
                                  targetType: 'thread', targetId: t.id, itemLabel: 'this post'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
