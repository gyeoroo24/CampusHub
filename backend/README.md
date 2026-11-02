# CampusHub API

Backend for CampusHub, the IISc student community platform (DS252 Introduction to Cloud
Computing, team Order of Phoenix). FastAPI + asyncpg on AWS Lambda (via Mangum), PostgreSQL
on RDS, Cognito sign-in, S3 uploads. The same code runs on EC2 for the Lambda-vs-EC2 comparison.

**Phase 1 is built:** sign-in and profiles, moderator roles, Buy & Sell, Lost & Found (with
matching notifications), Academic Help (departments, courses, materials, feedback), forums,
user reports and the moderation queue, notifications inbox and push-device registration.
Interactive docs for every endpoint: `/docs` (Swagger) and `/redoc`.

## Run it locally

Requires Docker and Python 3.12 or 3.13 (asyncpg 0.30.0 has no Python 3.14 wheels yet).

```bash
docker compose up -d                    # Postgres (schema loaded on first start) + MinIO
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.local.example .env              # dev sign-in, local MinIO (docker compose creates the bucket)
uvicorn app.main:app --reload --env-file .env   # http://localhost:8000/docs
```

`--env-file` also exports the MinIO keys in `.env` (`AWS_ACCESS_KEY_ID`…) to boto3. Without it,
boto3 signs uploads with your own `~/.aws/credentials`, and MinIO rejects them.

`.env.local.example` is for your own machine only. `.env.example` is the template for servers
(EC2, Lambda); it uses Cognito and can't turn dev sign-in on.

In dev mode you act as any IISc user by sending a header; the user is created on their first
request. Dev mode needs both `CAMPUSHUB_AUTH_MODE=dev` and `CAMPUSHUB_ALLOW_DEV_AUTH=true`, only
accepts the header from the machine the API runs on, and refuses to start inside Lambda:

```bash
curl -H "X-Dev-User: asha@iisc.ac.in" -H "X-Dev-Name: Asha" http://localhost:8000/api/v1/me
```

There is exactly one admin (the database enforces it). To make the first admin (after they've made
one request), use SQL; after that, the admin hands the role over with `POST /api/v1/users/{id}/make-admin`:

```bash
docker compose exec db psql -U campushub -c "UPDATE users SET base_role = 'admin' WHERE email = 'asha@iisc.ac.in';"
```

### Dummy data and keeping the database

The database lives in the Docker volume `campushub_pgdata` and the uploaded files in
`campushub_s3data`. Both survive `docker compose stop`, `docker compose down`, quitting Docker
Desktop and restarting the Mac; the containers restart by themselves whenever Docker Desktop
starts (`restart: unless-stopped`). Only `docker compose down -v` or `docker volume rm` deletes
the data. For the containers to come back after a reboot without opening Docker yourself, turn on
Docker Desktop → Settings → General → "Start Docker Desktop when you sign in".

To fill the database with realistic demo data (50 students, the CDS courses from
cds.iisc.ac.in plus a few CSA / EE / ECE ones, three years of course feedback, materials,
forums, listings, Wanted posts, saved searches, Lost & Found reports, placement data, events,
moderation reports, notifications and chats):

```bash
python scripts/seed_dummy_data.py            # once
python scripts/seed_dummy_data.py --reset    # remove the dummy data and add it again
python scripts/seed_dummy_data.py --remove   # remove it, keep everything else
```

Your own users and posts are left alone. Sign in as any dummy user with their email, e.g.
`X-Dev-User: ananya.rao@iisc.ac.in` (the list is `SEED_USERS` in the script).

### Upgrading an existing database

`db/schema.sql` only runs when the volume is brand new. A database created before revision 6
(24 Oct 2026) needs the migration and the campus-services rows once:

```bash
docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/migrations/006_taking_it_further.sql
docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/reference-data.sql
```

A database created before revision 7 (25 Oct 2026: anonymous feedback, one review per person
per course) also needs:

```bash
docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/migrations/007_feedback_rules.sql
```

A database created before revision 11 (31 Oct–1 Nov 2026: in-app messaging, one chat per
person, no "matched" Lost & Found status) needs these, in order:

