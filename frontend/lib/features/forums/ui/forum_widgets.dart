import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/forum_models.dart';

const upvoteColor = Color(0xFFFF4500);
const downvoteColor = Color(0xFF7193FF);

void forumSnack(BuildContext context, String message) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

/// "1.2k" style counts, as on Reddit.
String compactCount(int n) {
  final a = n.abs();
  if (a < 1000) return '$n';
  final v = (a / 1000).toStringAsFixed(a < 10000 ? 1 : 0).replaceAll('.0', '');
  return '${n < 0 ? '-' : ''}${v}k';
}

/// Round badge with a name's first letter.
class ForumAvatar extends StatelessWidget {
  final String name;
  final double size;

  const ForumAvatar({super.key, required this.name, this.size = 24});

  static const _palette = [Color(0xFFFF4500), Color(0xFF0079D3), Color(0xFF46D160), Color(0xFFFFB000),
    Color(0xFF7193FF), Color(0xFFDB2777), Color(0xFF0D9488), Color(0xFF7C3AED)];

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: size * 0.46, fontWeight: FontWeight.bold)),
    );
  }
}

/// Up arrow, score, down arrow. Votes show at once and roll back if the server refuses.
/// Guests are asked to sign in first.
class VoteControl extends ConsumerStatefulWidget {
  final int score;
  final int viewerVote;
  final Future<VoteResult> Function(int value) onVote;
  final Axis direction;
  final bool compact;

  const VoteControl({
    super.key,
    required this.score,
    required this.viewerVote,
    required this.onVote,
    this.direction = Axis.horizontal,
    this.compact = false,
  });

  @override
  ConsumerState<VoteControl> createState() => _VoteControlState();
}

class _VoteControlState extends ConsumerState<VoteControl> {
  late int _score = widget.score;
  late int _vote = widget.viewerVote;
  bool _busy = false;

  @override
  void didUpdateWidget(VoteControl old) {
    super.didUpdateWidget(old);
    if (!_busy && (old.score != widget.score || old.viewerVote != widget.viewerVote)) {
      _score = widget.score;
      _vote = widget.viewerVote;
    }
  }

  Future<void> _press(int direction) async {
    final user = ref.read(currentUserProvider);
    if (user == null || user.isGuest) {
      await AuthDialog.ensureSignedIn(context, ref, title: 'Sign in to vote',
          message: 'Sign in with your IISc email to vote on posts and replies.');
      return;
    }
    if (_busy) return;
    final value = _vote == direction ? 0 : direction;
    final (beforeScore, beforeVote) = (_score, _vote);
    setState(() {
      _busy = true;
      _score += value - _vote;
      _vote = value;
    });
    try {
      final result = await widget.onVote(value);
      if (mounted) {
        setState(() {
          _score = result.score;
          _vote = result.viewerVote;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _score = beforeScore;
          _vote = beforeVote;
        });
        forumSnack(context, errorText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final iconSize = widget.compact ? 18.0 : 22.0;
    final color = _vote == 1 ? upvoteColor : (_vote == -1 ? downvoteColor : null);
    Widget arrow(int direction) => InkResponse(
          radius: 18,
          onTap: () => _press(direction),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              direction == 1
                  ? (_vote == 1 ? Icons.arrow_upward_rounded : Icons.arrow_upward_outlined)
                  : (_vote == -1 ? Icons.arrow_downward_rounded : Icons.arrow_downward_outlined),
              size: iconSize,
              color: _vote == direction ? color : hint,
              semanticLabel: direction == 1 ? 'Upvote' : 'Downvote',
            ),
          ),
        );
    final score = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(compactCount(_score),
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: widget.compact ? 12 : 13, color: color)),
    );
    final children = [arrow(1), score, arrow(-1)];
    return widget.direction == Axis.vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Rounded pill around votes / comment counts in the action bar under a post.
class ForumPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ForumPill({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: child),
      ),
    );
  }
}

/// The "Create post" dialog: a title and the post. Pops with the new thread.
class CreatePostDialog extends StatefulWidget {
  final String placeName;
  final Future<ForumThread> Function(String title, String body) onPost;

  const CreatePostDialog({super.key, required this.placeName, required this.onPost});

  @override
  State<CreatePostDialog> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends State<CreatePostDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Add a title and some text.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final thread = await widget.onPost(_title.text.trim(), _body.text.trim());
      if (mounted) Navigator.pop(context, thread);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Create a post in ${widget.placeName}', style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 200,
              enabled: !_busy,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              enabled: !_busy,
              minLines: 5,
              maxLines: 12,
              maxLength: 10000,
              decoration: const InputDecoration(hintText: 'Text', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _post,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Post'),
        ),
      ],
    );
  }
}
