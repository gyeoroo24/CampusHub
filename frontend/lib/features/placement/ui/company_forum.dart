import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/report_content_dialog.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../providers/placement_providers.dart';

/// A company's forum (PRD §2.1 "a forum"): threads newest first; opening one shows its replies in order.
class CompanyForumTab extends ConsumerWidget {
  final String companyId;

  const CompanyForumTab({super.key, required this.companyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(companyForumIdProvider(companyId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(message: errorText(e), onRetry: () => ref.invalidate(companyForumIdProvider(companyId))),
          data: (forumId) {
            final threadsAsync = ref.watch(forumThreadsProvider(forumId));
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(forumThreadsProvider(forumId)),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Ask seniors about the process, prep and offers.',
                                style: TextStyle(color: theme.hintColor)),
                          ),
                          FilledButton.icon(
                            onPressed: () => _newThread(context, ref, forumId),
                            icon: const Icon(Icons.add_comment_outlined, size: 18),
                            label: const Text('New thread'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...threadsAsync.when<List<Widget>>(
                        loading: () => [const Center(child: CircularProgressIndicator())],
                        error: (e, _) => [Text(errorText(e))],
                        data: (threads) => threads.isEmpty
                            ? [
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text('No threads yet. Start the first one.',
                                      textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
                                ),
                              ]
                            : [
                                for (final t in threads)
                                  Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
                                    ),
                                    child: ListTile(
                                      leading: const Icon(Icons.forum_outlined),
                                      title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        '${t.authorName} · ${t.commentCount - 1} '
                                        '${t.commentCount - 1 == 1 ? 'reply' : 'replies'} · '
                                        '${DateTimeFormatter.timeAgo(t.lastCommentAt ?? t.createdAt)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: const Icon(Icons.chevron_right_rounded),
                                      onTap: () async {
                                        await showDialog(context: context, builder: (_) => ThreadDialog(threadId: t.id));
                                        ref.invalidate(forumThreadsProvider(forumId));
                                      },
                                    ),
                                  ),
                              ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
  }

  Future<void> _newThread(BuildContext context, WidgetRef ref, String forumId) async {
    final signedIn = await AuthDialog.ensureSignedIn(context, ref,
        title: 'Sign in to post', message: 'Sign in with your IISc email to start a thread.');
    if (!signedIn || !context.mounted) return;
    final title = TextEditingController();
    final body = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        String? error;
        bool busy = false;
        return StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            title: const Text('New thread'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: body,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(labelText: 'Your question or post', border: OutlineInputBorder()),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                          setState(() => error = 'Add a title and a post.');
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await ref.read(placementRepositoryProvider).createThread(forumId, title.text.trim(), body.text.trim());
                          if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                        } catch (e) {
                          setState(() {
                            busy = false;
                            error = errorText(e);
                          });
                        }
                      },
                child: const Text('Post'),
              ),
            ],
          ),
        );
      },
    );
    title.dispose();
    body.dispose();
    if (created == true) ref.invalidate(forumThreadsProvider(forumId));
  }
}

/// One thread: the opening post and replies in order, a reply box, and remove/report actions.
class ThreadDialog extends ConsumerStatefulWidget {
  final String threadId;

  const ThreadDialog({super.key, required this.threadId});

  @override
  ConsumerState<ThreadDialog> createState() => _ThreadDialogState();
}

class _ThreadDialogState extends ConsumerState<ThreadDialog> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool closeAfter = false}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(forumThreadProvider(widget.threadId));
      if (closeAfter && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final myId = user == null || user.isGuest ? null : user.id;
    final repo = ref.read(placementRepositoryProvider);
    final threadAsync = ref.watch(forumThreadProvider(widget.threadId));
    final thread = threadAsync.valueOrNull;
    final canRemoveThread = thread != null && (thread.viewerCanModerate || thread.authorId == myId);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
      title: Row(
        children: [
          Expanded(child: Text(thread?.title ?? 'Thread')),
          if (canRemoveThread)
            IconButton(
              tooltip: 'Remove thread',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy ? null : () => _run(() => repo.deleteThread(widget.threadId), closeAfter: true),
            ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: (MediaQuery.of(context).size.height * 0.6).clamp(240.0, 560.0),
        child: threadAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorText(e))),
          data: (thread) => Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: thread.comments.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final c = thread.comments[i];
                    final mine = c.authorId == myId;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${c.authorName}${i == 0 ? ' · opening post' : ''} · ${DateTimeFormatter.timeAgo(c.createdAt)}',
                                style: TextStyle(fontSize: 12, color: theme.hintColor),
                              ),
                            ),
                            if (!c.removed && myId != null)
                              PopupMenuButton<String>(
                                iconSize: 18,
                                onSelected: (v) => v == 'remove'
                                    ? _run(() => repo.deleteComment(c.id))
                                    : ReportContentDialog.show(context, ref,
                                        targetType: 'comment', targetId: c.id, itemLabel: 'this comment'),
                                itemBuilder: (_) => [
                                  if (mine || thread.viewerCanModerate)
                                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                                  if (!mine) const PopupMenuItem(value: 'report', child: Text('Report')),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        c.removed
                            ? Text('This comment was removed.',
                                style: TextStyle(fontStyle: FontStyle.italic, color: theme.hintColor))
                            : SelectableText(c.content ?? ''),
                      ],
                    );
                  },
                ),
              ),
              const Divider(),
              if (myId == null)
                TextButton(
                  onPressed: () => AuthDialog.ensureSignedIn(context, ref, title: 'Sign in to reply'),
                  child: const Text('Sign in to reply'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'Write a reply', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _busy
                          ? null
                          : () {
                              final text = _reply.text.trim();
                              if (text.isEmpty) return;
                              _run(() async {
                                await repo.reply(widget.threadId, text);
                                _reply.clear();
                              });
                            },
                      icon: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
