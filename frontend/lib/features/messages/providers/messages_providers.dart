import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../../buy_sell/domain/buy_sell_item.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../crypto/chat_crypto.dart';
import '../data/chat_key_store.dart';
import '../data/messages_repository.dart';
import '../domain/messages_models.dart';

/// Null in mock mode: encrypted messaging needs the live backend.
final messagesRepositoryProvider = Provider<MessagesRepository?>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) return null;
  return MessagesRepository(ref.watch(apiClientProvider));
});

final chatKeyStoreProvider = Provider<ChatKeyStore>((ref) => ChatKeyStore());

// ------------------------------------------------------------------------------------ session
enum ChatSessionStatus {
  /// Guest, or mock mode.
  unavailable,

  /// Only for accounts that set a messaging passphrase before it was removed, on a device that
  /// never unlocked it: enter it once and the key moves to the server-held backup.
  locked,
  ready,
}

class ChatSession {
  final ChatSessionStatus status;
  final String? userId;
  final ChatKeyBackup? serverKey;
  final ChatIdentity? identity;

  const ChatSession(this.status, {this.userId, this.serverKey, this.identity});

  bool get isReady => status == ChatSessionStatus.ready;
  String? get keyId => serverKey?.id;
}

/// Whether this device can read and send messages. There is no passphrase: the first visit makes a
/// key and the server keeps it, so every browser the user signs in on opens messages directly.
class ChatSessionNotifier extends AsyncNotifier<ChatSession> {
  MessagesRepository get _repo => ref.read(messagesRepositoryProvider)!;
  ChatKeyStore get _store => ref.read(chatKeyStoreProvider);
  String get _userId => ref.read(currentUserProvider)!.id;

  @override
  Future<ChatSession> build() async {
    final user = ref.watch(currentUserProvider);
    final repo = ref.watch(messagesRepositoryProvider);
    if (repo == null || user == null || user.isGuest) return const ChatSession(ChatSessionStatus.unavailable);
    final serverKey = await repo.fetchMyKey();
    if (serverKey == null) return _ready(user.id, await _upload(repo, await ChatCrypto.generateIdentity()));

    ChatIdentity? identity;
    final local = await _store.read(user.id);
    if (local != null && local.keyId == serverKey.id) identity = await ChatIdentity.fromPrivateKey(local.privateKey);
    if (identity == null && serverKey.isServerHeld) identity = await ChatIdentity.fromPrivateKey(serverKey.keyBackup);
    if (identity == null || !listEquals(identity.publicKey, serverKey.publicKey)) {
      // An old passphrase backup this device never unlocked (or a key replaced elsewhere).
      if (local != null) await _store.remove(user.id);
      return ChatSession(ChatSessionStatus.locked, userId: user.id, serverKey: serverKey);
    }
    // Same key, so its id and every message stay as they were; only the backup changes.
    if (!serverKey.isServerHeld) return _ready(user.id, await _upload(repo, identity));
    return _ready(user.id, (key: serverKey, identity: identity));
  }

  Future<({ChatKeyBackup key, ChatIdentity identity})> _upload(MessagesRepository repo, ChatIdentity identity) async =>
      (key: await repo.putMyKey(ChatCrypto.serverHeldUpload(identity)), identity: identity);

  Future<ChatSession> _ready(String userId, ({ChatKeyBackup key, ChatIdentity identity}) k) async {
    await _store.write(userId, k.key.id, k.identity.privateKey);
    return ChatSession(ChatSessionStatus.ready, userId: userId, serverKey: k.key, identity: k.identity);
  }

  /// Legacy: unlock an old passphrase backup once. Throws [WrongPassphraseException].
  Future<void> unlock(String passphrase) async {
    final serverKey = state.requireValue.serverKey!;
    final identity = await ChatCrypto.unlockBackup(
      userId: _userId,
      keyBackup: serverKey.keyBackup,
      salt: serverKey.backupSalt!,
      iterations: serverKey.backupIterations!,
      passphrase: passphrase,
    );
    if (!listEquals(identity.publicKey, serverKey.publicKey)) throw const WrongPassphraseException();
    state = AsyncData(await _ready(_userId, await _upload(_repo, identity)));
  }

