import 'dart:convert';
import 'dart:typed_data';

import '../crypto/chat_crypto.dart';

/// Shapes returned by the backend's `/chat` and `/me/chat-key` endpoints. Message bodies arrive
/// encrypted; [ChatMessage] is the decrypted view the UI shows.

Uint8List _bytes(Object? b64) => Uint8List.fromList(base64Decode(b64 as String));
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class PublicChatKey {
  final String id;
  final String userId;
  final Uint8List publicKey;
  final bool isCurrent;

  const PublicChatKey({required this.id, required this.userId, required this.publicKey, required this.isCurrent});

  factory PublicChatKey.fromJson(Map<String, dynamic> j) => PublicChatKey(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        publicKey: _bytes(j['public_key']),
        isCurrent: j['is_current'] as bool? ?? true,
      );
}

/// My key as the server stores it. With [backupKdf] "none" (the default now) [keyBackup] is the
/// plain private key; "pbkdf2-sha256" is an older passphrase-encrypted backup.
class ChatKeyBackup {
  final String id;
  final Uint8List publicKey;
  final Uint8List keyBackup;
  final String backupKdf;
  final Uint8List? backupSalt;
  final int? backupIterations;

  const ChatKeyBackup({
    required this.id,
    required this.publicKey,
    required this.keyBackup,
    required this.backupKdf,
    this.backupSalt,
    this.backupIterations,
  });

  bool get isServerHeld => backupKdf == ChatCrypto.serverHeldKdf;

  factory ChatKeyBackup.fromJson(Map<String, dynamic> j) => ChatKeyBackup(
        id: j['id'] as String,
        publicKey: _bytes(j['public_key']),
        keyBackup: _bytes(j['key_backup']),
        backupKdf: j['backup_kdf'] as String? ?? ChatCrypto.kdfName,
        backupSalt: j['backup_salt'] == null ? null : _bytes(j['backup_salt']),
        backupIterations: j['backup_iterations'] as int?,
      );
}

enum OfferStatus {
  pending,
  accepted,
  declined,
  withdrawn,
  superseded;

  static OfferStatus? parse(Object? v) => v == null ? null : OfferStatus.values.firstWhere((s) => s.name == v);

  String get label => switch (this) {
        OfferStatus.pending => 'Waiting for a reply',
        OfferStatus.accepted => 'Accepted',
        OfferStatus.declined => 'Declined',
        OfferStatus.withdrawn => 'Withdrawn',
        OfferStatus.superseded => 'Replaced by a newer offer',
      };
}

class EncryptedMessage {
  final String id;
  final String conversationId;

  /// What the ciphertext is bound to: the conversation id, except for messages written before
  /// chats were merged per person, which keep the id of their old per-listing chat.
  final String cryptoContextId;

  /// What it is about (a [ChatTopic] of the conversation); null for general chat.
  final String? topicId;
  final int seq;
  final int changedSeq;
  final String senderId;
  final String kind;
  final String senderKeyId;
  final String recipientKeyId;
  final Uint8List? nonce;
  final Uint8List? ciphertext;
  final OfferStatus? offerStatus;
  final DateTime sentAt;
  final DateTime? deletedAt;