```bash
for m in 008_encrypted_chat 009_server_held_chat_keys 010_chat_per_person 011_drop_matched_status; do
  docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/migrations/$m.sql
done
```

A database created before revision 12 (1 Nov 2026: Lost & Found matching by description and
photo) needs `012_lf_matching`, then one backfill once the matcher is set up (next section):

```bash
docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/migrations/012_lf_matching.sql
python -m app.matching --backfill
```

A database created before revision 17 (1–2 Nov 2026: seller trust strikes, automatic flagging,
price watch and the Negotiable badge, Placement Hub and Events, then Events moderators, Reddit-style
forums, the placement schedule and event posters) needs these, in order, then
`db/reference-data.sql` once more for the default event tags:

```bash
for m in 013_seller_trust 014_reversible_listing_hide 015_auto_flags_and_price_watch 016_placement_and_events \
         017_forums_events_moderation; do
  docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/migrations/$m.sql
done
```

Automatic flagging (future plan §1.6, `app/screening.py`) is on by default: its text checks use the
category-suggestion model, and the obscene-photo check needs the full model download below
(`scripts/fetch_match_models.py`). Without those models only the keyword, gibberish and spam
checks run. Set `CAMPUSHUB_AUTO_FLAG=false` to turn it off.

### Lost & Found matching (optional locally)

Reports are matched by description and photo with three small ONNX models (future plan §1.2;
code in `app/matching`). Without them the API keeps the old same-category rule, so this step is
optional. To turn it on locally:

```bash
uv pip install -r requirements-matching.txt          # or pip install
python scripts/fetch_match_models.py                  # ~305 MB into backend/models (gitignored)
```

The same download includes the 34 MB model behind category suggestion
(`GET /buy-sell/categories/suggest`, `app/categories_suggest.py`). It runs in the API itself, and
`--suggest-only` fetches just that one; both Dockerfiles do so.
`python scripts/calibrate_category_suggest.py` measures it on labelled titles.

Restart the API: with `CAMPUSHUB_MATCH_MODE=auto` (the default) it finds the models and matches
in a background task. `python scripts/calibrate_matching.py <photo dir>` prints the similarity
scores the thresholds in `app/matching/engine.py` were chosen from.

### Share it on your network

To let teammates on the same Wi-Fi use your running backend (no cloud needed):

1. In `.env`, set:
   - `CAMPUSHUB_DEV_AUTH_KEY` to a long random value. Other machines must send it as the
     `X-Dev-Key` header along with `X-Dev-User`; without it they can only browse as guests.
   - `CAMPUSHUB_S3_ENDPOINT_URL=http://<this laptop's IP>:9000`, so their upload and photo links
     work (on macOS: `ipconfig getifaddr en0`).
   - `AWS_SECRET_ACCESS_KEY` (and `AWS_ACCESS_KEY_ID`) to a new login, because MinIO's port 9000
     is reachable from the network. Then run `docker compose up -d` to restart MinIO with it.
2. Start the API on every interface: `uvicorn app.main:app --reload --env-file .env --host 0.0.0.0`.
3. Teammates open `http://<this laptop's IP>:8000/docs`, click **Authorize**, and enter their
   email (`X-Dev-User`) and the team key (`X-Dev-Key`).

Anyone with the key can act as any user, admins included, so share it only with the team.
Postgres and the MinIO console stay reachable from this machine only. If the laptop's IP
changes, update `CAMPUSHUB_S3_ENDPOINT_URL` and restart the API. Some campus networks block
traffic between laptops; a phone hotspot works around that.

To purge notifications older than 30 days (deployed as a daily scheduled Lambda, see below):

```bash
python -m app.jobs
```

## Tests

```bash
pytest
```

The 78 tests use the real Postgres from docker-compose (database `campushub_test`; set
`CAMPUSHUB_TEST_DATABASE_URL` to use another) and a mocked S3. They cover the PRD
acceptance criteria that the backend owns, and `tests/test_review_fixes.py` covers each bug
fixed after the 23 Oct 2026 review. Among them:

- FR-1: non-IISc emails are rejected.
- FR-3: a revoked moderator's next call is rejected.
- FR-6: the combined filter returns no false positives.
- FR-9: matching notifications.
- FR-10: moderator removal.
- FR-11: the "no data yet" flag.
- FR-13: course and department moderator limits.
- FR-14: thread order.
- NFR-8: signed checksums.