  /// Legacy, forgotten passphrase: start over with a new key. Old messages can't be read any more.
  Future<void> resetKey() async {
    state = AsyncData(await _ready(_userId, await _upload(_repo, await ChatCrypto.generateIdentity())));
  }
}

final chatSessionProvider = AsyncNotifierProvider<ChatSessionNotifier, ChatSession>(ChatSessionNotifier.new);

// --------------------------------------------------------------------------------- decryption
/// Decrypts messages for one signed-in identity, caching each conversation's derived key.
class MessageDecryptor {
  final ChatSession session;
  final Map<String, PublicChatKey> keys = {};
  final Map<String, SecretKey> _conversationKeys = {};

  MessageDecryptor(this.session);

  Future<SecretKey> conversationKey(String conversationId, PublicChatKey peerKey) async {
    final cacheKey = '$conversationId|${session.keyId}|${peerKey.id}';
    return _conversationKeys[cacheKey] ??=
        await ChatCrypto.conversationKey(session.identity!, peerKey.publicKey, conversationId);
  }

  Future<ChatMessage> open(EncryptedMessage m) async {
    final mine = m.senderId == session.userId;
    if (m.isDeleted) return ChatMessage(raw: m, mine: mine);
    final myKeyId = mine ? m.senderKeyId : m.recipientKeyId;
    final peerKey = keys[mine ? m.recipientKeyId : m.senderKeyId];
    if (myKeyId != session.keyId) {
      return ChatMessage(
          raw: m,
          mine: mine,
          unreadableReason: 'Sent to a messaging key you have since replaced, so it can’t be read here.');
    }
    if (peerKey == null) {
      return ChatMessage(raw: m, mine: mine, unreadableReason: 'The key for this message is missing.');
    }
    try {
      final content = await ChatCrypto.decrypt(
        conversationKey: await conversationKey(m.cryptoContextId, peerKey),
        conversationId: m.cryptoContextId,
        messageId: m.id,
        senderId: m.senderId,
        kind: m.kind,
        nonce: m.nonce!,
        ciphertext: m.ciphertext!,
      );
      return ChatMessage(
        raw: m,
        mine: mine,
        text: content['text']?.toString(),
        offerAmount: content['amount']?.toString(),
        offerNote: content['note']?.toString(),
      );
    } on MessageTamperedException {
      return ChatMessage(
          raw: m, mine: mine, unreadableReason: 'This message failed its integrity check and was hidden.');
    }
  }
}

// -------------------------------------------------------------------------------------- inbox
class InboxEntry {
  final Conversation conversation;
  final ChatMessage? lastMessage;

  const InboxEntry(this.conversation, this.lastMessage);
}

/// My conversations with their last message decrypted; refreshed every 15 seconds.
final conversationsProvider = FutureProvider<List<InboxEntry>>((ref) async {
  final repo = ref.watch(messagesRepositoryProvider);
  final session = await ref.watch(chatSessionProvider.future);
  if (repo == null || session.status == ChatSessionStatus.unavailable) return [];
  final timer = Timer(const Duration(seconds: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final conversations = await repo.fetchConversations();
  final decryptor = session.isReady ? MessageDecryptor(session) : null;
  return [
    for (final c in conversations)
      InboxEntry(c, await _openLast(decryptor, c)),
  ];
});

Future<ChatMessage?> _openLast(MessageDecryptor? decryptor, Conversation c) async {
  final last = c.lastMessage;
  if (last == null) return null;
  if (decryptor == null) return ChatMessage(raw: last, mine: false, unreadableReason: 'Locked');
  if (c.peerKey != null) decryptor.keys[c.peerKey!.id] = c.peerKey!;
  return decryptor.open(last);
}

/// Unread messages for the app-bar badge; refreshed every 20 seconds.
final chatUnreadCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(messagesRepositoryProvider);
  if (repo == null || ref.watch(isGuestUserProvider)) return 0;
  final timer = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return repo.fetchUnreadCount();
});

