# CampusHub developer guide

What each part of the codebase does, how the parts work together, and how to change them. For installing
and running CampusHub, see [README.md](README.md). For the original requirements, see [PRD.md](PRD.md).

The application code is the same on both submission branches. This guide follows `main` (serverless).
On `baseline-infra-restore` the backend runs on EC2 instead: the infrastructure differences are in
[section 6](#6-infrastructure-terraform), and that branch's README has its deploy steps.

## Table of contents

1. [The codebase at a glance](#1-the-codebase-at-a-glance)
2. [How a request flows](#2-how-a-request-flows)
3. [Backend (`backend/`)](#3-backend-backend)
4. [Database (`backend/db/`)](#4-database-backenddb)
5. [Frontend (`frontend/`)](#5-frontend-frontend)
6. [Infrastructure (`terraform/`)](#6-infrastructure-terraform)
7. [Load testing (`locust_load_testing/`)](#7-load-testing-locust_load_testing)
8. [Tests](#8-tests)
9. [Common tasks](#9-common-tasks)
10. [Conventions](#10-conventions)
11. [Requirements traceability](#11-requirements-traceability)

## 1. The codebase at a glance

| Part | Language / tool | What it is |
|---|---|---|
| `backend/` | Python 3.11+, FastAPI, asyncpg | The whole API: every module, sign-in, permissions, uploads, notifications, ML features |
| `backend/db/` | PostgreSQL 16 | Schema, migrations and reference data |
| `frontend/` | Dart, Flutter (web) | The user interface |
| `terraform/` | Terraform (HCL) | All AWS infrastructure, plus deploy and snapshot scripts |
| `locust_load_testing/` (on `main`) | Python, Locust, Tkinter | Load-test suite and the Lambda-vs-EC2 benchmark results |
| `.github/workflows/` | GitHub Actions | Builds and publishes the web app on pushes to `main` |
| `docs/` | Markdown, PNG/SVG | API reference, schema diagrams, deployment logs, session notes |

The same backend code runs in three places. Only configuration changes, never the code:

| Where | Entry point | Started by |
|---|---|---|
| Your machine | `app.main:app` | `cd backend && uvicorn app.main:app --reload --env-file .env` |
| AWS Lambda (this branch) | `app.main.handler` (Mangum wraps the FastAPI app) | API Gateway |
| EC2 (`baseline-infra-restore`) | `app.main:app` | uvicorn under systemd, behind an ALB |

## 2. How a request flows

Example: a signed-in student opens Buy & Sell, which calls `GET /api/v1/listings?category_id=...`.

```
Flutter web app                          frontend/lib/features/buy_sell/...
  BuySellFeedScreen  ->  buySellRepositoryProvider  ->  ApiBuySellRepository
  -> ApiClient (Dio): adds "Authorization: Bearer <Cognito ID token>"
        |
        v
CloudFront   /api/v1/listings* is an edge-cached path (20 s, key includes Authorization + query)
        |  miss
        v
API Gateway (HTTP API)  route /api/v1/listings/{proxy+}  ->  buy-sell Lambda
        |
        v
app/main.py   handler = Mangum(app)  ->  FastAPI
  router dependency  optional_user (app/auth.py)
      verifies the ID token against Cognito's signing keys, loads or creates the users row
  route function     routers/listings.py  list_listings(...)
      conn = Depends(get_conn)            app/db.py: connection from the asyncpg pool
      cache.get_or_set(key, ...)          app/cache.py: Redis first, key includes the viewer
      raw SQL via asyncpg                 -> RDS PostgreSQL
      Pydantic response model             -> JSON
```

A write (for example `POST /api/v1/listings`) follows the same path, never cached, and usually also:

1. checks permissions in `app/permissions.py` (always read from the database, never from token claims);
2. verifies uploaded photos with `app/storage.py` (the file must exist in S3, be yours, and match type and
   size), then retags them from `state=pending` to `state=attached`;
3. writes notifications with `app/notify.py` (an inbox row per user, plus a push attempt);
4. runs follow-ups such as automatic flagging (`app/screening.py`), saved-search alerts (`app/alerts.py`) or
   Lost & Found matching (`app/matching/trigger.py`).

Database constraint errors are turned into clear HTTP 4xx responses by `app/errors.py`.

## 3. Backend (`backend/`)

### 3.1 Core modules (`backend/app/`)

| File | Responsibility |
|---|---|
| `main.py` | Builds the FastAPI app: CORS, error handlers, routers under `/api/v1`, Swagger sign-in button, the Lambda `handler`. Refuses to start with dev sign-in inside Lambda |
| `config.py` | All settings, from environment variables prefixed `CAMPUSHUB_` (or `.env`). Picks Lambda-specific defaults (pool size 2, `/docs` off) |
| `auth.py` | Who is calling: verifies Cognito ID tokens (signature, expiry, issuer, audience, `email_verified`), or the `X-Dev-User` header in local dev mode. Creates the user's row on first sign-in and relinks a re-created Cognito account by email |
| `permissions.py` | Role checks for PRD §3.1: admin, module moderators, department and course moderators (Academic Help), forum moderators; writes the moderation log |
| `db.py` | The asyncpg connection pool, created on first use and recreated if the event loop changes (Lambda). Reads the database password from Secrets Manager |
| `cache.py` | Redis cache-aside for list endpoints. No-op without `CAMPUSHUB_REDIS_HOST`; any Redis error counts as a miss |
| `storage.py` | S3: presigned upload URLs (with signed size and SHA-256 checksum, NFR-8), upload verification, `pending` / `attached` tags, download links (optionally signed CloudFront URLs) |
| `notify.py` | Notifications: inbox rows plus push through a `PushSender`: `WebPushSender` to browsers when a VAPID key is set up, else `LogPushSender` |
| `webpush.py` | Web Push encryption (RFC 8291) and VAPID signing; also the push-sender Lambda's handler |
| `errors.py` | Maps PostgreSQL constraint violations to HTTP responses |
| `common.py` | Pagination (`Page`, `page_params`), shared reference models, text types, PATCH helper (`set_clause`), `not_found` / `forbidden` |
| `cognito_accounts.py` | Checks that a person's Cognito account still exists and is enabled (moderator grants). If the check cannot be made, it logs and allows |
| `otp.py` | Email and phone codes for dev sign-in and phone verification |
| `jobs.py` | Scheduled jobs: notification purge, meal alerts |
| `alerts.py` | Saved-search and Wanted-post alerts for new items |
| `screening.py` | Automatic flagging of new posts: keywords, gibberish, spam, category model, obscene-photo check |
| `seller_trust.py` | Seller strikes and the "Negative Seller" / "Blocked Seller" tags, driven only by moderator-confirmed removals |
| `categories_suggest.py` | Suggests a Buy & Sell / Lost & Found category from a title (ONNX model; returns nothing if the model is absent) |
| `company_matching.py` | Finds companies that are probably the same under different names (for merging) |
| `placement_sheet.py`, `placement_csv.py`, `placement_roles.py` | Parsers for the Placement Hub bulk imports (FR-17): placement sheets, company lists and schedules, roles and compensation. Malformed rows are reported, never dropped |
| `material_check.py` | Checks files uploaded to a course's materials before others can see them |
| `mess_extract.py`, `mess_alerts.py` | Reading a mess menu from a PDF or photo (Tesseract OCR); meal alerts to mess followers |
| `course_updates.py` | Tells a course's followers about new materials, feedback and forum posts |
| `sentiment.py`, `sentiment_backends.py` | Sentence sentiment and themes for course feedback: local model, word list, or Amazon Comprehend (one setting) |
| `lf_kinds.py` | Lost and found reports share one shape; this names the table and columns for each |

### 3.2 Routers (`backend/app/routers/`)

Each file is one module of the API. All are mounted under `/api/v1`, and every route runs `optional_user`, so a
bad or expired token always gets 401, even on pages guests can read.

| File | Module | PRD |
|---|---|---|
| `users.py` | Health check, my profile, phone verification, public profiles, admin account controls (deactivate, hand over admin) | FR-1 |
| `moderators.py` | Grant and revoke moderator roles, scoped to a module, department or course | FR-3 |
| `listings.py` | Buy & Sell listings: create, status (Available/Reserved/Sold), search and filter, price watch, removal | FR-4, FR-5, FR-6, FR-10 |
| `wanted.py` | Wanted posts (what buyers are looking for) | extension |
| `seller_trust.py` | Seller strikes, appeals, suspensions and unblock requests | extension |
| `categories.py` | Buy & Sell and Lost & Found categories: add, delete or merge | FR-4, FR-7 |
| `lost_found.py` | Lost and found reports, and their matches | FR-7, FR-8, FR-9, FR-10 |
| `academic.py` | Departments, courses, materials, feedback, course follows | FR-11, FR-12, FR-13 |
| `survival_guide.py` | One-page summary of a course's feedback with sentiment over time | extension |
| `forums.py` | Forums, threads and comments with votes (course, department, company) | FR-14 |
| `placement.py` | Companies, job descriptions, pre-placement talks, hiring statistics, interview experiences, seniors, bulk imports | FR-15, FR-16, FR-17 |
| `events.py` | Events, tags, Past/Present/Upcoming, bookmarks, followed tags, event updates | FR-18, FR-19, FR-20 |
| `mess.py` | Mess menus and meal alerts | extension |
| `campus_services.py` | Health Centre, Wellness Centre and other links for the landing page | FR-21 |
| `notifications.py` | My notifications inbox and push devices | FR-9, FR-22 |
| `saved_searches.py` | Saved searches and their alerts | extension |
| `reports.py` | Reporting content, and the moderators' review queue | FR-10 |
| `chat.py` | One-to-one messaging (one chat per person, offers that reserve a listing), encrypted with server-held keys | FR-23 |
| `my_posts.py` | "My postings" on my profile | – |
| `uploads.py` | Upload tickets (presigned S3 URLs) | FR-4, NFR-8 |
| `auth_otp.py` | Email sign-in codes for local dev mode only (404 in Cognito mode) | – |

The full list of endpoints, with fields, is in [docs/api-reference.md](docs/api-reference.md).

### 3.3 Lost & Found matching (`backend/app/matching/`)

| File | Does |
|---|---|
| `engine.py` | Scores lost/found pairs by description and photo, stores likely matches, alerts owners |
| `models.py` | The three small ONNX embedding models |
| `trigger.py` | Starts matching after a report changes: `inline`, through a separate Lambda (`lambda`), or `off` (setting `CAMPUSHUB_MATCH_MODE`) |
| `handler.py` | Entry point of the optional matcher Lambda (`Dockerfile.matcher`); not deployed by this Terraform |
| `nsfw.py`, `photo_screen.py` | Obscene-photo check used by automatic flagging |
| `__main__.py` | `python -m app.matching --backfill` |

Without the models (the Lambda zip leaves them out), matching falls back to the same-category rule.

### 3.4 Other backend folders and files

| Path | What it is |
|---|---|
| `lambdas/cognito_pre_signup.py` | Cognito *Pre sign-up* trigger: only `iisc.ac.in` emails (FR-1). Attach to the user pool by hand |
| `scripts/seed_dummy_data.py` | Realistic demo data (students, courses, listings, events, chats, ...) |
| `scripts/fetch_match_models.py` | Downloads the ONNX models (`--suggest-only` for just the category model) |
| `scripts/calibrate_*.py`, `scripts/eval_*.py`, `scripts/generate_*_eval_data.py` | Threshold calibration and accuracy evaluation for the ML features |
| `scripts/diagnose_cloud_deploy.sh/.sql` | Checks a cloud deployment's configuration and database |
| `requirements.txt` | Everything, including the ML and OCR packages (local runs, EC2) |
| `requirements-lambda-zip.txt` | Trimmed copy for the Lambda zip (stays under 250 MB). Keep shared pins in sync |
| `requirements-matching.txt`, `requirements-dev.txt` | Matching models; test tools |
| `Dockerfile`, `Dockerfile.lambda`, `Dockerfile.matcher` | Container images for other deployment paths; the Terraform here does not use them |
| `docker-compose.yml` | Local PostgreSQL and MinIO |

## 4. Database (`backend/db/`)

| File | Purpose |
|---|---|
| `schema.sql` | The complete schema at the latest revision: 57 tables and 19 enum types. Loaded on a brand-new database |
| `migrations/0NN_*.sql` | One file per revision (`006` to `027`), to upgrade an existing database in order |
| `reference-data.sql` | Real starting data (campus services, default event tags). Safe to run twice |
| `init-test-db.sql` | Creates the `campushub_test` database used by pytest |

Main table groups (diagrams per module in [docs/schema/](docs/schema/README.md)):

| Area | Tables |
|---|---|
| Identity and roles | `users`, `moderator_assignments`, `moderation_log`, `push_devices` |
| Buy & Sell | `listings`, `listing_photos`, `bs_categories`, `wanted_posts`, `listing_watches`, `listing_bookmarks`, `saved_searches`, `seller_strikes`, `seller_unblock_requests` |
| Lost & Found | `lost_reports`, `found_reports`, their `_photos`, `lf_categories`, `lf_embeddings`, `lf_matches` |
| Academic Help | `departments`, `courses`, `course_materials`, `course_feedback`, `course_follows` |
| Placement Hub | `companies`, `job_descriptions`, `ppt_info`, `interview_experiences`, `placement_records`, `placement_bulk_imports`, `company_seniors` |
| Forums | `forums`, `threads`, `comments`, `thread_votes`, `comment_votes` |
| Events and mess | `events`, `event_tags`, `event_tag_map`, `event_updates`, `tag_follows`, `messes`, `mess_menus`, `mess_menu_items`, `mess_follows`, `mess_alerts_sent` |
| Cross-module | `bookmarks`, `notifications`, `reports`, `campus_services` |
| Messaging | `chat_keys`, `chat_conversations`, `chat_topics`, `chat_messages`, `chat_message_hides`, `chat_blocks` |

Rules the schema enforces itself: IISc-only emails (`iisc_email` domain), exactly one admin
(`uq_users_single_admin`), status enums, and foreign keys with explicit `ON DELETE` behaviour.

## 5. Frontend (`frontend/`)

Why the frontend is structured this way (feature-first folders, Riverpod, go_router, and the alternatives
considered for each): [docs/frontend-design-decisions.md](docs/frontend-design-decisions.md).

### 5.1 Layout

```
lib/
├── main.dart          Starts the app: path URLs, Riverpod ProviderScope, theme, router, session keeper
├── core/              Shared by every feature
│   ├── api/           ApiClient (Dio): base URL, auth header, dev headers, 401 -> refresh -> retry once
│   ├── config/        ServerConfig: API URL, mock mode and dev key, changeable at run time by the admin
│   ├── constants/     AppConfig: compile-time --dart-define values (USE_MOCK, API_BASE_URL, COGNITO_*)
│   ├── router/        go_router routes (/, /buy-sell, /lost-found, /courses/:id, /placements/:id, /events/:id, /mess, /messages, /profile, ...)
│   ├── storage/       Token storage (shared_preferences)
│   ├── services/      Upload service: asks for a ticket, PUTs the file to S3 with the checksum
│   ├── models/, enums/, theme/, widgets/, utils/
└── features/          One folder per module
```

### 5.2 How a feature is built

Every feature folder (`buy_sell`, `lost_found`, `academics`, `placement`, `events`, `mess`, `messages`,
`forums`, `wanted`, `alerts`, `seller_trust`, `campus_services`, `profile`, `admin`, `auth`) has the same four
layers:

| Layer | Example (`features/buy_sell/`) | Role |
|---|---|---|
| `domain/` | `buy_sell_item.dart` | Plain Dart models used by the UI |
| `data/` | `buy_sell_repository.dart` (interface), `api_buy_sell_repository.dart`, `mock_buy_sell_repository.dart`, `buy_sell_dto.dart` | Talks to the API, or serves mock data |
| `providers/` | `buy_sell_providers.dart` | Riverpod providers; picks the API or mock repository from `ServerConfig.useMockData` |
| `ui/` | `buy_sell_feed_screen.dart`, `ui/widgets/...` | Screens and widgets |

The mock repositories let the whole UI run without a backend (`USE_MOCK=true`, the default).

### 5.3 Sign-in

`features/auth/data/cognito_hosted_ui.dart` runs the Cognito Hosted UI code flow with PKCE and stores the ID,
access and refresh tokens. `ApiClient.onUnauthorized` refreshes the ID token on a 401 and retries the
request once. `features/auth/ui/session_keeper` keeps the session in step with the stored tokens. Without
Cognito flags, the app uses the backend's dev sign-in.

## 6. Infrastructure (`terraform/`)

| Module | Serverless (`main`) | EC2 baseline (`baseline-infra-restore`) |
|---|---|---|
| `networking` | VPC, private Lambda and database subnets, security groups, VPC endpoints | Also public subnets and internet gateway for the ALB |
| `database` | RDS PostgreSQL, password in Secrets Manager, optional RDS Proxy | same |
| `elasticache` | Redis for `app/cache.py` | same |
| `storage` | Frontend and media S3 buckets | same, plus `backend.zip` for the instances |
| `auth` | Cognito user pool, app client, Hosted UI, groups | same |
| `compute` | Builds the Lambda zip (`build_lambda_zip.sh`), 5 functions, warmer | – |
| `api_gateway` | HTTP API routes to the 5 functions | – |
| `compute_ec2` | – | ALB, launch template, user data, Auto Scaling group and policies |
| `cdn` | CloudFront: S3 site, API origin, SPA rewrite, API cache policy | same, with the ALB as API origin |
| `waf`, `monitoring`, `data_tools` | Optional WAF; alarms, budget and SNS; snapshot/migration Lambda | same |

The five Lambdas run the same zip; API Gateway routes by path prefix (for example `/api/v1/listings*` to
`buy-sell`) so each module has its own metrics and memory setting. Module, variable and output reference:
[terraform/README.md](terraform/README.md).

Helper scripts in `terraform/scripts/`: `deploy_frontend.sh`, `snapshot_export.sh`, `snapshot_restore.sh`,
`deactivate_missing_cognito_users.sh`, `create_vapid_keys.sh`.

## 7. Load testing (`locust_load_testing/`)

On `main` only. A desktop app that generates and runs Locust tests against either stack.

| File | Does |
|---|---|
| `locust-automated/app.py` | Tkinter GUI: target, token, endpoints, users, spawn rate, duration |
| `locust-automated/catalog.py` | Catalogue of 65 endpoints across 10 modules, with read/write class and weights |
| `locust-automated/generator.py` | Writes a locustfile for the chosen endpoints and weights |
| `locust-automated/runner.py` | Runs Locust in distributed mode (`--processes -1`) and cleans up workers |
| `locust-automated/collector.py` | Polls live stats, downloads the HTML report |
| `locust-automated/chart_generator.py` | Throughput, latency and user charts (Matplotlib) |
| `locust-automated/auth_utils.py` | Decodes and checks the Cognito token |
| `locust-automated/presets.py`, `custom_presets/*.json` | Saved endpoint mixes, such as `acad_placement_preset` |
| `output/` | One folder per run, and `BENCHMARK_SUMMARY.md` |

Results and analysis: [README section 9](README.md#9-performance-and-metrics).

## 8. Tests

| Suite | Command | Notes |
|---|---|---|
| Backend | `cd backend && pytest` | More than 200 tests against the real Postgres from docker compose (database `campushub_test`) and mocked S3. `conftest.py` empties every table between tests; `as_user(email)` builds dev sign-in headers |
| ML accuracy | `pytest tests/test_category_suggest_accuracy.py tests/test_auto_flag_accuracy.py` | Skipped unless the models are downloaded (`scripts/fetch_match_models.py`) |
| Frontend | `cd frontend && flutter test` | `live_backend_integration_test.dart` needs a running backend |
| Load | `locust_load_testing/locust-automated/start.sh` | See section 7 |

Test files are named after the module or fix they cover (`test_listings.py`, `test_placement_hub.py`,
`test_review_fixes.py`, ...).

## 9. Common tasks

### Add an API endpoint

1. Add the route to the module's file in `backend/app/routers/` (or a new file, then add it to the router
   list in `app/main.py`).
2. Take `conn: asyncpg.Connection = Depends(get_conn)` and `user = Depends(current_user)` (or
   `optional_user` for guest access). Check permissions with `app/permissions.py`.
3. Write the SQL directly with asyncpg; declare Pydantic request and response models.
4. If the route needs its own Lambda routing, add its prefix in `terraform/modules/api_gateway`; otherwise
   the catch-all route sends it to `community-events`. If it is a cacheable list, add it to
   `cacheable_api_path_patterns` in `terraform/modules/cdn` and use `cache.get_or_set` with a viewer-aware key.
5. Add tests in `backend/tests/` and update `docs/api-reference.md`.

### Change the database

1. Write `backend/db/migrations/0NN_short_name.sql` (next number, wrapped in `BEGIN`/`COMMIT`, using
   `IF NOT EXISTS` where possible).
2. Apply the same change to `backend/db/schema.sql` and bump its revision comment.
3. Locally (from backend/): `docker exec -i campushub-db-1 psql -U campushub -d campushub < db/migrations/0NN_short_name.sql`.
   On AWS: the data-tools Lambda's `migrate` action ([README step 5.7](README.md#57-load-the-database)).

### Add a frontend screen

1. Add the model to `domain/`, the repository interface plus API and mock implementations to `data/`, a
   provider to `providers/`, and the screen to `ui/`.
2. Add the route in `core/router/app_router.dart` and the endpoint path in `core/api/api_endpoints.dart`.

### Deploy a change

| Changed | Run |
|---|---|
| Backend code or `requirements-lambda-zip.txt` | `cd terraform && terraform apply` (rebuilds and redeploys the Lambda zip) |
| Frontend | `cd terraform && ./scripts/deploy_frontend.sh` |
| Database | A new migration, applied as above |
| Infrastructure | `terraform plan`, then `terraform apply` |

## 10. Conventions

- **No ORM.** SQL is written by hand with asyncpg, with numbered parameters (`$1`), never string
  formatting of values.
- **Permissions come from the database.** Roles are not taken from Cognito groups, so a revoked moderator
  loses access on their next request (FR-3).
- **Every route checks the token.** Guests send no token; an invalid one is always rejected.
- **Optional features fail soft.** Missing ML models, Tesseract, Redis or Comprehend turn a feature off
  instead of crashing the app (`importlib.util.find_spec` checks, cache misses).
- **Secrets stay in Secrets Manager.** Environment variables carry only secret ARNs.
- **Uploads go straight to S3** through presigned URLs with a signed checksum; the API only verifies them.
- **Soft deletion and an audit trail** for moderation (`moderation_log`).
- **Settings** are `CAMPUSHUB_*` environment variables, documented in
  [backend/README.md](backend/README.md#configuration).

## 11. Requirements traceability

Where each PRD functional requirement lives in the code:

| PRD | Backend | Frontend feature |
|---|---|---|
| FR-1 IISc-only sign-in | `auth.py`, `lambdas/cognito_pre_signup.py`, `iisc_email` domain | `auth` |
| FR-2, FR-3 roles and moderator grants | `permissions.py`, `routers/moderators.py` | `admin` |
| FR-4 to FR-6, FR-10 Buy & Sell | `routers/listings.py`, `routers/categories.py` | `buy_sell` |
| FR-7 to FR-9 Lost & Found | `routers/lost_found.py`, `matching/` | `lost_found` |
| FR-11 to FR-13 Academic Help | `routers/academic.py` | `academics` |
| FR-14 forums | `routers/forums.py` | `forums` |
| FR-15 to FR-17 Placement Hub | `routers/placement.py`, `placement_*.py` | `placement` |
| FR-18 to FR-20 events | `routers/events.py` | `events` |
| FR-21 landing page | `routers/campus_services.py` and the module feeds | `campus_services` |
| FR-22 notifications | `notify.py`, `routers/notifications.py` | `alerts` |
| FR-23 chat | `routers/chat.py` | `messages` |
| NFR-8 upload integrity | `storage.py` (signed SHA-256 checksum) | `core/services/upload_service.dart` |

Features beyond the PRD (Wanted posts, seller trust, saved searches, mess menus, course survival guide,
automatic flagging, category suggestion) are listed in the `docs/session-notes-*.md` files.
