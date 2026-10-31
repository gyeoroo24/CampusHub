import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_hub/features/messages/crypto/chat_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List b64(String s) => Uint8List.fromList(base64Decode(s));

/// Produced by the backend's reference implementation (backend/tests/chat_crypto.py) with fixed
/// keys and nonces, so these tests prove the app and the reference agree byte for byte.
const _alice = '11111111-1111-4111-8111-111111111111';
const _bob = '22222222-2222-4222-8222-222222222222';
const _conversation = '33333333-3333-4333-8333-333333333333';
const _message = '44444444-4444-4444-8444-444444444444';
final _vector = {
  'a_private': 'AAIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH2A=',
  'a_public': 'B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=',
  'b_private': 'YGZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg0Q=',
  'b_public': 'VxR2nRFr92Q2rnS8eT0sMK0ZA8WaxSc4BcfiaYtBDDY=',
  'conversation_key': '6PGqxKKNm0/Clo3kk/Af3Ix5K3b356rArqYoweiLd3w=',
  'nonce': 'AAECAwQFBgcICQoL',
  'ciphertext': 'xcMFeV2fFfBgUBnUPl+pmSM+qEON6ZNCAKW9zyPS1YioRqjzSOh16PsinXoB6PQ5qj4iSu3rbt/F5Gr6RR+E4xf5Bm14fJdygrM5A1IkX8c1qgI1+G8=',
  'backup': 'RkdISUpLTE1OT1BRlIu+XkDWZ9x82z5pyu0QjFgUX4+gwXHR1SsASOPZr8Xjo+mGD2V+vuhIKzkQZjP9',
  'salt': 'MjM0NTY3ODk6Ozw9Pj9AQQ==',
  'safety': '20320 85683 81406 84594 25827 21317 66398 66910 41988 13708 26991 86178',
};

