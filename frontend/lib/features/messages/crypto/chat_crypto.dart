import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for Buy & Sell messages (protocol "campushub-chat-v1").
///
/// Messages are encrypted and decrypted on the device, and the backend stores ciphertext. For
/// now, though, the app also uploads each user's private key in plain form ([serverHeldUpload]),
/// so nobody needs a passphrase and the SERVER CAN READ MESSAGES: this is not end-to-end
/// encryption yet (true E2E, e.g. passkeys plus device linking, is a planned improvement). The backend's tests use a
/// Python implementation of the same protocol (backend/tests/chat_crypto.py), and
/// test/messages/chat_crypto_test.dart checks the two agree byte for byte.
///
///  * identity key — X25519 key pair per user; the public half is uploaded.
///  * key backup — now just the plain private key (kdf "none"). Older accounts may still have
///    a passphrase backup: the private key, AES-256-GCM encrypted under
///    PBKDF2-SHA256(passphrase, salt, iterations), stored as nonce(12) || ciphertext || tag(16),
///    AAD = `campushub-chat-key-backup-v1|{user id}`. Lets another device unlock the key.
///  * conversation key — HKDF-SHA256(X25519(mine, theirs), salt = "campushub-chat-v1",
///    info = `campushub-chat-v1|conv={conversation id}|` || lower public key || higher public key).
///  * message — AES-256-GCM with a random 12-byte nonce over UTF-8 JSON, AAD =
///    `campushub-chat-v1|{conversation id}|{message id}|{sender id}|{kind}`, so the server can't
///    move a message to another chat, change who sent it, or turn text into an offer.
///  * safety number — 12 groups of 5 digits from SHA-512 of both users' ids and public keys;
///    the same on both phones, and different if the server ever swapped a key.
class ChatCrypto {
  ChatCrypto._();

  static const protocol = 'campushub-chat-v1';
  static const _backupAad = 'campushub-chat-key-backup-v1';
  static const kdfName = 'pbkdf2-sha256';
  static const serverHeldKdf = 'none';

  /// OWASP's 2023 figure for PBKDF2-HMAC-SHA256. Runs once per device when unlocking.
  static const defaultIterations = 600000;

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _random = Random.secure();

