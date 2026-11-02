import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/report_content_dialog.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/forum_models.dart';
import '../providers/forum_providers.dart';
import 'forum_widgets.dart';

enum _CommentSort { best, newest, oldest }

/// One post, Reddit style: the post with its votes, a comment box, and the replies as a tree
/// (replies to replies indented under a thread line; tap a name to collapse its branch).
class ThreadDialog extends StatelessWidget {
  final String threadId;

  const ThreadDialog({super.key, required this.threadId});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 780,
        height: size.height * 0.88,
        child: ThreadView(threadId: threadId),
      ),
    );
  }
}

class ThreadView extends ConsumerStatefulWidget {
  final String threadId;

  const ThreadView({super.key, required this.threadId});

  @override
  ConsumerState<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends ConsumerState<ThreadView> {
  final _comment = TextEditingController();
  final _collapsed = <String>{};
  _CommentSort _sort = _CommentSort.best;
  String? _replyingTo;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<bool> _ensureSignedIn() =>
      AuthDialog.ensureSignedIn(context, ref, title: 'Sign in to comment', message: 'Sign in with your IISc email to join the discussion.');

  Future<bool> _send(String text, {String? parentId}) async {
    if (text.trim().isEmpty || _busy) return false;
    if (!await _ensureSignedIn() || !mounted) return false;
    final repo = ref.read(forumRepositoryProvider);
    setState(() => _busy = true);
    try {
      await repo.reply(widget.threadId, text.trim(), parentId: parentId);
      if (!mounted) return true;
      ref.invalidate(forumThreadProvider(widget.threadId));
      setState(() => _replyingTo = null);
      return true;
    } catch (e) {
      if (mounted) forumSnack(context, errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String what, Future<void> Function() action, {bool closeAfter = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove this $what?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await action();
      if (!mounted) return;
      if (closeAfter) {
        Navigator.pop(context);
      } else {
        ref.invalidate(forumThreadProvider(widget.threadId));
      }
    } catch (e) {
      if (mounted) forumSnack(context, errorText(e));
    }
  }

  List<ForumComment> _sorted(List<ForumComment> list) {
    final copy = [...list];
    switch (_sort) {
      case _CommentSort.best:
        copy.sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : a.createdAt.compareTo(b.createdAt));
      case _CommentSort.newest:
        copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _CommentSort.oldest:
        copy.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threadAsync = ref.watch(forumThreadProvider(widget.threadId));
    final user = ref.watch(currentUserProvider);
    final myId = user == null || user.isGuest ? null : user.id;
    final repo = ref.read(forumRepositoryProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Row(
            children: [
              const Icon(Icons.forum_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(threadAsync.valueOrNull?.title ?? 'Post',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        Expanded(
          child: threadAsync.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(e)))),
            data: (thread) {
              final post = thread.openingPost;
              final canRemoveThread = thread.viewerCanModerate || thread.authorId == myId;
              final byParent = <String?, List<ForumComment>>{};
              final ids = {for (final c in thread.replies) c.id};
              for (final c in thread.replies) {
                // A reply whose parent is gone still shows, at the top level.
                byParent.putIfAbsent(ids.contains(c.parentId) ? c.parentId : null, () => []).add(c);
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    children: [
                      ForumAvatar(name: thread.authorName, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('u/${thread.authorName} · ${DateTimeFormatter.timeAgo(thread.createdAt)}',
                            style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      ),
                      if (myId != null)
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          onSelected: (v) => v == 'remove'
                              ? _remove('post and all its comments', () => repo.deleteThread(thread.id), closeAfter: true)
                              : ReportContentDialog.show(context, ref,
                                  targetType: 'thread', targetId: thread.id, itemLabel: 'this post'),
                          itemBuilder: (_) => [
                            if (canRemoveThread) const PopupMenuItem(value: 'remove', child: Text('Remove post')),
                            if (thread.authorId != myId) const PopupMenuItem(value: 'report', child: Text('Report')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(thread.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (post != null)
                    post.removed
                        ? Text('[removed]', style: TextStyle(color: theme.hintColor))
                        : SelectableText(post.content ?? '', style: const TextStyle(fontSize: 15, height: 1.4)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ForumPill(
                        child: VoteControl(
                          score: thread.score,
                          viewerVote: thread.viewerVote,
                          onVote: (v) => repo.voteThread(thread.id, v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ForumPill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.mode_comment_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text('${thread.replyCount}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (myId == null)
                    OutlinedButton.icon(
                      onPressed: _ensureSignedIn,
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Sign in to comment'),
                    )
                  else
                    _CommentBox(
                      controller: _comment,
                      busy: _busy,
                      hint: 'Join the conversation',
                      onSend: () async {
                        if (await _send(_comment.text)) _comment.clear();
                      },
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Sort by', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      const SizedBox(width: 8),
                      DropdownButton<_CommentSort>(
                        value: _sort,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                        items: const [
                          DropdownMenuItem(value: _CommentSort.best, child: Text('Best')),
                          DropdownMenuItem(value: _CommentSort.newest, child: Text('New')),
                          DropdownMenuItem(value: _CommentSort.oldest, child: Text('Old')),
                        ],
                        onChanged: (v) => setState(() => _sort = v ?? _sort),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (thread.replies.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('No comments yet. Be the first to share what you think!',
                          textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
                    ),
                  for (final c in _sorted(byParent[null] ?? const []))
                    _buildComment(c, byParent, 0, thread, myId),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildComment(ForumComment c, Map<String?, List<ForumComment>> byParent, int depth, ForumThread thread,
      String? myId) {
    final theme = Theme.of(context);
    final repo = ref.read(forumRepositoryProvider);
    final children = _sorted(byParent[c.id] ?? const []);
    final collapsed = _collapsed.contains(c.id);
    final mine = c.authorId == myId;
    final lineColor = theme.dividerColor.withValues(alpha: 0.6);
    void toggle() => setState(() => collapsed ? _collapsed.remove(c.id) : _collapsed.add(c.id));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(onTap: toggle, child: ForumAvatar(name: c.authorName, size: 24)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: toggle,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(c.authorName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.authorId == thread.authorId ? theme.colorScheme.primary : null)),
                      ),
                      if (c.authorId == thread.authorId)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text('OP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary)),
                        ),
                      Text(' · ${DateTimeFormatter.timeAgo(c.createdAt)}',
                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      if (collapsed) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.add_circle_outline_rounded, size: 14, color: theme.hintColor),
                        if (children.isNotEmpty)
                          Text(' ${children.length} more', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                      ],
                    ],
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(height: 4),
                  c.removed
                      ? Text('[removed]', style: TextStyle(color: theme.hintColor, fontStyle: FontStyle.italic))
                      : SelectableText(c.content ?? '', style: const TextStyle(height: 1.35)),
                  Row(
                    children: [
                      if (!c.removed)
                        VoteControl(
                          compact: true,
                          score: c.score,
                          viewerVote: c.viewerVote,
                          onVote: (v) => repo.voteComment(c.id, v),
                        ),
                      if (!c.removed)
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: theme.hintColor, visualDensity: VisualDensity.compact),
                          onPressed: () async {
                            if (!await _ensureSignedIn() || !mounted) return;
                            setState(() => _replyingTo = _replyingTo == c.id ? null : c.id);
                          },
                          icon: const Icon(Icons.reply_rounded, size: 16),
                          label: const Text('Reply'),
                        ),
                      if (!c.removed && myId != null)
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          iconSize: 18,
                          icon: Icon(Icons.more_horiz_rounded, color: theme.hintColor, size: 18),
                          onSelected: (v) => v == 'remove'
                              ? _remove('comment', () => repo.deleteComment(c.id))
                              : ReportContentDialog.show(context, ref,
                                  targetType: 'comment', targetId: c.id, itemLabel: 'this comment'),
                          itemBuilder: (_) => [
                            if (mine || thread.viewerCanModerate) const PopupMenuItem(value: 'remove', child: Text('Remove')),
                            if (!mine) const PopupMenuItem(value: 'report', child: Text('Report')),
                          ],
                        ),
                    ],
                  ),
                  if (_replyingTo == c.id)
                    _InlineReply(
                      busy: _busy,
                      replyingTo: c.authorName,
                      onCancel: () => setState(() => _replyingTo = null),
                      onSend: (text) => _send(text, parentId: c.id),
                    ),
                  if (children.isNotEmpty)
                    Container(
                      // The thread line joining a comment to its replies.
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: lineColor, width: 2))),
                      padding: EdgeInsets.only(left: depth < 6 ? 10 : 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final child in children) _buildComment(child, byParent, depth + 1, thread, myId)],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBox extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final String hint;
  final VoidCallback onSend;

  const _CommentBox({required this.controller, required this.busy, required this.hint, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 8,
          maxLength: 10000,
          enabled: !busy,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            counterText: '',
          ),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: busy ? null : onSend,
          child: busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Comment'),
        ),
      ],
    );
  }
}

class _InlineReply extends StatefulWidget {
  final bool busy;
  final String replyingTo;
  final VoidCallback onCancel;
  final Future<bool> Function(String text) onSend;

  const _InlineReply({required this.busy, required this.replyingTo, required this.onCancel, required this.onSend});

  @override
  State<_InlineReply> createState() => _InlineReplyState();
}

class _InlineReplyState extends State<_InlineReply> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            enabled: !widget.busy,
            decoration: InputDecoration(
              hintText: 'Reply to ${widget.replyingTo}',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: widget.busy ? null : widget.onCancel, child: const Text('Cancel')),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: widget.busy ? null : () => widget.onSend(_controller.text),
                child: const Text('Reply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
