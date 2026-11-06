import 'package:campus_hub/features/events/domain/event_models.dart';
import 'package:campus_hub/features/forums/domain/forum_models.dart';
import 'package:campus_hub/features/placement/domain/placement_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a thread parses votes and nested replies', () {
    final t = ForumThread.fromJson({
      'id': 't1', 'forum_id': 'f1', 'title': 'Resume tips', 'author': {'id': 'u1', 'name': 'Asha'},
      'preview': 'Keep it short', 'score': 3, 'viewer_vote': 1, 'comment_count': 3, 'reply_count': 2,
      'created_at': '2026-11-02T10:00:00Z', 'viewer_can_moderate': false,
      'comments': [
        {'id': 'c0', 'author': {'id': 'u1', 'name': 'Asha'}, 'content': 'Keep it short', 'created_at': '2026-11-02T10:00:00Z'},
        {'id': 'c1', 'parent_id': null, 'author': {'id': 'u2', 'name': 'Kiran'}, 'content': 'One page',
         'score': 2, 'viewer_vote': -1, 'created_at': '2026-11-02T10:05:00Z'},
        {'id': 'c2', 'parent_id': 'c1', 'author': {'id': 'u1', 'name': 'Asha'}, 'content': null, 'removed': true,
         'created_at': '2026-11-02T10:06:00Z'},
      ],
    });
    expect((t.score, t.viewerVote, t.replyCount), (3, 1, 2));
    expect(t.openingPost!.id, 'c0');
    expect(t.replies.map((c) => c.parentId), [null, 'c1']);
    expect(t.replies.first.viewerVote, -1);
    expect(t.replies.last.removed, isTrue);
    expect(ForumSort.newest.apiValue, 'new');
  });

  test('older thread payloads without reply_count still count replies', () {
    final t = ForumThread.fromJson({'id': 't', 'forum_id': 'f', 'title': 'x', 'comment_count': 4});
    expect(t.replyCount, 3);
  });

  test('schedule entries and companies carry their kind', () {
    final p = Ppt.fromJson({'id': 'p', 'company_id': 'c', 'company_name': 'IBM', 'kind': 'oa', 'when': 'upcoming'});
    expect(p.kind, PptKind.oa);
    expect(PptKind.parse('nonsense'), PptKind.ppt);
    final c = Company.fromJson({'id': 'c', 'name': 'IBM', 'next_date_at': '2026-11-20T12:30:00Z', 'next_date_kind': 'interview'});
    expect(c.nextDateKind, PptKind.interview);
    final r = CsvImportResult.fromJson({
      'rows_total': 3, 'rows_created': 2, 'rows_updated': 0, 'rows_rejected': 1, 'companies_created': ['IBM'],
      'rejected_rows': [{'line': 4, 'reason': 'Name is empty.'}],
    });
    expect((r.rowsCreated, r.rejectedRows.single.line), (2, 4));
  });

  test('an event draft sends the poster only when it changes', () {
    final base = EventDraft(title: 'Fest', startTime: DateTime(2026, 11, 8, 17), endTime: DateTime(2026, 11, 8, 19), tagIds: [1]);
    expect(base.toJson().containsKey('poster_s3_key'), isFalse);
    final withPoster = EventDraft(title: 'Fest', startTime: base.startTime, endTime: base.endTime, tagIds: [1],
        posterKey: 'event-posters/u/p.png');
    expect(withPoster.toJson()['poster_s3_key'], 'event-posters/u/p.png');
    final removed = EventDraft(title: 'Fest', startTime: base.startTime, endTime: base.endTime, tagIds: [1], removePoster: true);
    expect(removed.toJson().containsKey('poster_s3_key'), isTrue);
    expect(removed.toJson()['poster_s3_key'], isNull);
    expect(CampusEvent.fromJson({'id': 'e', 'title': 'x', 'start_time': '2026-11-08T11:30:00Z',
        'end_time': '2026-11-08T13:30:00Z', 'poster_url': 'https://x/p.png'}).posterUrl, 'https://x/p.png');
  });
}
