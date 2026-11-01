# CampusHub — Features Added & Bugs Fixed

*As-of 25 Oct 2026*

This session on 25 Oct 2026 added one feature (teammate OTP sign-in by real email code) and fixed six reported bugs in CampusHub (frontend: Flutter web; backend: FastAPI). All work is local only — nothing deployed to Vercel in this pass.

## New Features

### Report content (listings & lost/found posts)

Signed-in users can now flag a listing or a lost/found post for moderator review.

- A flag icon on the listing/lost-found detail dialog opens a report form (preset reasons + free text)
- Submits to the existing backend endpoint `POST /api/v1/reports` (already supported `target_type`, `target_id`, `reason` — just wasn't wired to any UI)
- New `createReport()` added to `IAdminRepository` (mock + API implementations)
- Shows up immediately in the moderator Reports Queue

### Clickable moderator reports

Report cards in the Reports Queue are now clickable: tapping one fetches and opens the actual listing or lost/found post it's about, instead of just showing `Target: listing` as plain text.

### Real OTP email for dev sign-in

The sign-in flow previously accepted *any* 6-digit code ("Mock Mode: enter any 6 digits"). Replaced with a working OTP system:

- New backend module generates a random 6-digit code, hashes it, expires it after 10 minutes, rate-limits resends (30s cooldown) and caps wrong attempts (5)
- New endpoints `POST /api/v1/auth/otp/request` and `POST /api/v1/auth/otp/verify`
- Sends via SMTP if configured (`CAMPUSHUB_SMTP_*` env vars) — otherwise logs the code to the backend console so local dev works with no mail account
- Only active in `auth_mode=dev`; a 404 in Cognito/production mode leaves that flow untouched
- Frontend dialog now shows a real error ("Incorrect code", "That code expired") instead of always succeeding

### Vercel deployment (earlier in session)

Deployed the Flutter web build to Vercel, proxied through Cloudflare tunnels so the hosted app talks to the local backend and MinIO for live data and images.

## Bugs Fixed

| # | Bug | Root cause | Fix |
| --- | --- | --- | --- |
| 1 | Course review page lost on refresh — URL stayed `/courses` | `context.push()` only updates go_router's internal imperative stack, not the actual browser URL | Switched to `context.go('/courses/:id')` in `courses_screen.dart` and `super_search_bar.dart` |
| 2 | Lost & Found category chips hard-clipped against the Report buttons | No visual treatment for the scrollable row ending under fixed-width buttons | Added a `ShaderMask` fade-out gradient on the trailing edge in `lost_found_filter_bar.dart` |
| 3 | Filters stayed applied after navigating away and back to a tab | `buySellFilterProvider` / `lostFoundFilterProvider` are app-lifetime providers, unaffected by tab-widget unmounting | Reset filter state in each screen's `dispose()`. Hit a Riverpod gotcha along the way: `ref` is invalid during `dispose()`, and providers can't be written mid-teardown — fixed by capturing the notifier in `initState()` and deferring the reset via `Future(() => ...)` |
| 4 | Moderator report cards weren't clickable | No navigation wired to the report's `target_type` / `target_id` | Cards now fetch and open the actual listing/lost-found post on tap |
| 5 | No way for users to report bad content | Backend endpoint existed (`POST /api/v1/reports`) but no frontend UI called it | Added report flag buttons + `ReportContentDialog` (see Features) |
| 6 | OTP sign-in accepted any 6 digits | Dev auth flow never actually generated or checked a code — purely client-side theater | Built real OTP generation/verification (see Features) |

All six verified live in the browser: refreshed at `/courses/<id>` and stayed; confirmed the chip fade visually; applied a filter, switched tabs, confirmed it reset with no console errors; clicked a report and watched it open the right listing; submitted a report as one test account and saw it land in another's moderator queue; rejected a wrong OTP, then signed in with the real emailed/logged code.

## Known Limitations & Follow-ups

- **SMTP not configured**: OTP codes currently print to the backend log instead of emailing. Give the credentials (Gmail app password, SendGrid, etc.) to wire real delivery.
- **Phone number OTP not implemented**: there's no existing phone-verification flow to hook into (phone is a free-text profile field), and real SMS needs a paid provider (Twilio/AWS SNS).
- **Vercel deployment is tunnel-dependent**: the hosted app only shows live data while the local backend, MinIO and the Cloudflare tunnels stay running on that machine — it's not an independent cloud deployment.

## Also Shipped Yesterday (24 Oct 2026, `backend_v2` branch)

Not part of today's session, but landed the day before on GitHub — included here since it's recent and adjacent work on the same repo.

### Fixed bugs from the 23 Oct backend review

- Verified-email-only account creation; re-created/relinked Cognito accounts handled; parallel first sign-ins fixed
- Dev sign-in now requires `CAMPUSHUB_ALLOW_DEV_AUTH=true` and only works from the local machine
- Strict ASCII email validation; 503 when Cognito keys can't be fetched; every route now checks the token
- Admins can edit others' content (logged); new `PATCH /users/{id}` to deactivate accounts
- Concurrent report resolution made safe; removing content closes its reports; atomic moderator grant/revoke
- Upload URLs sign file size, failed uploads are deleted, S3 403 maps to 422, signed CloudFront links
- 422 responses for bad ids/blank text, escaped search, stable paging, forum read-counts fixed
- Push notification timeout, Lambda logging/defaults, Secrets Manager, daily notification purge job
- 35 new tests (78 passing total)

### Local network sharing + single-admin handover

- Dev sign-in from other machines on the same network now requires a team key (`X-Dev-Key`)
- Postgres and MinIO console restricted to localhost in docker-compose
- New `POST /users/{id}/make-admin`: hands the admin role to someone else, downgrading the current admin in the same transaction (DB now enforces exactly one admin)
- 80 tests passing

### Saved searches, Wanted posts, campus services, course survival guide

- **Saved searches**: 5 endpoints; new matching listings/found reports trigger a notification once per item, with a badge count
- **Wanted posts**: 7 endpoints; new listings matching category/budget/title word trigger a notification; posts can be reported
- **Campus services**: public read / admin write endpoints, seeded with real IISc Health Centre, Wellness Centre and grievance links
- **Course survival guide**: `GET /courses/{id}/survival-guide` — per-semester sentiment, trend, themes and repeated advice, computed with the word-list sentiment scorer (`app/sentiment.py`) described below
- Schema rev 6 (`db/migrations/006_taking_it_further.sql`); 88 endpoints, 90 tests passing

### How the course feedback analytics work

The survival guide's sentiment/theme analysis (`app/sentiment.py`) is **not** an LLM or ML model call — it's a hand-built, VADER-style lexicon scorer. No API calls, no inference cost, instant.

1. **Sentence splitting**: each review is split into sentences by punctuation.
2. **Word-list scoring**: every word is looked up in a ~70-word weighted dictionary (`best`/`great` = +3, `hard`/`tough` = -1, etc.). Booster words (`very`, `extremely`) scale the nearest sentiment word up; negators (`not`, `never`, `without`) flip it.
3. **Multi-word phrases**: a second dictionary catches phrases single words miss (`"highly recommend"` = +3, `"not worth"` = -3, `"too much"` = -2).
4. **"But" handling**: in a sentence like *"Great content, but the workload is heavy"*, words after "but" are weighted 1.25x and words before it 0.75x, so mixed reviews land as mixed rather than falsely positive or negative.
5. **Normalizing to −1..+1**: the summed weight is squashed with `x / sqrt(x² + 15)`, then labeled positive (`> 0.25`), negative (`< -0.25`), or mixed (in between).
6. **Themes**: each sentence is matched against regex patterns for 7 themes — workload, exams, assignments/projects, teaching, grading, prerequisites, pace/content — and tagged with every theme it mentions.
7. **Advice extraction**: sentences starting with imperative verbs ("start", "avoid", "brush up", "expect"...) or containing "should"/"recommend" are pulled out as repeatable advice.
8. **Aggregation**: per-semester and overall scores, positive/negative shares, a trend (improving/declining/steady), and the most-mentioned themes are computed from all of a course's sentence scores and surfaced on `GET /courses/{id}/survival-guide`.

The module's own docstring says this is a deliberate placeholder: it keeps the same -1..+1 output shape as a real sentiment API, so swapping in Amazon Comprehend (`DetectSentiment`) or a Bedrock model later is a drop-in replacement with no API shape changes needed.
