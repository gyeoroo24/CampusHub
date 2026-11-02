/// Discussion forum read models (FR-14), shared by company forums (Placement Hub) and event forums.
library;

int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
String? _str(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// What a forum belongs to. Each has exactly one forum, created on first visit.
enum ForumScope { company, event }

/// Thread order: newest first, or most upvoted.
enum ForumSort {
  newest('New'),
  top('Top');

  final String label;

  const ForumSort(this.label);

  String get apiValue => this == ForumSort.newest ? 'new' : name;
}

class ForumThread {
  final String id;
  final String forumId;
  final String title;
  final String authorId;
  final String authorName;

  /// The start of the opening post (in lists).
  final String? preview;
  final int score;

  /// 1, -1 or 0.
  final int viewerVote;
  final int replyCount;
  final DateTime? lastCommentAt;
  final DateTime createdAt;

  /// Only on the thread page, in order; the first one is the opening post.
  final List<ForumComment> comments;
  final bool viewerCanModerate;

  const ForumThread({
    required this.id,
    required this.forumId,
    required this.title,
    required this.authorId,
    required this.authorName,
    this.preview,
    this.score = 0,
    this.viewerVote = 0,
    this.replyCount = 0,
    this.lastCommentAt,
    required this.createdAt,
    this.comments = const [],
    this.viewerCanModerate = false,
  });

  factory ForumThread.fromJson(Map<String, dynamic> json) => ForumThread(
        id: '${json['id']}',
        forumId: '${json['forum_id']}',
        title: json['title']?.toString() ?? '',
        authorId: '${(json['author'] as Map?)?['id'] ?? ''}',
        authorName: '${(json['author'] as Map?)?['name'] ?? ''}',
        preview: _str(json['preview']),
        score: _int(json['score']),
        viewerVote: _int(json['viewer_vote']),
        replyCount: json.containsKey('reply_count')
            ? _int(json['reply_count'])
            : (_int(json['comment_count']) - 1).clamp(0, 1 << 30),
        lastCommentAt: _date(json['last_comment_at']),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
        comments: (json['comments'] as List<dynamic>? ?? [])
            .map((c) => ForumComment.fromJson(c as Map<String, dynamic>))
            .toList(),
        viewerCanModerate: json['viewer_can_moderate'] == true,
      );

  /// The opening post (on the thread page).
  ForumComment? get openingPost => comments.isEmpty ? null : comments.first;

  /// Replies, without the opening post.
  List<ForumComment> get replies => comments.length <= 1 ? const [] : comments.sublist(1);
}

class ForumComment {
  final String id;

  /// The reply this answers; null when it answers the opening post.
  final String? parentId;
  final String authorId;
  final String authorName;

  /// null when the comment was removed.
  final String? content;
  final bool removed;
  final int score;
  final int viewerVote;
  final DateTime createdAt;

  const ForumComment({
    required this.id,
    this.parentId,
    required this.authorId,
    required this.authorName,
    this.content,
    this.removed = false,
    this.score = 0,
    this.viewerVote = 0,
    required this.createdAt,
  });

  factory ForumComment.fromJson(Map<String, dynamic> json) => ForumComment(
        id: '${json['id']}',
        parentId: _str(json['parent_id']),
        authorId: '${(json['author'] as Map?)?['id'] ?? ''}',
        authorName: '${(json['author'] as Map?)?['name'] ?? ''}',
        content: _str(json['content']),
        removed: json['removed'] == true,
        score: _int(json['score']),
        viewerVote: _int(json['viewer_vote']),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
      );
}

/// A score after voting.
class VoteResult {
  final int score;
  final int viewerVote;

  const VoteResult(this.score, this.viewerVote);

  factory VoteResult.fromJson(Map<String, dynamic> json) => VoteResult(_int(json['score']), _int(json['viewer_vote']));
}

/// Which threads a board shows.
class ThreadQuery {
  final String forumId;
  final ForumSort sort;
  final String search;

  const ThreadQuery(this.forumId, {this.sort = ForumSort.newest, this.search = ''});

  @override
  bool operator ==(Object other) =>
      other is ThreadQuery && other.forumId == forumId && other.sort == sort && other.search == search;

  @override
  int get hashCode => Object.hash(forumId, sort, search);
}
