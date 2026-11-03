import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_hub/features/events/data/events_repository.dart';
import 'package:campus_hub/features/events/domain/event_models.dart';
import 'package:campus_hub/features/placement/data/placement_repository.dart';
import 'package:campus_hub/features/placement/domain/placement_models.dart';

void main() {
  group('Placement Hub models', () {
    test('company page JSON parses, with explicit empty JD/PPT lists', () {
      final c = Company.fromJson({
        'id': 'c1',
        'name': 'Walmart Global Tech',
        'industry': 'Retail technology',
        'description': null,
        'website': 'https://careers.walmart.com',
        'role_count': 0,
        'interview_count': 2,
        'next_ppt_at': null,
        'latest_year': 2026,
        'latest_year_selected': 3,
        'total_selected': 7,
        'job_descriptions': [],
        'ppts': [],
        'viewer_can_manage': true,
        'created_at': '2026-11-01T10:00:00Z',
        'updated_at': '2026-11-01T10:00:00Z',
      });
      expect(c.initials, 'WG');
      expect(c.jobDescriptions, isEmpty);
      expect(c.ppts, isEmpty);
      expect(c.latestYear, 2026);
      expect(c.viewerCanManage, isTrue);
    });

    test('hiring stats keep the newest year first with roles', () {
      final s = HiringStats.fromJson({
        'company_id': 'c1',
        'company_name': 'Google',
        'total_selected': 5,
        'years': [
          {
            'year': 2026,
            'students_selected': 3,
            'roles': [
              {'role_title': 'SWE', 'students_selected': 2},
              {'role_title': 'Research Engineer', 'students_selected': 1},
            ],
          },
          {'year': 2025, 'students_selected': 2, 'roles': []},
        ],
      });
      expect(s.years.map((y) => y.year), [2026, 2025]);
      expect(s.years.first.roles.first.roleTitle, 'SWE');
    });

    test('anonymous interview experiences hide the author unless they are mine', () {
      Map<String, dynamic> json({required bool mine}) => {
            'id': 'i1',
            'company_id': 'c1',
            'company_name': 'Google',
            'role_title': 'SDE',
            'placement_year': 2026,
            'content': 'Two rounds.',
            'is_anonymous': true,
            'is_mine': mine,
            'author': mine ? {'id': 'u1', 'name': 'Asha'} : null,
            'created_at': '2026-11-01T10:00:00Z',
          };
      expect(InterviewExperience.fromJson(json(mine: false)).displayAuthor, 'Anonymous student');
      expect(InterviewExperience.fromJson(json(mine: true)).displayAuthor, 'Asha');
    });

    test('import result lists rejected rows by line', () {
      final r = ImportResult.fromJson({
        'placement_year': 2026,
        'rows_total': 4,
        'rows_created': 2,
        'rows_updated': 1,
        'rows_rejected': 1,
        'companies_created': ['google'],
        'rejected_rows': [
          {'line': 5, 'reason': "“x@gmail.com” isn't an IISc email address."},
        ],
      });
      expect(r.rejectedRows.single.line, 5);
      expect(r.companiesCreated, ['google']);
    });

    test('mock repository searches companies and posts interviews', () async {
      final repo = MockPlacementRepository();
      expect((await repo.fetchCompanies(query: 'finance')).map((c) => c.name), ['Goldman Sachs']);
      final posted = await repo.postInterview('co_nvidia', roleTitle: 'DL Engineer', content: 'CUDA questions.');
      expect(posted.isMine, isTrue);
      expect((await repo.fetchInterviews(companyId: 'co_nvidia')).first.id, posted.id);
      await repo.deleteInterview(posted.id);
    });
  });

  group('Community events', () {
    test('event JSON parses tags, when and bookmark state', () {
      final e = CampusEvent.fromJson({
        'id': 'e1',
        'title': 'Bird walk',
        'description': null,
        'location': 'Main gate',
        'start_time': '2026-11-08T01:30:00Z',
        'end_time': '2026-11-08T03:30:00Z',
        'when': 'present',
        'tags': [
          {'id': 3, 'name': 'Nature'},
        ],
        'organizer': {'id': 'u1', 'name': 'Asha'},
        'bookmark_count': 4,
        'is_bookmarked': true,
        'can_edit': false,
        'created_at': '2026-11-01T10:00:00Z',
        'updated_at': '2026-11-01T10:00:00Z',
      });
      expect(e.when, EventWhen.present);
      expect(e.tags.single.name, 'Nature');
      expect(e.isBookmarked, isTrue);
      expect(e.organizerName, 'Asha');
    });

    test('a draft sends UTC times and drops blank optional fields', () {
      final json = EventDraft(
        title: 'Jam',
        description: '  ',
        location: 'Gymkhana',
        startTime: DateTime.utc(2026, 11, 8, 12),
        endTime: DateTime.utc(2026, 11, 8, 14),
        tagIds: const [1],
      ).toJson();
      expect(json['description'], isNull);
      expect(json['start_time'], '2026-11-08T12:00:00.000Z');
      expect(json['tag_ids'], [1]);
    });

    test('mock repository splits now/upcoming from past and filters by tag', () async {
      final repo = MockEventsRepository();
      final now = await repo.fetchEvents();
      expect(now.every((e) => e.when != EventWhen.past), isTrue);
      expect(now.first.when, EventWhen.present); // happening now comes first
      final past = await repo.fetchEvents(when: {EventWhen.past});
      expect(past.every((e) => e.when == EventWhen.past), isTrue);
      final sports = await repo.fetchEvents(tagIds: {5});
      expect(sports.every((e) => e.tags.any((t) => t.id == 5)), isTrue);
    });

    test('guest bookmarks persist on the device', () async {
      SharedPreferences.setMockInitialValues({});
      final store = GuestBookmarks();
      await store.save({'e1', 'e2'});
      expect(await GuestBookmarks().load(), {'e1', 'e2'});
    });
  });
}