// ------------------------------------------------------------------------------- conversation
class ConversationState {
  final Conversation? conversation;
  final Map<String, ChatMessage> messages;
  final bool loading;
  final Object? error;
  final bool hasOlder;
  final bool loadingOlder;

  const ConversationState({
    this.conversation,
    this.messages = const {},
    this.loading = true,
    this.error,
    this.hasOlder = false,
    this.loadingOlder = false,
  });

  List<ChatMessage> get ordered => messages.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

  ConversationState copyWith({
    Conversation? conversation,
    Map<String, ChatMessage>? messages,
    bool? loading,
    Object? error,
    bool clearError = false,
    bool? hasOlder,
    bool? loadingOlder,
  }) =>
      ConversationState(
        conversation: conversation ?? this.conversation,
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        hasOlder: hasOlder ?? this.hasOlder,
        loadingOlder: loadingOlder ?? this.loadingOlder,
      );
}

/// One open conversation: loads the latest messages, then polls for changes every 3 seconds
/// (new messages, answered offers, unsent messages) and marks what arrives as read.
class ConversationController extends AutoDisposeFamilyNotifier<ConversationState, String> {
  static const pollInterval = Duration(seconds: 3);

  late MessagesRepository _repo;
  late MessageDecryptor _decryptor;
  int _cursor = 0;
  bool _polling = false;

  @override
  ConversationState build(String conversationId) {
    final session = ref.watch(chatSessionProvider).valueOrNull;
    final repo = ref.watch(messagesRepositoryProvider);
    if (repo == null || session == null || !session.isReady) {
      return ConversationState(loading: false, error: Exception('Unlock your messages first.'));
    }
    _repo = repo;
    _decryptor = MessageDecryptor(session);
    _cursor = 0;
    final timer = Timer.periodic(pollInterval, (_) => _poll());
    ref.onDispose(timer.cancel);
    Future.microtask(_loadLatest);
    return const ConversationState();
  }

  String get _id => arg;

  Future<Map<String, ChatMessage>> _merge(MessagePage page) async {
    for (final k in page.keys) {
      _decryptor.keys[k.id] = k;
    }
    final peerKey = page.conversation.peerKey;
    if (peerKey != null) _decryptor.keys[peerKey.id] = peerKey;
    final merged = Map.of(state.messages);
    for (final m in page.items) {
      merged[m.id] = await _decryptor.open(m);
    }
    return merged;
  }