void main() {
  group('matches the backend reference implementation', () {
    test('public keys and the conversation key', () async {
      final a = await ChatIdentity.fromPrivateKey(b64(_vector['a_private']!));
      final b = await ChatIdentity.fromPrivateKey(b64(_vector['b_private']!));
      expect(base64Encode(a.publicKey), _vector['a_public']);
      expect(base64Encode(b.publicKey), _vector['b_public']);
      final fromA = await ChatCrypto.conversationKey(a, b.publicKey, _conversation);
      final fromB = await ChatCrypto.conversationKey(b, a.publicKey, _conversation);
      expect(base64Encode(await fromA.extractBytes()), _vector['conversation_key']);
      expect(await fromB.extractBytes(), await fromA.extractBytes());
    });

    test('decrypts a message the reference encrypted', () async {
      final b = await ChatIdentity.fromPrivateKey(b64(_vector['b_private']!));
      final key = await ChatCrypto.conversationKey(b, b64(_vector['a_public']!), _conversation);
      final content = await ChatCrypto.decrypt(
        conversationKey: key,
        conversationId: _conversation,
        messageId: _message,
        senderId: _alice,
        kind: 'offer',
        nonce: b64(_vector['nonce']!),
        ciphertext: b64(_vector['ciphertext']!),
      );
      expect(content, {'v': 1, 'type': 'offer', 'amount': '2400', 'note': 'Cash, today ✓'});
    });

    test('unlocks a key backup the reference made, and makes the same one', () async {
      final unlocked = await ChatCrypto.unlockBackup(
        userId: _alice,
        keyBackup: b64(_vector['backup']!),
        salt: b64(_vector['salt']!),
        iterations: 100000,
        passphrase: 'correct horse battery',
      );
      expect(base64Encode(unlocked.publicKey), _vector['a_public']);
      final upload = await ChatCrypto.keyUpload(unlocked,
          userId: _alice,
          passphrase: 'correct horse battery',
          iterations: 100000,
          salt: b64(_vector['salt']!),
          nonce: b64(_vector['backup']!).sublist(0, 12));
      expect(upload['key_backup'], _vector['backup']);
      expect(upload['public_key'], _vector['a_public']);
      expect(upload['backup_kdf'], 'pbkdf2-sha256');
    });

    test('safety number', () async {
      final a = b64(_vector['a_public']!), b = b64(_vector['b_public']!);
      expect(await ChatCrypto.safetyNumber(_alice, a, _bob, b), _vector['safety']);
      expect(await ChatCrypto.safetyNumber(_bob, b, _alice, a), _vector['safety']);
    });
  });

  group('protects messages', () {
    late ChatIdentity alice, bob, eve;
    late SecretKey aliceKey, bobKey;

    setUpAll(() async {
      alice = await ChatCrypto.generateIdentity();
      bob = await ChatCrypto.generateIdentity();
      eve = await ChatCrypto.generateIdentity();
      aliceKey = await ChatCrypto.conversationKey(alice, bob.publicKey, _conversation);
      bobKey = await ChatCrypto.conversationKey(bob, alice.publicKey, _conversation);
    });

    Future<Map<String, dynamic>> open(SecretKey key, Map<String, dynamic> m,
            {String? conversation, String? sender, String? kind, String? id}) =>
        ChatCrypto.decrypt(
          conversationKey: key,
          conversationId: conversation ?? _conversation,
          messageId: id ?? m['id'] as String,
          senderId: sender ?? _alice,
          kind: kind ?? m['kind'] as String,
          nonce: b64(m['nonce'] as String),
          ciphertext: b64(m['ciphertext'] as String),
        );

    test('round trip, with fresh ids and nonces every time', () async {
      final m1 = await ChatCrypto.encrypt(
          conversationKey: aliceKey, conversationId: _conversation, senderId: _alice, kind: 'text',
          content: {'text': 'Is the cycle still available? 🚲'});
      final m2 = await ChatCrypto.encrypt(
          conversationKey: aliceKey, conversationId: _conversation, senderId: _alice, kind: 'text',
          content: {'text': 'Is the cycle still available? 🚲'});
      expect((await open(bobKey, m1))['text'], 'Is the cycle still available? 🚲');
      expect((await open(aliceKey, m1))['text'], 'Is the cycle still available? 🚲'); // the sender too
      expect(m1['id'], isNot(m2['id']));
      expect(m1['nonce'], isNot(m2['nonce']));
      expect(m1['ciphertext'], isNot(m2['ciphertext']));
      expect(utf8.decode(base64Decode(m1['ciphertext'] as String), allowMalformed: true), isNot(contains('cycle')));
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(m1['id'] as String),
          isTrue);
    });

    test('a third person, or anything altered, is rejected', () async {
      final m = await ChatCrypto.encrypt(
          conversationKey: aliceKey, conversationId: _conversation, senderId: _alice, kind: 'offer',
          content: {'amount': '2000'});
      final eveKey = await ChatCrypto.conversationKey(eve, alice.publicKey, _conversation);
      final throwsTampered = throwsA(isA<MessageTamperedException>());
      await expectLater(open(eveKey, m), throwsTampered);
      await expectLater(open(bobKey, m, sender: _bob), throwsTampered); // pretend Bob sent it
      await expectLater(open(bobKey, m, kind: 'text'), throwsTampered);
      await expectLater(open(bobKey, m, id: ChatCrypto.newMessageId()), throwsTampered);
      // The same two people in another conversation have a different key.
      final otherKey = await ChatCrypto.conversationKey(bob, alice.publicKey, '55555555-5555-4555-8555-555555555555');
      await expectLater(open(otherKey, m), throwsTampered);
      final flipped = b64(m['ciphertext'] as String)..[0] ^= 1;
      await expectLater(open(bobKey, {...m, 'ciphertext': base64Encode(flipped)}), throwsTampered);
    });

    test('a wrong passphrase does not unlock the backup', () async {
      final upload = await ChatCrypto.keyUpload(alice, userId: _alice, passphrase: 'right one', iterations: 100000);
      Future<ChatIdentity> unlock(String userId, String passphrase) => ChatCrypto.unlockBackup(
            userId: userId,
            keyBackup: b64(upload['key_backup'] as String),
            salt: b64(upload['backup_salt'] as String),
            iterations: 100000,
            passphrase: passphrase,
          );
      expect((await unlock(_alice, 'right one')).publicKey, alice.publicKey);
      await expectLater(unlock(_alice, 'wrong one'), throwsA(isA<WrongPassphraseException>()));
      await expectLater(unlock(_bob, 'right one'), throwsA(isA<WrongPassphraseException>()));
    });
  });
}