## How sign-in works

- **Guests** send nothing and can read every public feed (FR-1).
- **Signed-in users** send their Cognito **ID token**: `Authorization: Bearer <id_token>`.
  The API checks its signature, expiry, issuer and audience on every route (a bad or expired
  token gets 401 even on pages guests can read), then creates the user's row on their first
  request.
- **Only verified emails get an account.** The first sign-up goes: enter your IISc email and
  a password, Cognito emails a verification code, you type the code in, then you sign in. The
  API refuses tokens whose `email_verified` claim isn't true, so nobody can claim someone
  else's address. Configure the user pool with:
  - email as the username, and email as the auto-verified attribute (verification by code);
  - "Keep original attribute value active when an update is pending" for email, so a changed
    email only takes effect after its new code is entered;
  - the pre sign-up trigger below, which must not auto-verify or auto-confirm users.
- **A re-created Cognito account** (same verified email, new Cognito id) is linked back to the
  person's existing CampusHub account.
- **Roles** come from the database, not from Cognito groups. Admin is `users.base_role`;
  moderator rights are the active rows in `moderator_assignments`. Both are checked on every
  request, so revoking a moderator takes effect on their very next call.
- **Sign-up restriction:** attach `lambdas/cognito_pre_signup.py` as the user pool's
  *Pre sign-up* trigger, so only `…iisc.ac.in` addresses (including subdomains such as
  `alum.iisc.ac.in`) can create accounts.

## Uploading photos and files

1. `POST /api/v1/uploads` with `kind`, `content_type`, `size_bytes` and `checksum_sha256`
   (the base64 SHA-256 of the file). It returns `upload_url`, `headers` and `s3_key`.
   For course materials, also send `course_id`.
2. PUT the file to `upload_url` with exactly those `headers`. S3 rejects the upload if the
   type, size (`size_bytes` is signed as Content-Length) or checksum doesn't match (NFR-8).
   The file is tagged `state=pending`.
3. Send the `s3_key` when creating or editing the post, using `photo_keys` or `s3_key`.
   The API checks that the file is yours and really uploaded, and that its size and type
   are allowed; a file that fails is deleted. Once the post is saved the file is retagged
   `state=attached`. Files left `pending` were never attached; the bucket's lifecycle rule
   deletes them (see Deploying).

| Kind | Allowed types | Max |
|---|---|---|
| listing_photo, lost_report_photo, found_report_photo | jpeg, png, webp, heic | 10 MB, up to 10 per post |
| course_material | pdf, pptx, docx, zip, txt, images | 50 MB |

## Endpoints (all under `/api/v1`)

Who can call each one: guest = no sign-in needed; user = signed in. For the fields each endpoint
takes and returns, written for frontend design, see [docs/api-reference.md](../docs/api-reference.md).

**Users and roles**

| Method & path | Who | What |
|---|---|---|
| GET /health | guest | Health check (CloudWatch canary) |
| GET, PATCH /me | user | My profile, admin flag and active moderator roles; update profile (a phone number can only be removed here) |
| POST /me/phone/code, POST /me/phone/verify | user | Add or change my phone number: a 6-digit code is sent to it, then checked |
| GET /users/{id} | guest | Public profile; email and phone only for signed-in viewers |
| GET /users/lookup?email= | admin | Find an account by email (for deactivating or handing over the admin role) |
| PATCH /users/{id} | admin | Deactivate or reactivate an account (`is_active`); not your own |
| POST /users/{id}/make-admin | admin | Hand the admin role over: there is exactly one admin, so the caller becomes a signed-in user |
| POST /moderators | admin; department moderator for their courses | Grant a moderator role by email |
| DELETE /moderators/{id} | same, or the moderator themselves | Revoke a role, or step down from your own |
| GET /moderators | admin, department moderator | List roles |
| POST /uploads | user | Get a presigned upload URL |

**Buy & Sell**

