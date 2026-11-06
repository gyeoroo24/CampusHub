import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/forum_repository.dart';
import '../domain/forum_models.dart';

final forumRepositoryProvider = Provider<IForumRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockForumRepository();
  }
  return ApiForumRepository(ref.watch(apiClientProvider));
});

/// The forum id of a company or event.
final forumIdProvider = FutureProvider.family<String, (ForumScope, String)>((ref, key) {
  return ref.watch(forumRepositoryProvider).forumId(key.$1, key.$2);
});

final forumThreadsProvider = FutureProvider.family<List<ForumThread>, ThreadQuery>((ref, query) {
  ref.watch(currentUserProvider); // the viewer's own votes
  return ref.watch(forumRepositoryProvider).fetchThreads(query);
});

final forumThreadProvider = FutureProvider.family<ForumThread, String>((ref, threadId) {
  ref.watch(currentUserProvider);
  return ref.watch(forumRepositoryProvider).getThread(threadId);
});