  Future<void> _loadLatest() async {
    try {
      final page = await _repo.fetchMessages(_id);
      _cursor = page.conversation.lastSeq;
      state = state.copyWith(
          conversation: page.conversation,
          messages: await _merge(page),
          loading: false,
          hasOlder: page.hasMore,
          clearError: true);
      await _markRead();
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> _poll() async {
    if (_polling || state.loading) return;
    _polling = true;
    try {
      MessagePage page;
      do {
        page = await _repo.fetchMessages(_id, after: _cursor, limit: 100);
        final messages = await _merge(page);
        for (final m in page.items) {
          if (m.changedSeq > _cursor) _cursor = m.changedSeq;
        }
        state = state.copyWith(conversation: page.conversation, messages: messages, clearError: true);
        if (page.items.isNotEmpty) ref.invalidate(conversationsProvider);   // inbox preview
      } while (page.hasMore);
      await _markRead();
    } catch (e) {
      debugPrint('[Messages] poll failed: $e');
    } finally {
      _polling = false;
    }
  }

  /// The view is open, so everything loaded from the other person counts as read.
  Future<void> _markRead() async {
    final conversation = state.conversation;
    if (conversation == null) return;
    final latest = state.messages.values.where((m) => !m.mine).fold<int>(0, (a, m) => m.seq > a ? m.seq : a);
    if (latest > conversation.myLastReadSeq) {
      await _repo.markRead(_id, latest);
      ref.invalidate(chatUnreadCountProvider);
    }
  }

  Future<void> loadOlder() async {
    if (!state.hasOlder || state.loadingOlder || state.messages.isEmpty) return;
    state = state.copyWith(loadingOlder: true);
    try {
      final oldest = state.messages.values.map((m) => m.seq).reduce((a, b) => a < b ? a : b);
      final page = await _repo.fetchMessages(_id, before: oldest);
      state = state.copyWith(messages: await _merge(page), hasOlder: page.hasMore, loadingOlder: false);
    } catch (e) {
      state = state.copyWith(loadingOlder: false);
      rethrow;
    }
  }

  Future<void> _send(String kind, Map<String, dynamic> content, String? topicId, {bool retried = false}) async {
    final c = state.conversation!;
    if (!c.canSend || c.peerKey == null || c.myKeyId == null) {
      throw Exception(c.cantSendReason ?? 'You can’t send messages here right now.');
    }
    final sealed = await ChatCrypto.encrypt(
      conversationKey: await _decryptor.conversationKey(c.id, c.peerKey!),
      conversationId: c.id,
      senderId: _decryptor.session.userId!,
      kind: kind,
      content: content,
    );
    try {
      final sent = await _repo.sendMessage(c.id, {
        ...sealed,
        'sender_key_id': c.myKeyId,
        'recipient_key_id': c.peerKey!.id,
        'topic_id': topicId,
      });
      _decryptor.keys[c.peerKey!.id] = c.peerKey!;
      state = state.copyWith(messages: {...state.messages, sent.id: await _decryptor.open(sent)});
    } on ApiException catch (e) {
      // 409: a key changed since we loaded the conversation (e.g. they set up a new phone).
      // Fetch the current keys and encrypt again, once.
      if (e.statusCode == 409 && !retried) {
        state = state.copyWith(conversation: await _repo.fetchConversation(c.id));
        if (state.conversation!.canSend) return _send(kind, content, topicId, retried: true);
      }
      rethrow;
    }
    unawaited(_poll());
  }

  /// [topicId]: what it is about (one of the conversation's topics), or null for general chat.
  Future<void> sendText(String text, {String? topicId}) => _send('text', {'text': text}, topicId);

  /// An offer is always about one listing topic.
  Future<void> sendOffer(String topicId, String amount, String? note) =>
      _send('offer', {'amount': amount, if (note != null && note.isNotEmpty) 'note': note}, topicId);

  Future<void> answerOffer(String messageId, String action) async {
    await _repo.answerOffer(messageId, action);
    await _poll();
    if (action == 'accept') {
      // The backend reserved the listing: show it as Reserved in the feed and on the listing.
      final topic = state.conversation!.topic(state.messages[messageId]?.topicId);
      if (topic == null || !topic.isListing) return;
      final listingId = topic.refId;
      ref.read(buySellPaginationProvider.notifier).updateItemStatusLocally(listingId, ListingStatus.reserved);
      ref.invalidate(buySellListingsProvider);
      ref.invalidate(myBuySellListingsProvider);
      ref.invalidate(listingDetailProvider(listingId));
    }
  }

  Future<void> unsend(String messageId) async {
    await _repo.unsend(messageId);
    await _poll();
  }

  Future<void> hideForMe(String messageId) async {
    await _repo.hideMessage(messageId);
    state = state.copyWith(messages: Map.of(state.messages)..remove(messageId));
  }

  Future<void> deleteChat() => _repo.deleteConversation(_id);

  Future<void> setBlocked(bool blocked) async {
    final c = state.conversation!;
    blocked ? await _repo.block(c.peerId) : await _repo.unblock(c.peerId);
    state = state.copyWith(conversation: await _repo.fetchConversation(c.id));
  }
}

final conversationControllerProvider =
    NotifierProvider.autoDispose.family<ConversationController, ConversationState, String>(ConversationController.new);
