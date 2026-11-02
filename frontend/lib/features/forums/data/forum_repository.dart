import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/forum_models.dart';

/// Company and event forums: threads, replies (to the post or to another reply) and votes.
abstract class IForumRepository {
  /// The forum of a company or event (created on first visit).
  Future<String> forumId(ForumScope scope, String scopeId);

  Future<List<ForumThread>> fetchThreads(ThreadQuery query);

  Future<ForumThread> getThread(String threadId);

  Future<ForumThread> createThread(String forumId, String title, String content);

  /// [parentId] is the reply being answered; null answers the opening post.
  Future<ForumComment> reply(String threadId, String content, {String? parentId});

  /// [value] is 1, -1 or 0 (take the vote back).
  Future<VoteResult> voteThread(String threadId, int value);

  Future<VoteResult> voteComment(String commentId, int value);

  Future<void> deleteThread(String threadId);

  Future<void> deleteComment(String commentId);
}

class ApiForumRepository implements IForumRepository {
  final ApiClient apiClient;

  ApiForumRepository(this.apiClient);

  @override
  Future<String> forumId(ForumScope scope, String scopeId) async {
    final path = switch (scope) {
      ForumScope.company => ApiEndpoints.companyForum(scopeId),
      ForumScope.event => ApiEndpoints.eventForum(scopeId),
    };
    final response = await apiClient.get(path);
    return '${(response.data as Map<String, dynamic>)['id']}';
  }

  @override
  Future<List<ForumThread>> fetchThreads(ThreadQuery query) async {
    final response = await apiClient.get(ApiEndpoints.forumThreads(query.forumId), queryParameters: {
      'sort': query.sort.apiValue,
      if (query.search.trim().isNotEmpty) 'q': query.search.trim(),
      'limit': 50,
    });
    final items = (response.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? [];
    return items.map((j) => ForumThread.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<ForumThread> getThread(String threadId) async {
    final response = await apiClient.get(ApiEndpoints.thread(threadId));
    return ForumThread.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ForumThread> createThread(String forumId, String title, String content) async {
    final response =
        await apiClient.post(ApiEndpoints.forumThreads(forumId), data: {'title': title, 'content': content});
    return ForumThread.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ForumComment> reply(String threadId, String content, {String? parentId}) async {
    final response = await apiClient.post(ApiEndpoints.threadComments(threadId),
        data: {'content': content, if (parentId != null) 'parent_id': parentId});
    return ForumComment.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<VoteResult> voteThread(String threadId, int value) async {
    final response = await apiClient.put(ApiEndpoints.threadVote(threadId), data: {'value': value});
    return VoteResult.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<VoteResult> voteComment(String commentId, int value) async {
    final response = await apiClient.put(ApiEndpoints.commentVote(commentId), data: {'value': value});
    return VoteResult.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteThread(String threadId) async {
    await apiClient.delete(ApiEndpoints.thread(threadId));
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await apiClient.delete(ApiEndpoints.comment(commentId));
  }
}

/// In-memory version for mock mode.
class MockForumRepository implements IForumRepository {
  static final _threads = <ForumThread>[];
  static final _threadVotes = <String, int>{};
  static final _commentVotes = <String, int>{};

  @override
  Future<String> forumId(ForumScope scope, String scopeId) async => 'forum_${scope.name}_$scopeId';

  ForumThread _withVotes(ForumThread t) => ForumThread(
        id: t.id, forumId: t.forumId, title: t.title, authorId: t.authorId, authorName: t.authorName,
        preview: t.comments.isEmpty ? t.preview : t.comments.first.content, score: _threadVotes[t.id] ?? 0,
        viewerVote: _threadVotes[t.id] ?? 0, replyCount: t.comments.length - 1, lastCommentAt: t.lastCommentAt,
        createdAt: t.createdAt, viewerCanModerate: true,
        comments: [
          for (final c in t.comments)
            ForumComment(id: c.id, parentId: c.parentId, authorId: c.authorId, authorName: c.authorName,
                content: c.content, createdAt: c.createdAt, score: _commentVotes[c.id] ?? 0,
                viewerVote: _commentVotes[c.id] ?? 0),
        ],
      );

  @override
  Future<List<ForumThread>> fetchThreads(ThreadQuery query) async {
    final search = query.search.trim().toLowerCase();
    final list = _threads
        .where((t) => t.forumId == query.forumId && (search.isEmpty || t.title.toLowerCase().contains(search)))
        .map(_withVotes)
        .toList();
    switch (query.sort) {
      case ForumSort.top:
        list.sort((a, b) => b.score.compareTo(a.score));
      case ForumSort.hot:
      case ForumSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  @override
  Future<ForumThread> getThread(String threadId) async => _withVotes(_threads.firstWhere((t) => t.id == threadId));

  @override
  Future<ForumThread> createThread(String forumId, String title, String content) async {
    final now = DateTime.now();
    final thread = ForumThread(
      id: 'th_${now.microsecondsSinceEpoch}', forumId: forumId, title: title, authorId: 'me', authorName: 'You',
      createdAt: now,
      comments: [ForumComment(id: 'cm_${now.microsecondsSinceEpoch}', authorId: 'me', authorName: 'You',
          content: content, createdAt: now)],
    );
    _threads.add(thread);
    _threadVotes[thread.id] = 1;
    return _withVotes(thread);
  }

  @override
  Future<ForumComment> reply(String threadId, String content, {String? parentId}) async {
    final i = _threads.indexWhere((t) => t.id == threadId);
    final t = _threads[i];
    final now = DateTime.now();
    final comment = ForumComment(id: 'cm_${now.microsecondsSinceEpoch}', parentId: parentId, authorId: 'me',
        authorName: 'You', content: content, createdAt: now);
    _threads[i] = ForumThread(id: t.id, forumId: t.forumId, title: t.title, authorId: t.authorId,
        authorName: t.authorName, createdAt: t.createdAt, lastCommentAt: now, comments: [...t.comments, comment]);
    _commentVotes[comment.id] = 1;
    return comment;
  }

  @override
  Future<VoteResult> voteThread(String threadId, int value) async {
    _threadVotes[threadId] = value;
    return VoteResult(value, value);
  }

  @override
  Future<VoteResult> voteComment(String commentId, int value) async {
    _commentVotes[commentId] = value;
    return VoteResult(value, value);
  }

  @override
  Future<void> deleteThread(String threadId) async => _threads.removeWhere((t) => t.id == threadId);

  @override
  Future<void> deleteComment(String commentId) async {}
}
