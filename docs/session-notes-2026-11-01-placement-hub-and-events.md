# CampusHub — Placement Hub and Community Events

*1 Nov 2026, branch `backend_v3` (from `backend_v2`)*

This round built the two PRD modules that only had database tables until now: **Placement Hub**
(FR-15, FR-16, FR-17) and **Community Events** with bookmarks (FR-18, FR-19, FR-20, FR-22). Both
have a backend API and app screens. Database revision 12 → 13 (migration `013`). Nothing was deployed.

## Schema (rev 13)

The tables from rev 3 already fit the PRD. Rev 13 only adds columns the screens need:

| Table | New columns | Why |
| --- | --- | --- |
| `companies` | `website`, `industry` | Company page details |
| `job_descriptions` | `description`, `compensation` | The JD as text; before, only an optional file key existed |
| `ppt_info` | `venue` | Where the pre-placement talk is |
| `interview_experiences` | `is_anonymous`, `placement_year` | Same anonymity rule as course feedback; which season the interview was for |

`reference-data.sql` now also adds the default event tags (Sports, Food/Mess, Nature, Photography,
Culture, Music, Tech Talks, Workshops).

**Upgrading an existing database:** run `db/migrations/016_placement_and_events.sql (first numbered 013)`, then
`db/reference-data.sql` (safe to run twice).

## Placement Hub

- **Company pages:** details, JDs, PPTs and headline numbers. Missing JDs and PPTs come back as
  empty lists, so the app shows explicit empty states (FR-15).
- **Hiring statistics:** per year and role, from the imported placement sheets, plus a "seasons at
  a glance" summary and top recruiters. **Totals only:** no endpoint returns students' emails.
- **Interview experiences (FR-16):** any signed-in student posts one under a company, optionally
  anonymously. The author edits; Placement Hub moderators remove; anyone can report.
- **Company forum:** the shared forums code now covers companies too (`GET /companies/{id}/forum`).
- **Placement sheet import (FR-17):** a moderator pastes the sheet (cells copied from Excel or
  Sheets, or a CSV) and picks the season. Each row is created, updated (same student, same season)
  or rejected with its line number and reason. New companies are created automatically. The pasted
  text is kept in S3 as the import's source. The parser is `app/placement_sheet.py`.
- **Who can do what:** Placement Hub moderators and admins add/edit companies, JDs and PPTs and
  import sheets; only an admin can delete a company, because that also deletes its hiring records.

## Community Events

- **Timeline:** happening now, then upcoming (soonest first), then past. Past/Present/Upcoming is
  worked out from the clock on every request (FR-19).
- **Tags (FR-18):** filter by one or more tags. The admin manages the tag list.
- **Posting:** any signed-in user can post an event; the organizer or an admin edits or cancels it.
- **Bookmarks:** account-synced for signed-in users (`/me/bookmarks`, which also accepts listings),
  on-device for guests. When a guest signs in, their saved events are imported to the account
  (`POST /me/bookmarks/import`).
- **Alerts (FR-20, FR-22):**
  - `followed_tag_event`: a new event carries a tag you follow.
  - `bookmarked_event_update`: an event you bookmarked changed its time, place, title or details, or was cancelled.
  - Tapping either notification opens the event. Nobody is alerted about their own changes or
    about events that are over.

## App (Flutter)

- Two new tabs: **Placements** (`/placements`, company page at `/placements/:id`) and **Events**
  (`/events`, event page at `/events/:id` for notification links). The phone bottom bar is now
  "fixed" type so all five labels show.
- **Placements tab:** seasons chart and top recruiters, upcoming PPTs, latest interview
  experiences, a searchable company grid. Moderators get a **Manage** menu (add company, import sheet).
- **Company page:** Overview (about, JDs, PPTs, with moderator edit controls), Hiring stats (last
  3 years, or all), Interviews (share / edit / remove / report), Forum (threads and replies).
- **Events tab:** Now & upcoming / Past / Saved, search, tag filters, **Follow tags**, and an
  **Add event** form.
- **Notifications:** event alerts open the event; `forum_reply` now opens the thread. Before, it
  opened nothing.
- **Mock mode** has in-memory Placement and Events repositories like the other modules.
- **JD files:** the API accepts a JD file (upload kind `job_description`). The app has no
  general file picker yet (only `image_picker`), so it edits JDs as text and shows a link when a
  file exists.

## Tests

- **Backend:** 16 new tests in `tests/test_placement_hub.py` and `tests/test_events.py`. They cover
  the FR-15–FR-20 acceptance criteria, the permission matrix for both modules, revoked moderators,
  imports with bad rows, anonymity, and every alert rule. Full suite: 153 passed, 1 skipped.
- **Flutter:** `test/placement_and_events_test.dart` covers model parsing, the mock repositories
  and guest bookmarks. **Not run in this session**: the machine's Flutter SDK (Dart 3.1) is older
  than the project needs (Dart ≥ 3.13). The new Dart files were syntax-checked with `dart format`
  and their JSON fields were checked against real API responses, but they still need
  `flutter analyze` and `flutter test` on a current SDK.

## Not done

- Landing page highlights across modules (FR-21).
- Events can't be reported (events aren't a permission module; `report_target_type` has no `event`).
- Push delivery is still log-only for the new alerts too; the in-app inbox works.