| Method & path | Who | What |
|---|---|---|
| GET, POST /buy-sell/categories | guest / user | List; add or get the existing category with that name |
| GET /listings | guest | Browse. Filters: `q`, `category_id`, `min_price`, `max_price`, `status`, `seller_id`; `sort` newest / price_asc / price_desc |
| POST /listings | user | Create, with up to 10 `photo_keys` |
| GET /listings/{id} | guest | Detail with photos; seller contact for signed-in users |
| PATCH /listings/{id} | seller, admin | Edit fields; admin edits are logged |
| PATCH /listings/{id}/status | seller, admin | available / reserved / sold |
| PUT /listings/{id}/photos | seller, admin | Replace, reorder or remove photos |
| DELETE /listings/{id} | seller, Buy & Sell moderator, admin | Soft delete; moderator removals are logged |

New, edited or re-opened listings alert matching saved searches and Wanted posts (`app/alerts.py`).

**Wanted posts**

| Method & path | Who | What |
|---|---|---|
| GET /wanted | guest | Browse. Filters: `q`, `category_id`, `status` (default open), `author_id` |
| POST /wanted | user | Post what you need: `title`, `category_id`, `description`, `max_price`. Response lists `possible_matches`; up to 10 open posts each |
| GET /wanted/{id} | guest | Detail; author contact for signed-in users |
| GET /wanted/{id}/matches | guest | Available listings matching the post (same category, within budget, a shared title word) |
| PATCH /wanted/{id} | author, admin | Edit fields |
| PATCH /wanted/{id}/status | author, admin | open / fulfilled / closed |
| DELETE /wanted/{id} | author, Buy & Sell moderator, admin | Soft delete; moderator removals are logged |

**Saved searches and alerts**

| Method & path | Who | What |
|---|---|---|
| GET /me/saved-searches | user | Mine, with `new_count` since I last looked |
| POST /me/saved-searches | user | `module` (`buy_sell` watches listings, `lost_found` watches found reports), `name`, `q`, `category_id`, `min_price`, `max_price`, `alerts_enabled`; up to 20 each |
| PATCH /me/saved-searches/{id} | owner | Edit, or pause alerts |
| POST /me/saved-searches/{id}/seen | owner | Reset `new_count` |
| DELETE /me/saved-searches/{id} | owner | |

**Lost & Found** (same routes for `/found-reports`)

| Method & path | Who | What |
|---|---|---|
| GET, POST /lost-found/categories | guest / user | Categories name the item (ID card, Water bottle…) |
| GET /lost-reports | guest | Browse. Filters: `category_id`, `status`, `q`, `reporter_id`, `from_date`/`to_date` (when lost or found); `sort` newest / oldest |
| POST /lost-reports | user | File a report. The response lists same-category `possible_matches`. The matcher then compares it by description and photo with open reports of the other kind (any category) and alerts the lost report's owner about a strong match; editing, new photos and reopening match again (each person is told once per found report). Without the matcher, filing a *found* report notifies everyone with an open lost report in that category |
| GET /lost-reports/{id}/matches | reporter, admin | Possible matches, best first: `status` ready / pending / unavailable, each with `score`, `strength` (strong / possible) and `reasons` |
| GET, PATCH, DELETE /lost-reports/{id} | guest / reporter or admin / reporter, Lost & Found moderator or admin | |
| PATCH /lost-reports/{id}/status | reporter, admin | open / closed |
| PUT /lost-reports/{id}/photos | reporter, admin | Replace photos |

**Academic Help**

| Method & path | Who | What |
|---|---|---|
| GET /departments | guest | |
| POST /departments | admin | Add a department |
| PATCH /departments/{id} | admin | Rename |
| DELETE /departments/{id} | admin | Deletes the department and everything in it |
| GET /departments/{id}/courses | guest | With `material_count`, `feedback_count`, `has_content` (FR-11) |
| POST /departments/{id}/courses | admin, department moderator | |
| GET /courses/{id} | guest | |
| PATCH /courses/{id} | admin, department moderator | |
| DELETE /courses/{id} | admin, department moderator | Deletes materials, feedback, forum, threads, comments, course roles and reports |
| GET /courses/{id}/materials | guest | With download URLs |
| POST /courses/{id}/materials | course moderator of that course, department moderator, admin | |
| PATCH, DELETE /materials/{id} | same | |
| GET /courses/{id}/feedback | guest | Names only for signed-in viewers; anonymous feedback never shows one. `is_mine` marks the viewer's own |
| GET /courses/{id}/feedback/mine | user | My review of the course (404 if none) |
| POST /courses/{id}/feedback | user | One review per person per course (409 on a second); `is_anonymous` hides the name |
| PATCH /feedback/{id} | author, department moderator, admin | Edit |
| DELETE /feedback/{id} | author, course moderator of that course, department moderator, admin | Remove |
| GET /courses/{id}/survival-guide | guest | Feedback summary per semester (Aug / Jan, by when it was written) with sentiment, trend, themes, repeated advice and a summary paragraph. Computed on request (`app/sentiment.py`) |

