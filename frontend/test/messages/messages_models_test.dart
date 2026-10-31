import 'package:campus_hub/features/messages/domain/messages_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _topic(String id, String kind, String title, {String status = 'available', Object? price}) => {
      'id': id,
      'kind': kind,
      'ref_id': 'ref-$id',
      'owner_id': 'u2',
      'title': title,
      'description': kind == 'listing' ? null : 'Black leather wallet',
      'price': price,
      'status': status,
      'cover_photo_url': null,
      'is_removed': false,
      'started_by': 'u1',
      'created_at': '2026-10-31T10:00:00Z',
    };

void main() {
  test('one conversation per person carries every topic', () {
    final c = Conversation.fromJson({
      'id': 'c1',
      'peer': {'id': 'u2', 'name': 'Asha', 'is_active': true, 'key': null},
      'topics': [
        _topic('t1', 'listing', 'Hero cycle', price: '2500.00'),
        _topic('t2', 'listing', 'Lamp', status: 'sold', price: '300'),
        _topic('t3', 'lost_report', 'Lost: Wallet', status: 'open'),
      ],
      'my_key_id': null,
      'last_seq': 0,
      'my_last_read_seq': 0,
      'peer_last_read_seq': 0,
      'unread_count': 0,
      'last_message': null,
      'last_message_at': null,
      'created_at': '2026-10-31T10:00:00Z',
      'blocked_by_me': false,
      'can_send': true,
      'cant_send_reason': null,
    });
    expect(c.topics.map((t) => t.title), ['Hero cycle', 'Lamp', 'Lost: Wallet']);
    expect(c.topic('t1')!.price, 2500);
    expect(c.topic('t1')!.canTakeOffers, isTrue);
    expect(c.topic('t2')!.canTakeOffers, isFalse); // sold
    expect(c.topic('t3')!.kind, ChatTopicKind.lostReport);
    expect(c.topic('t3')!.canTakeOffers, isFalse); // offers are for listings
    expect(c.topic(null), isNull);
    expect(c.topic('nope'), isNull);
  });

  test('messages from before the merge keep their old crypto context', () {
    final old = EncryptedMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'crypto_context_id': 'old-listing-chat',
      'topic_id': 't1',
      'seq': 1,
      'changed_seq': 1,
      'sender_id': 'u1',
      'kind': 'text',
      'sender_key_id': 'k1',
      'recipient_key_id': 'k2',
      'nonce': null,
      'ciphertext': null,
      'offer_status': null,
      'sent_at': '2026-10-31T10:00:00Z',
      'deleted_at': '2026-10-31T10:01:00Z',
    });
    expect(old.cryptoContextId, 'old-listing-chat');
    expect(old.topicId, 't1');
  });

  test('items with the same title are told apart by when they were discussed', () {
    Map<String, dynamic> cord(String id, String when) =>
        _topic(id, 'listing', 'Extension cord', price: '200')..['created_at'] = when;
    final c = Conversation.fromJson({
      'id': 'c1',
      'peer': {'id': 'u2', 'name': 'Asha', 'is_active': true, 'key': null},
      'topics': [
        cord('a', '2026-03-10T10:00:00Z'),
        cord('b', '2026-08-02T10:00:00Z'),
        cord('c', '2026-08-20T10:00:00Z'),
        _topic('d', 'listing', 'Lamp'),
      ],
      'my_key_id': null,
      'last_seq': 0,
      'my_last_read_seq': 0,
      'peer_last_read_seq': 0,
      'unread_count': 0,
      'last_message': null,
      'last_message_at': null,
      'created_at': '2026-10-31T10:00:00Z',
      'blocked_by_me': false,
      'can_send': true,
      'cant_send_reason': null,
    });
    expect(c.topics.map((t) => t.label), [
      'Extension cord · Mar 2026',
      'Extension cord · Aug 2026 #1',
      'Extension cord · Aug 2026 #2',
      'Lamp',
    ]);
    expect(c.topic('b')!.title, 'Extension cord');
  });
}