  static Uint8List randomBytes(int length) =>
      Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  /// A random UUID v4, used as a message id (it is part of the message's AAD).
  static String newMessageId() {
    final b = randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<ChatIdentity> generateIdentity() => ChatIdentity.fromPrivateKey(randomBytes(32));

  /// Body for `PUT /me/chat-key` with no passphrase: the server keeps the plain private key.
  static Map<String, dynamic> serverHeldUpload(ChatIdentity identity) => {
        'public_key': base64Encode(identity.publicKey),
        'key_backup': base64Encode(identity.privateKey),
        'backup_kdf': serverHeldKdf,
      };

  /// Body for `PUT /me/chat-key`: the public key and the private key sealed under [passphrase].
  static Future<Map<String, dynamic>> keyUpload(
    ChatIdentity identity, {
    required String userId,
    required String passphrase,
    int iterations = defaultIterations,
    Uint8List? salt,
    Uint8List? nonce,
  }) async {
    salt ??= randomBytes(16);
    nonce ??= randomBytes(12);
    final wrapKey = await _passphraseKey(passphrase, salt, iterations);
    final box = await _aesGcm.encrypt(
      identity.privateKey,
      secretKey: wrapKey,
      nonce: nonce,
      aad: utf8.encode('$_backupAad|$userId'),
    );
    return {
      'public_key': base64Encode(identity.publicKey),
      'key_backup': base64Encode([...nonce, ...box.cipherText, ...box.mac.bytes]),
      'backup_salt': base64Encode(salt),
      'backup_kdf': kdfName,
      'backup_iterations': iterations,
    };
  }

  /// Opens a key backup from `GET /me/chat-key`. Throws [WrongPassphraseException] if the
  /// passphrase is wrong (or the backup isn't this user's).
  static Future<ChatIdentity> unlockBackup({
    required String userId,
    required Uint8List keyBackup,
    required Uint8List salt,
    required int iterations,
    required String passphrase,
  }) async {
    if (keyBackup.length < 12 + 16 + 32) throw const WrongPassphraseException();
    final wrapKey = await _passphraseKey(passphrase, salt, iterations);
    try {
      final privateKey = await _aesGcm.decrypt(
        SecretBox(
          keyBackup.sublist(12, keyBackup.length - 16),
          nonce: keyBackup.sublist(0, 12),
          mac: Mac(keyBackup.sublist(keyBackup.length - 16)),
        ),
        secretKey: wrapKey,
        aad: utf8.encode('$_backupAad|$userId'),
      );
      return await ChatIdentity.fromPrivateKey(Uint8List.fromList(privateKey));
    } on SecretBoxAuthenticationError {
      throw const WrongPassphraseException();
    }
  }

  static Future<SecretKey> _passphraseKey(String passphrase, List<int> salt, int iterations) {
    return Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  /// The AES key both people derive for a conversation.
  static Future<SecretKey> conversationKey(
    ChatIdentity mine,
    Uint8List theirPublicKey,
    String conversationId,
  ) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: await mine.keyPair(),
      remotePublicKey: SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
    );
    final ordered = _compareBytes(mine.publicKey, theirPublicKey) <= 0
        ? [mine.publicKey, theirPublicKey]
        : [theirPublicKey, mine.publicKey];
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: utf8.encode(protocol),
      info: [...utf8.encode('$protocol|conv=$conversationId|'), ...ordered[0], ...ordered[1]],
    );
  }

  static List<int> _aad(String conversationId, String messageId, String senderId, String kind) =>
      utf8.encode('$protocol|$conversationId|$messageId|$senderId|$kind');

  /// Encrypts [content] (e.g. `{'text': 'Hi'}` or `{'amount': '2400'}`) into the fields for
  /// `POST /chat/conversations/{id}/messages`, without the key ids.
  static Future<Map<String, dynamic>> encrypt({
    required SecretKey conversationKey,
    required String conversationId,
    required String senderId,
    required String kind,
    required Map<String, dynamic> content,
    String? messageId,
    Uint8List? nonce,
  }) async {
    messageId ??= newMessageId();
    nonce ??= randomBytes(12);
    final plaintext = utf8.encode(jsonEncode({'v': 1, 'type': kind, ...content}));
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: conversationKey,
      nonce: nonce,
      aad: _aad(conversationId, messageId, senderId, kind),
    );
    return {
      'id': messageId,
      'kind': kind,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Decrypts a message. Throws [MessageTamperedException] if the ciphertext, or anything it is
  /// bound to (conversation, id, sender, kind), was changed, or it was encrypted for other keys.
  static Future<Map<String, dynamic>> decrypt({
    required SecretKey conversationKey,
    required String conversationId,
    required String messageId,
    required String senderId,
    required String kind,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) async {
    if (ciphertext.length < 16) throw const MessageTamperedException();
    try {
      final plaintext = await _aesGcm.decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - 16),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
        ),
        secretKey: conversationKey,
        aad: _aad(conversationId, messageId, senderId, kind),
      );
      final content = jsonDecode(utf8.decode(plaintext));
      if (content is! Map<String, dynamic> || content['type'] != kind) {
        throw const MessageTamperedException();
      }
      return content;
    } on SecretBoxAuthenticationError {
      throw const MessageTamperedException();
    } on FormatException {
      throw const MessageTamperedException();
    }
  }

  /// Twelve groups of five digits; compare them in person to be sure no one is in the middle.
  static Future<String> safetyNumber(
    String userA,
    Uint8List publicA,
    String userB,
    Uint8List publicB,
  ) async {
    final pairs = [(userA, publicA), (userB, publicB)]..sort((x, y) => x.$1.compareTo(y.$1));
    final digest = (await Sha512().hash([
      ...utf8.encode('campushub-safety-v1'),
      ...utf8.encode(pairs[0].$1),
      ...pairs[0].$2,
      ...utf8.encode(pairs[1].$1),
      ...pairs[1].$2,
    ]))
        .bytes;
    return List.generate(12, (i) {
      var n = 0;
      for (final b in digest.sublist(i * 5, i * 5 + 5)) {
        n = n * 256 + b;
      }
      return (n % 100000).toString().padLeft(5, '0');
    }).join(' ');
  }

  static int _compareBytes(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}

/// A user's X25519 key pair, unlocked on this device.
class ChatIdentity {
  final Uint8List privateKey;
  final Uint8List publicKey;

  ChatIdentity._(this.privateKey, this.publicKey);

  static Future<ChatIdentity> fromPrivateKey(Uint8List privateKey) async {
    final pair = await X25519().newKeyPairFromSeed(privateKey);
    final public = await pair.extractPublicKey();
    return ChatIdentity._(Uint8List.fromList(await pair.extractPrivateKeyBytes()), Uint8List.fromList(public.bytes));
  }

  Future<SimpleKeyPair> keyPair() => X25519().newKeyPairFromSeed(privateKey);
}

class WrongPassphraseException implements Exception {
  const WrongPassphraseException();
  @override
  String toString() => 'That passphrase is not right.';
}

class MessageTamperedException implements Exception {
  const MessageTamperedException();
  @override
  String toString() => "This message can't be decrypted.";
}