**Forums**

| Method & path | Who | What |
|---|---|---|
| GET /courses/{id}/forum | guest | The course's forum (created on first open) |
| GET /departments/{id}/forum | guest | The department's forum (created on first open) |
| GET /forums/{id}/threads | guest | Threads, newest first |
| POST /forums/{id}/threads | user | Title + opening post |
| GET /threads/{id} | guest | Thread with comments in order |
| PATCH /threads/{id} | author, admin | Rename |
| DELETE /threads/{id} | author, forum moderator, admin | Removes all its comments |
| POST /threads/{id}/comments | user | Reply; notifies the author and other participants |
| PATCH /comments/{id} | author, admin | |
| DELETE /comments/{id} | author, forum moderator, admin | |

**Reports and notifications**

| Method & path | Who | What |
|---|---|---|
| POST /reports | user | Report a listing, Wanted post, lost/found report, material, feedback, thread or comment |
| GET /me/reports | user | Reports I filed |
| GET /reports | moderator, admin | Queue of reports in my scope (default: open; `status=all` for every status) |
| POST /reports/{id}/resolve | moderator in scope | `actioned` (optionally `remove_content`) or `dismissed`; closes all open reports on that item. Removing an item any other way also closes its reports |
| GET /me/notifications | user | Inbox (`unread_only` filter) |
| POST /me/notifications/{id}/read | user | Mark one notification read |
| POST /me/notifications/read-all | user | Mark all read |
| DELETE /me/notifications/{id}, POST /me/notifications/delete, DELETE /me/notifications | user | Delete one, several (`ids`), or all of my notifications |
| POST /me/devices | user | Register a device's push token |
| DELETE /me/devices | user | Unregister it; body `{"push_token": "..."}` (kept out of the URL and access logs) |

**Messages** (one chat per person; topics are the listings and Lost & Found posts discussed)

| Method & path | Who | What |
|---|---|---|
| GET, PUT /me/chat-key; GET /users/{id}/chat-key | user | My messaging key (with its private key, only for me); someone's public key |
| GET, POST /chat/conversations | user | My chats, one per person; open a chat about a `listing_id`, `lost_report_id`, `found_report_id`, or with a `user_id` |
| GET /chat/unread | user | Unread count for the badge |
| GET /chat/conversations/{id}, GET /chat/conversations/{id}/messages | participant | One chat; its encrypted messages (`after=` to sync, `before=` for history) |
| POST /chat/conversations/{id}/messages, POST …/read | participant | Send a message or offer (about a `topic_id`); mark read |
| POST /chat/messages/{id}/offer, DELETE /chat/messages/{id} | participant | Accept (reserves the listing), decline or withdraw an offer; unsend |
| GET /chat/blocks, PUT, DELETE /chat/blocks/{user_id} | user | Blocked people; block or unblock |

**Campus services** (landing page)

| Method & path | Who | What |
|---|---|---|
| GET /campus-services | guest | Health Centre, Wellness Centre, emergency and grievance links, grouped by category |
| POST /campus-services | admin | Add (`url` and/or `phone` required) |
| PATCH, DELETE /campus-services/{id} | admin | Edit, hide (`is_active: false`) or delete |

## Deploying on AWS

What still has to change before a real cloud deployment (temporary dev shortcuts, missing
providers, new migrations) is listed in [docs/cloud-deployment-checklist.md](../docs/cloud-deployment-checklist.md).