  const EncryptedMessage({
    required this.id,
    required this.conversationId,
    required this.cryptoContextId,
    required this.topicId,
    required this.seq,
    required this.changedSeq,
    required this.senderId,
    required this.kind,
    required this.senderKeyId,
    required this.recipientKeyId,
    required this.nonce,
    required this.ciphertext,
    required this.offerStatus,
    required this.sentAt,
    required this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get isOffer => kind == 'offer';

  factory EncryptedMessage.fromJson(Map<String, dynamic> j) => EncryptedMessage(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        cryptoContextId: j['crypto_context_id'] as String? ?? j['conversation_id'] as String,
        topicId: j['topic_id'] as String?,
        seq: j['seq'] as int,
        changedSeq: j['changed_seq'] as int,
        senderId: j['sender_id'] as String,
        kind: j['kind'] as String,
        senderKeyId: j['sender_key_id'] as String,
        recipientKeyId: j['recipient_key_id'] as String,
        nonce: j['nonce'] == null ? null : _bytes(j['nonce']),
        ciphertext: j['ciphertext'] == null ? null : _bytes(j['ciphertext']),
        offerStatus: OfferStatus.parse(j['offer_status']),
        sentAt: _date(j['sent_at']) ?? DateTime.now(),
        deletedAt: _date(j['deleted_at']),
      );
}

enum ChatTopicKind {
  listing,
  lostReport,
  foundReport;

  static ChatTopicKind parse(Object? v) => switch (v) {
        'lost_report' => ChatTopicKind.lostReport,
        'found_report' => ChatTopicKind.foundReport,
        _ => ChatTopicKind.listing,
      };
}

/// What part of a chat is about: a listing, or a lost or found report.
class ChatTopic {
  final String id;
  final ChatTopicKind kind;
  final String refId;
  final String ownerId;
  final String title;
  final String? description;
  final double? price;

  /// Listing: available / reserved / sold. Report: open / matched / closed.
  final String status;
  final String? coverPhotoUrl;
  final bool isRemoved;
  final DateTime createdAt;

  /// What the app shows: [title], plus when it was first discussed if this chat has another item
  /// with the same title (e.g. two identical extension cords sold months apart).
  final String label;

  const ChatTopic({
    required this.id,
    required this.kind,
    required this.refId,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.price,
    required this.status,
    required this.coverPhotoUrl,
    required this.isRemoved,
    required this.createdAt,
    String? label,
  }) : label = label ?? title;

  ChatTopic withLabel(String label) => ChatTopic(
        id: id,
        kind: kind,
        refId: refId,
        ownerId: ownerId,
        title: title,
        description: description,
        price: price,
        status: status,
        coverPhotoUrl: coverPhotoUrl,
        isRemoved: isRemoved,
        createdAt: createdAt,
        label: label,
      );

  bool get isListing => kind == ChatTopicKind.listing;

  /// Can still take offers.
  bool get canTakeOffers => isListing && !isRemoved && status != 'sold';

  String get statusLabel => isRemoved ? 'Removed' : status[0].toUpperCase() + status.substring(1);

  factory ChatTopic.fromJson(Map<String, dynamic> j) => ChatTopic(
        id: j['id'] as String,
        kind: ChatTopicKind.parse(j['kind']),
        refId: j['ref_id'] as String,
        ownerId: j['owner_id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        price: j['price'] == null ? null : double.tryParse('${j['price']}'),
        status: j['status'] as String,
        coverPhotoUrl: j['cover_photo_url'] as String?,
        isRemoved: j['is_removed'] as bool? ?? false,
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );
}

/// A chat with one person (everything you've discussed with them, like a WhatsApp chat).
class Conversation {
  final String id;
  final String peerId;
  final String peerName;
  final bool peerActive;
  final PublicChatKey? peerKey;

  /// What it has been about, oldest first.
  final List<ChatTopic> topics;
  final String? myKeyId;
  final int lastSeq;
  final int myLastReadSeq;
  final int peerLastReadSeq;
  final int unreadCount;
  final EncryptedMessage? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final bool blockedByMe;
  final bool canSend;
  final String? cantSendReason;

  const Conversation({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.peerActive,
    required this.peerKey,
    required this.topics,
    required this.myKeyId,
    required this.lastSeq,
    required this.myLastReadSeq,
    required this.peerLastReadSeq,
    required this.unreadCount,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.createdAt,
    required this.blockedByMe,
    required this.canSend,
    required this.cantSendReason,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final peer = j['peer'] as Map<String, dynamic>;
    return Conversation(
      id: j['id'] as String,
      peerId: peer['id'] as String,
      peerName: peer['name'] as String,
      peerActive: peer['is_active'] as bool? ?? true,
      peerKey: peer['key'] == null ? null : PublicChatKey.fromJson(peer['key'] as Map<String, dynamic>),
      topics: _labelled([for (final t in j['topics'] as List? ?? const []) ChatTopic.fromJson(t as Map<String, dynamic>)]),
      myKeyId: j['my_key_id'] as String?,
      lastSeq: j['last_seq'] as int,
      myLastReadSeq: j['my_last_read_seq'] as int,
      peerLastReadSeq: j['peer_last_read_seq'] as int,
      unreadCount: j['unread_count'] as int,
      lastMessage:
          j['last_message'] == null ? null : EncryptedMessage.fromJson(j['last_message'] as Map<String, dynamic>),
      lastMessageAt: _date(j['last_message_at']),
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      blockedByMe: j['blocked_by_me'] as bool? ?? false,
      canSend: j['can_send'] as bool? ?? false,
      cantSendReason: j['cant_send_reason'] as String?,
    );
  }

  DateTime get sortTime => lastMessageAt ?? createdAt;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Items with the same title get told apart by when they were first discussed ("Extension
  /// cord · Mar 2026", "Extension cord · Aug 2026"), and by a number if even that matches.
  static List<ChatTopic> _labelled(List<ChatTopic> topics) {
    String when(ChatTopic t) {
      final d = t.createdAt.toLocal();
      return '${_months[d.month - 1]} ${d.year}';
    }

    final byTitle = <String, List<ChatTopic>>{};
    for (final t in topics) {
      byTitle.putIfAbsent(t.title.trim().toLowerCase(), () => []).add(t);
    }
    return [
      for (final t in topics)
        () {
          final same = byTitle[t.title.trim().toLowerCase()]!;
          if (same.length == 1) return t;
          final sameMonth = same.where((o) => when(o) == when(t)).toList();
          final n = sameMonth.length > 1 ? ' #${sameMonth.indexOf(t) + 1}' : '';
          return t.withLabel('${t.title} · ${when(t)}$n');
        }(),
    ];
  }

  ChatTopic? topic(String? id) => id == null ? null : topics.where((t) => t.id == id).firstOrNull;
}

class MessagePage {
  final Conversation conversation;
  final List<EncryptedMessage> items;
  final List<PublicChatKey> keys;
  final bool hasMore;

  const MessagePage({required this.conversation, required this.items, required this.keys, required this.hasMore});

  factory MessagePage.fromJson(Map<String, dynamic> j) => MessagePage(
        conversation: Conversation.fromJson(j['conversation'] as Map<String, dynamic>),
        items: (j['items'] as List).map((m) => EncryptedMessage.fromJson(m as Map<String, dynamic>)).toList(),
        keys: (j['keys'] as List).map((k) => PublicChatKey.fromJson(k as Map<String, dynamic>)).toList(),
        hasMore: j['has_more'] as bool? ?? false,
      );
}

/// What a message says, once decrypted on this device.
class ChatMessage {
  final EncryptedMessage raw;
  final bool mine;
  final String? text;
  final String? offerAmount;
  final String? offerNote;

  /// Why it can't be shown (e.g. it was encrypted to a key this device doesn't have).
  final String? unreadableReason;

  const ChatMessage({
    required this.raw,
    required this.mine,
    this.text,
    this.offerAmount,
    this.offerNote,
    this.unreadableReason,
  });

  String get id => raw.id;
  int get seq => raw.seq;
  String? get topicId => raw.topicId;
  bool get isDeleted => raw.isDeleted;
  bool get isOffer => raw.isOffer;

  /// One line for the inbox.
  String get preview {
    if (isDeleted) return mine ? 'You unsent a message' : 'Message unsent';
    if (unreadableReason != null) return 'Encrypted message';
    if (isOffer) return '${mine ? 'You offered' : 'Offer:'} ₹$offerAmount';
    return text ?? '';
  }
}
