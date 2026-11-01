import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_exception.dart';
import '../domain/messages_models.dart';

/// The backend's messaging API. Message bodies travel as ciphertext (see `ChatCrypto`), but the
/// server also holds each user's key for now, so it is not end-to-end encrypted.
class MessagesRepository {
  final ApiClient apiClient;

  MessagesRepository(this.apiClient);

  /// My key and its backup (the plain private key, or an older passphrase backup), or null if I
  /// haven't set up messaging.
  Future<ChatKeyBackup?> fetchMyKey() async {
    try {
      final r = await apiClient.get(ApiEndpoints.myChatKey);
      return ChatKeyBackup.fromJson(r.data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Uploads a key (set-up, new passphrase, or a replacement key). [body] comes from `ChatCrypto.keyUpload`.
  Future<ChatKeyBackup> putMyKey(Map<String, dynamic> body) async {
    final r = await apiClient.put(ApiEndpoints.myChatKey, data: body);
    return ChatKeyBackup.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<Conversation>> fetchConversations() async {
    final r = await apiClient.get(ApiEndpoints.chatConversations, queryParameters: {'limit': 100});
    return (r.data as List).map((j) => Conversation.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<int> fetchUnreadCount() async {
    final r = await apiClient.get(ApiEndpoints.chatUnread);
    return (r.data as Map<String, dynamic>)['unread_messages'] as int? ?? 0;
  }

  /// Opens (or reopens) my chat with the owner of what [target] names, adding it as a topic:
  /// `{'listing_id': …}`, `{'lost_report_id': …}`, `{'found_report_id': …}`, or `{'user_id': …}` for a
  /// general chat. There is one chat per person, so this returns the existing one if we've talked.
  Future<({Conversation conversation, String? topicId})> startConversation(Map<String, String> target) async {
    final r = await apiClient.post(ApiEndpoints.chatConversations, data: target);
    final j = r.data as Map<String, dynamic>;
    return (
      conversation: Conversation.fromJson(j['conversation'] as Map<String, dynamic>),
      topicId: j['topic_id'] as String?,
    );
  }

  Future<Conversation> fetchConversation(String id) async {
    final r = await apiClient.get(ApiEndpoints.chatConversation(id));
    return Conversation.fromJson(r.data as Map<String, dynamic>);
  }

  /// The latest page ([before] null), older history ([before] = oldest seq loaded),
  /// or every change after [after] (a changed_seq).
  Future<MessagePage> fetchMessages(String conversationId, {int? after, int? before, int limit = 50}) async {
    final r = await apiClient.get(ApiEndpoints.chatMessages(conversationId), queryParameters: {
      'limit': limit,
      if (after != null) 'after': after,
      if (before != null) 'before': before,
    });
    return MessagePage.fromJson(r.data as Map<String, dynamic>);
  }

  /// [body] comes from `ChatCrypto.encrypt` plus the two key ids.
  Future<EncryptedMessage> sendMessage(String conversationId, Map<String, dynamic> body) async {
    final r = await apiClient.post(ApiEndpoints.chatMessages(conversationId), data: body);
    return EncryptedMessage.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> markRead(String conversationId, int seq) async {
    await apiClient.post(ApiEndpoints.chatRead(conversationId), data: {'seq': seq});
  }

  /// [action] is accept, decline or withdraw.
  Future<EncryptedMessage> answerOffer(String messageId, String action) async {
    final r = await apiClient.post(ApiEndpoints.chatOffer(messageId), data: {'action': action});
    return EncryptedMessage.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> unsend(String messageId) async {
    await apiClient.delete(ApiEndpoints.chatMessage(messageId));
  }

  Future<void> block(String userId) async {
    await apiClient.put(ApiEndpoints.chatBlock(userId));
  }

  Future<void> unblock(String userId) async {
    await apiClient.delete(ApiEndpoints.chatBlock(userId));
  }

  Future<List<({String id, String name})>> fetchBlocked() async {
    final r = await apiClient.get(ApiEndpoints.chatBlocks);
    return (r.data as List)
        .map((j) => (id: (j as Map)['id'] as String, name: j['name'] as String))
        .toList();
  }
}