- **Lambda:** build `Dockerfile.lambda` for one architecture and without attestations, push it
  to ECR, and create the function from the image (handler `app.main.handler`, the same
  architecture). Put it behind an API Gateway HTTP API.

  ```bash
  docker buildx build --platform linux/arm64 --provenance=false -f Dockerfile.lambda -t campushub-api .
  ```

  - Use `.env.example` as the list of settings: `CAMPUSHUB_AUTH_MODE=cognito` plus the Cognito
    pool and app-client ids, and `CAMPUSHUB_S3_BUCKET`.
  - Point `CAMPUSHUB_DATABASE_URL` at the **RDS Proxy** endpoint without a password, and set
    `CAMPUSHUB_DATABASE_SECRET_ARN` to the database credentials in Secrets Manager. Inside
    Lambda the pool size defaults to 2 (the proxy does the real pooling) and `/docs` is off.
  - Set `CAMPUSHUB_CORS_ALLOW_ORIGINS` to the web app's origin.
  - On Lambda, push lookups and S3 cleanup (background tasks) finish before the response is
    returned, so they add to its latency; pushes are capped at `CAMPUSHUB_PUSH_TIMEOUT_SECONDS`
    (3 s). Keep this in mind when comparing Lambda with EC2, where they run after the response.
- **Matcher:** a separate function from `Dockerfile.matcher` (handler
  `app.matching.handler.handler`; arm64, 1536 MB, 30 s timeout, async retries 2). It holds
  ONNX Runtime and the three models (~305 MB), so the API image stays small and starts fast.

  ```bash
  docker buildx build --platform linux/arm64 --provenance=false -f Dockerfile.matcher -t campushub-matcher .
  ```

  - Give it the same database, S3 and VPC settings as the API. Its role needs `s3:GetObject`
    on the bucket and `secretsmanager:GetSecretValue`.
  - Set `CAMPUSHUB_MATCH_FUNCTION` on the API to the matcher's name, and allow the API role
    `lambda:InvokeFunction` on it. The API then invokes it asynchronously after each change
    (`{"kind", "report_id"}`). A Lambda in private subnets needs a `lambda` interface endpoint
    or NAT for that call.
  - Run `{"backfill": true}` once after migration 012, and optionally every 15 minutes from
    EventBridge to retry anything a failed invocation left pending.
  - Measured locally (one thread): ~7 ms per description and ~40 ms per photo; expect 2–3×
    on Graviton, plus loading the models (~0.3 s) on a cold start.
- **Purge job:** a second function from the same image with handler `app.jobs.purge_handler`,
  run daily by an EventBridge schedule, deletes notifications older than 30 days.
- **Network:** a Lambda in private subnets needs
  - an S3 gateway endpoint, to check uploads;
  - a NAT gateway or a `cognito-idp` interface endpoint, to download Cognito's signing keys
    once per container.
- **IAM:** the function role needs `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`,
  `s3:PutObjectTagging` and `s3:ListBucket` on the bucket (without `ListBucket`, S3 answers
  403 instead of 404 for a missing file), plus `secretsmanager:GetSecretValue` on the
  database secret.
- **S3 lifecycle rule:** expire objects tagged `state=pending` after 1 day, so uploads that
  were never attached to a post are deleted.
- **CloudFront:** set `CAMPUSHUB_CDN_BASE_URL`, `CAMPUSHUB_CDN_KEY_PAIR_ID` and
  `CAMPUSHUB_CDN_PRIVATE_KEY` together. File links then point at CloudFront and are signed
  with that key pair, so they expire like presigned S3 links (the app won't start with only
  the URL). Register the public key in a CloudFront key group that the distribution trusts.
- **EC2 baseline:** build `Dockerfile` (uvicorn) and run it with an `.env` made from
  `.env.example` (never `.env.local.example`).
- **Push notifications:** inbox rows are always written. `app/notify.py` currently only logs
  pushes; replace `LogPushSender` with an SNS or FCM sender to deliver them.

## Not built yet (Phase 2)

Placement Hub (companies, JDs, PPTs, interview experiences, bulk import, hiring stats),
Community Events (tags, follows, bookmarks) and real push delivery. The
database tables already exist in `db/schema.sql`.
