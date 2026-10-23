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
cp .env.example .env                    # dev auth, local MinIO
python scripts/create_local_bucket.py
uvicorn app.main:app --reload --env-file .env   # http://localhost:8000/docs
```

`--env-file` also exports the MinIO keys in `.env` (`AWS_ACCESS_KEY_ID`…) to boto3. Without it,
boto3 signs uploads with your own `~/.aws/credentials`, and MinIO rejects them.

In dev mode you act as any IISc user by sending a header; the user is created on their first request:

```bash
curl -H "X-Dev-User: asha@iisc.ac.in" -H "X-Dev-Name: Asha" http://localhost:8000/api/v1/me
```

To make someone the first admin (after they've made one request):

```bash
docker compose exec db psql -U campushub -c "UPDATE users SET base_role = 'admin' WHERE email = 'asha@iisc.ac.in';"
```

## Tests

```bash
pytest
```

The tests use the real Postgres from docker-compose (database `campushub_test`; set
`CAMPUSHUB_TEST_DATABASE_URL` to use another) and a mocked S3. They cover the PRD
acceptance criteria that the backend owns, including:

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
  The API checks its signature, expiry, issuer and audience, then creates the user's row on
  their first request.
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
   type or checksum doesn't match (NFR-8).
3. Send the `s3_key` when creating or editing the post, using `photo_keys` or `s3_key`.
   The API checks that the file is yours and really uploaded, and that its size and type
   are allowed.

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
| PATCH /listings/{id} | seller | Edit fields |
| PATCH /listings/{id}/status | seller | available / reserved / sold |
| PUT /listings/{id}/photos | seller | Replace, reorder or remove photos |
| DELETE /listings/{id} | seller, Buy & Sell moderator, admin | Soft delete; moderator removals are logged |

**Lost & Found** (same routes for `/found-reports`)

| Method & path | Who | What |
|---|---|---|
| GET, POST /lost-found/categories | guest / user | Categories name the item (ID card, Water bottle…) |
| GET /lost-reports | guest | Browse. Filters: `category_id`, `status`, `q`, `reporter_id` |
| POST /lost-reports | user | File a report. The response lists `possible_matches`. Filing a *found* report notifies everyone with an open lost report in that category |
| GET, PATCH, DELETE /lost-reports/{id} | guest / reporter / reporter or Lost & Found moderator | |
| PATCH /lost-reports/{id}/status | reporter | open / matched / closed |
| PUT /lost-reports/{id}/photos | reporter | Replace photos |

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
| PATCH, DELETE /feedback/{id} | author, department moderator, admin | |

**Forums**

| Method & path | Who | What |
|---|---|---|
| GET /courses/{id}/forum | guest | The course's forum (created on first open) |
| GET /departments/{id}/forum | guest | The department's forum (created on first open) |
| GET /forums/{id}/threads | guest | Threads, newest first |
| POST /forums/{id}/threads | user | Title + opening post |
| GET /threads/{id} | guest | Thread with comments in order |
| PATCH /threads/{id} | author | Rename |
| DELETE /threads/{id} | author, forum moderator, admin | Removes all its comments |
| POST /threads/{id}/comments | user | Reply; notifies the author and other participants |
| PATCH /comments/{id} | author | |
| DELETE /comments/{id} | author, forum moderator, admin | |

**Reports and notifications**

| Method & path | Who | What |
|---|---|---|
| POST /reports | user | Report a listing, lost/found report, material, feedback, thread or comment |
| GET /me/reports | user | Reports I filed |
| GET /reports | moderator, admin | Queue of reports in my scope (default: open) |
| POST /reports/{id}/resolve | moderator in scope | `actioned` (optionally `remove_content`) or `dismissed`; closes all open reports on that item |
| GET /me/notifications | user | Inbox (`unread_only` filter) |
| POST /me/notifications/{id}/read | user | Mark one notification read |
| POST /me/notifications/read-all | user | Mark all read |
| POST /me/devices | user | Register a device's push token |
| DELETE /me/devices?push_token= | user | Unregister it |

## Deploying on AWS

- **Lambda:** build `Dockerfile.lambda`, push to ECR, and create the function from the image
  (handler `app.main.handler`). Put it behind an API Gateway HTTP API.
  - Set `CAMPUSHUB_AUTH_MODE=cognito` plus the Cognito pool and app-client ids, and
    `CAMPUSHUB_S3_BUCKET`.
  - Point `CAMPUSHUB_DATABASE_URL` at the **RDS Proxy** endpoint and keep
    `CAMPUSHUB_DB_POOL_MAX_SIZE=2`; the proxy does the real pooling.
- **Network:** a Lambda in private subnets needs
  - an S3 gateway endpoint, to check uploads;
  - a NAT gateway or a `cognito-idp` interface endpoint, to download Cognito's signing keys
    once per container.
- **IAM:** the function role needs `s3:PutObject`, `s3:GetObject` and `s3:DeleteObject` on
  the bucket.
- **CloudFront:** set `CAMPUSHUB_CDN_BASE_URL` so photo and file URLs point at CloudFront
  instead of presigned S3 links.
- **EC2 baseline:** build `Dockerfile` (uvicorn) and run it with the same environment variables.
- **Push notifications:** inbox rows are always written. `app/notify.py` currently only logs
  pushes; replace `LogPushSender` with an SNS or FCM sender to deliver them.

## Not built yet (Phase 2)

Placement Hub (companies, JDs, PPTs, interview experiences, bulk import, hiring stats),
Community Events (tags, follows, bookmarks), real push delivery, and 1-to-1 chat. The
database tables already exist in `db/schema.sql`.
