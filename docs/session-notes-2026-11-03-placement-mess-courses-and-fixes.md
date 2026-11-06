# CampusHub — Forums, Mess Menus, Placement Imports, Course Materials & Fixes

*2–3 Nov 2026, branch `backend_v2`, commits `059c78a`, `d1a5896`, `60a9dce`*

Picks up where [session-notes-2026-11-02-trust-moderation-and-fixes.md](session-notes-2026-11-02-trust-moderation-and-fixes.md)
stops. Database revision 16 → 23 (migrations `017`–`023`). Nothing was deployed: everything was tested
locally against `campushub-db-1` / `campushub-s3-1`, with seed users only. The OTP warning in the 2 Nov
notes still applies before merging into `main`.

## Round 1 — forums, events moderators, placement tabs (`059c78a`, migration `017`)

- **Reddit-style forums** shared by companies and events: votes, replies to replies, sort by New/Top,
  search ([forum_board.dart](../frontend/lib/features/forums/ui/forum_board.dart),
  [thread_view.dart](../frontend/lib/features/forums/ui/thread_view.dart)); replaced the old company forum.
- **Community Events:** posters, a forum per event, and an Events moderator role that moderates them;
  reports on event-forum posts go to the events queue.
- **Placement Hub:** Companies / Schedule / Statistics tabs; the schedule holds online tests and
  interviews next to pre-placement talks; CSV imports for companies and placement dates
  ([placement_csv.py](../backend/app/placement_csv.py)).
- Also in this commit (parallel session): category-suggest accuracy eval
  ([category-suggest-accuracy.md](category-suggest-accuracy.md)), cloud-deploy diagnostic scripts,
  theme / Wanted feed / listing dialog updates from the 2 Nov notes.

## Round 2 — mess menus, messages, placement fixes (`d1a5896`, migrations `018`–`020`)

- **Mess menus:** a moderator uploads the PDF or photo, the meals are read by OCR
  ([mess_extract.py](../backend/app/mess_extract.py), Tesseract) into a form to check, then posted; menus
  by mess name (a new name adds the mess); one Food/Mess event card per mess; meal alerts sent when
  notifications are requested, with no scheduler.
- **Messages:** delete a chat or a message for me, delete for everyone (visibly), people search, general
  chats from company seniors, Back returns to where the chat was opened.
- **Placement Hub:** "Talk to seniors" from the hiring sheets, any email accepted in sheets,
  placement-office interview/test CSV formats, "Time TBA" for dates without a time, Upcoming/Past
  schedule, single-select filters, no duplicate Manage button.
- Wanted matches skip hidden or held listings; strike count shown with the rules; forum votes start at 0.
- Docs: [placement-csv-formats.md](placement-csv-formats.md), OCR in [SLMs.md](SLMs.md), API and deployment.
- Flutter tests brought up to date; fixed a filter reset after dispose and a phone toolbar overflow.

## Round 3 — compensation, sentiment, courses, deletes, imports (`60a9dce`, migrations `021`–`023`)

### Placement Hub
- **Roles and compensation import** (migration `021`, [placement_roles.py](../backend/app/placement_roles.py)):
  both placement-office shapes, free-text pay read into rupees a year ("15.05 lakhs", "₹32 LPA", ranges,
  per month), placeholders dropped, duplicate roles merged. Companies show headline pay; companies can be
  deleted; mock placement data cleaned up.
- **Excel CSVs:** files saved by Excel on Windows (Windows-1252, not UTF-8) import; header aliases such as
  "Selected Company", "IISc Email Id", "Job title"; error lines point to where a row starts.
- **Season from the file name** ("FT 2025-26" → 2026) in the import dialog.
- **Schedule sheets (slot 1–3):** headers with a line break ("Date⏎[MM/DD/YYYY]"), month-first dates,
  "7-Oct-26", "Venue of Interview", round taken from the file name ("slot 2 test schedule.csv"), "No test" /
  "CANCELLED" kept in the details, two days in one cell → two dates, "Shortlist Released?" in the details.
- **The hub lists every company** (it fetched only the first 50, so only "A" names showed).
- **Top search** covers all modules: Placement Hub companies and Events & mess menus added.

### Courses (migration `022`)
- **Materials tab:** a shared repository anyone signed in can add to; tags (PYQ, Quiz, Notes, …), 100 MB
  limit, search and tag filters.
- **Upload checks** ([material_check.py](../backend/app/material_check.py)): programs, APKs, JARs, scripts,
  macro documents, ZIP bombs and mismatched types are refused; encrypted/nested archives, PDFs with
  JavaScript, "leaked paper for sale" text and more than 10 uploads an hour are held and auto-flagged to the
  academic moderators.
- **Forum tab** per course, and **Follow** a course: new materials, feedback and forum posts notify
  followers (`course_update`).

### Buy & Sell and moderation
- **Deletes are permanent** (migration `023`): deleting a listing or Wanted post (owner, moderator or
  admin) removes it, its photos, watches and reports. Strikes and chats keep a copy of the title. A
  moderator removing a *reported* listing still hides it with a strike so the seller can appeal. Earlier
  soft-deleted posts were purged.
- **Strike notices:** contesting a strike notifies Buy & Sell moderators and admins; overturning, keeping
  it, or lifting a suspension notifies the seller.

### Mess menus
- Removed the duplicate "Upload a mess menu" button (Post a menu does it).
- **D and E mess showed nothing this month:** their November menus had been posted as files only, so the
  meals could only go into December. A menu with meals now replaces an overlapping file-only menu; local
  data fixed (menus run 2 Nov – 31 Dec).
- **D mess cells read better:** one dish per line with no separators used to run together; lines are now
  joined as dishes unless a name wrapped. "Daily … items" notes under the table are read.
- Rotated (weekly-repeating) menus.

### Other
- Pluggable sentiment backends for the survival guide (local int8 RoBERTa or Comprehend;
  `CAMPUSHUB_SENTIMENT_BACKEND`).
- Messages UI fixes, Enter-to-send in forums, events posting limited to moderators.

## Verification

Backend 245 tests pass, Flutter 109 pass, `flutter analyze` clean. Checked in the browser (web build on
:8083): course Materials/Forum/Follow, top search sections, mess page, D mess meals, Placement Hub list
past "A", schedule Past view. All six slot schedule files imported through the API with 0 rejected rows.
**Not tested in the browser:** an actual material upload and strike notifications (covered by tests).

## Before deploying

Run migrations `017`–`023` in order ([cloud-deployment-checklist.md](cloud-deployment-checklist.md)).
Old company cards such as "Accenture [Mock Assessment]" from imports before bracket handling are left as
they are.
