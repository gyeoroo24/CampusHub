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
| GET, PATCH /me | user | My profile, admin flag and active moderator roles; update profile (phone is optional) |
| GET /users/{id} | guest | Public profile; email and phone only for signed-in viewers |
| PATCH /users/{id} | admin | Deactivate or reactivate an account (`is_active`); not your own |
| POST /users/{id}/make-admin | admin | Hand the admin role over: there is exactly one admin, so the caller becomes a signed-in user |
| POST /moderators | admin; department moderator for their courses | Grant a moderator role by email |
| DELETE /moderators/{id} | same | Revoke a role |
| GET /moderators | admin, department moderator | List roles |
| POST /uploads | user | Get a presigned upload URL |

**Buy & Sell**

| Method & path | Who | What |
|---|---|---|
| GET, POST /buy-sell/categories | guest / user | List; add or get the existing category with that name |
| GET /listings | guest | Browse. Filters: `q`, `category_id`, `min_price`, `max_price`, `status`, `seller_id` |
| POST /listings | user | Create, with up to 10 `photo_keys` |
| GET /listings/{id} | guest | Detail with photos; seller contact for signed-in users |
| PATCH /listings/{id} | seller, admin | Edit fields; admin edits are logged |
| PATCH /listings/{id}/status | seller, admin | available / reserved / sold |
| PUT /listings/{id}/photos | seller, admin | Replace, reorder or remove photos |
| DELETE /listings/{id} | seller, Buy & Sell moderator, admin | Soft delete; moderator removals are logged |

**Lost & Found** (same routes for `/found-reports`)

| Method & path | Who | What |
|---|---|---|
| GET, POST /lost-found/categories | guest / user | Categories name the item (ID card, Water bottle…) |
| GET /lost-reports | guest | Browse. Filters: `category_id`, `status`, `q`, `reporter_id` |
| POST /lost-reports | user | File a report. The response lists `possible_matches`. Filing a *found* report notifies everyone with an open lost report in that category; so does changing a found report's category or time, or reopening it (each person is told once) |
| GET, PATCH, DELETE /lost-reports/{id} | guest / reporter or admin / reporter, Lost & Found moderator or admin | |
| PATCH /lost-reports/{id}/status | reporter, admin | open / matched / closed |
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
| GET /courses/{id}/feedback | guest | |
| POST /courses/{id}/feedback | user | |
| PATCH /feedback/{id} | author, department moderator, admin | Edit |
| DELETE /feedback/{id} | author, course moderator of that course, department moderator, admin | Remove |

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
| POST /reports | user | Report a listing, lost/found report, material, feedback, thread or comment |
| GET /me/reports | user | Reports I filed |
| GET /reports | moderator, admin | Queue of reports in my scope (default: open) |
| POST /reports/{id}/resolve | moderator in scope | `actioned` (optionally `remove_content`) or `dismissed`; closes all open reports on that item. Removing an item any other way also closes its reports |
| GET /me/notifications | user | Inbox (`unread_only` filter) |
| POST /me/notifications/{id}/read | user | Mark one notification read |
| POST /me/notifications/read-all | user | Mark all read |
| POST /me/devices | user | Register a device's push token |
| DELETE /me/devices | user | Unregister it; body `{"push_token": "..."}` (kept out of the URL and access logs) |

## Deploying on AWS

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
Community Events (tags, follows, bookmarks), real push delivery, and 1-to-1 chat. The
database tables already exist in `db/schema.sql`.
