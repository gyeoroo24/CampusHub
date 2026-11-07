# CampusHub

CampusHub is one web app for IISc students: Buy & Sell, Lost & Found, Academic Help, Placement Hub,
Community Events, mess menus and forums. It is the group project of team **Order of Phoenix** for
**DS252 Introduction to Cloud Computing** (IISc).

The same FastAPI backend and Flutter web app are deployed on AWS in two ways, so that the two can be
compared (PRD section 7):

- **Serverless** (this branch): CloudFront → API Gateway → AWS Lambda.
- **Baseline** (`baseline-infra-restore`): CloudFront → Application Load Balancer → EC2 Auto Scaling group.

Both use PostgreSQL on RDS, ElastiCache Redis, S3 and Cognito.

| Document | For |
|---|---|
| **README.md** (this file) | Installing, deploying and using CampusHub |
| [PRD.md](PRD.md) | The original project requirements (the plan) |
| [DEV.md](DEV.md) | Developers: what each part of the codebase does and how to change it |

## Table of contents

1. [Branches](#1-branches)
2. [Serverless architecture (this branch)](#2-serverless-architecture-this-branch)
3. [Serverless vs EC2 baseline](#3-serverless-vs-ec2-baseline)
4. [Repository layout](#4-repository-layout)
5. [Deploy to AWS](#5-deploy-to-aws)
6. [Deploy locally](#6-deploy-locally)
7. [Using CampusHub](#7-using-campushub)
8. [Tests](#8-tests)
9. [Performance and metrics](#9-performance-and-metrics)
10. [Cost](#10-cost)
11. [Tear down](#11-tear-down)
12. [Documentation index](#12-documentation-index)
13. [Troubleshooting](#13-troubleshooting)
14. [Team](#14-team)

## 1. Branches

The submission uses two branches. Each has its own copy of this README, with the deploy steps for its
own architecture.

| Branch | Deploys | Compute | Terraform `environment` | State key |
|---|---|---|---|---|
| **`fix/cloud-deploy-zip-and-routes`** (this branch, planned `main`) | Serverless | 5 AWS Lambda functions (Python 3.11, zip package) behind API Gateway HTTP API | `dev` | `campushub/dev/terraform.tfstate` |
| [`baseline-infra-restore`](https://github.com/gyeoroo24/CampusHub/tree/baseline-infra-restore) | EC2 baseline | EC2 Auto Scaling group (Amazon Linux 2023, `t4g.micro`) behind an Application Load Balancer | `baseline` | `campushub/baseline/terraform.tfstate` |

The application code (`backend/`, `frontend/`) is nearly the same on both branches. The differences are
listed in [section 3](#3-serverless-vs-ec2-baseline). Every AWS resource name includes the
`environment`, so both stacks can run side by side in one AWS account.

## 2. Serverless architecture (this branch)

```
                         Users (browser)
                               |
                               v
              +----------------------------------+
              |  Amazon CloudFront               |   HTTPS, *.cloudfront.net certificate
              |  - /*        -> S3 (Flutter web) |   SPA rewrite function for deep links
              |  - /api/v1/<list pages> cached   |   20 s default / 60 s max edge cache
              |  - /api/*    -> API Gateway      |   everything else, uncached
              +----------------+-----------------+
                 |                         |
                 v                         v
     +-------------------+     +-------------------------+      +----------------------+
     | S3 frontend bucket|     | API Gateway (HTTP API)  |      | Cognito user pool    |
     | (Origin Access    |     | per-prefix routes to    |      | Hosted UI, PKCE,     |
     |  Control)         |     | 5 Lambda integrations   |      | 4 groups             |
     +-------------------+     +------------+------------+      +----------------------+
                                            |
   +----------------------------------------|---------------------------------------------+
   | VPC 10.0.0.0/16, private subnets in ap-south-1a / 1b / 1c (no NAT, no internet route) |
   |                                        v                                              |
   |   +----------------------------------------------------------------------------+     |
   |   | Lambda: buy-sell | lost-found | placement-hub | academic-hub | community-events|   |
   |   | (all run the same FastAPI app via Mangum; warmed every 5 min by EventBridge)   |   |
   |   +---------+----------------------+---------------------+------------------------+   |
   |             |                      |                     |                            |
   |             v                      v                     v                            |
   |   +------------------+   +-------------------+   +--------------------------------+  |
   |   | ElastiCache Redis|   | RDS PostgreSQL 16 |   | VPC endpoints                  |  |
   |   | cache.t3.micro   |   | db.t4g.micro      |   | S3 (gateway, free)             |  |
   |   | TLS + AUTH token |   | Multi-AZ optional |   | Secrets Manager, Cognito, SSM, |  |
   |   +------------------+   +-------------------+   | KMS (interface)                |  |
   |                                                   +--------------------------------+  |
   |   data-tools Lambda (pg_dump / pg_restore / psql) for snapshots and migrations        |
   +---------------------------------------------------------------------------------------+
        S3 media bucket (uploads, presigned URLs)   CloudWatch alarms, SNS email, AWS Budgets
```

**Request path and caching.** A read-heavy GET (for example `/api/v1/listings`) is served in up to three
ways:

1. **CloudFront edge cache.** 11 list/browse paths (`listings`, `lost-reports`, `found-reports`, `wanted`,
   `events`, `event-tags`, `departments`, `courses`, `messes`, `companies`, `placement/stats`) are cached
   for 20 s (60 s max). The cache key includes the `Authorization` header and the query string, so two
   users never share a response. Writes are never cached.
2. **ElastiCache Redis** (`backend/app/cache.py`). On a CloudFront miss, the Lambda checks Redis before
   querying Postgres, for 7 of those paths (`listings`, `lost-reports`, `found-reports`, `events`,
   `departments`, `courses`, `messes`). If Redis is down, the app serves the request uncached; it never fails because of
   Redis.
3. **RDS PostgreSQL**, the system of record.

**Secrets.** Lambda environment variables hold only Secrets Manager ARNs. The database password and the
Redis AUTH token are read from Secrets Manager when a container starts.

## 3. Serverless vs EC2 baseline

| | Serverless (this branch) | EC2 baseline (`baseline-infra-restore`) |
|---|---|---|
| API entry point | API Gateway HTTP API | Application Load Balancer (port 80, `X-Origin-Verify` header from CloudFront) |
| Compute | 5 Lambda functions, 512 MB (community-events 1024 MB), 29 s timeout | Auto Scaling group: min 3, desired 3, max 5; scales on 60 % CPU or 200 requests per instance |
| Packaging | `build_lambda_zip.sh` builds a zip at `terraform apply` | `backend.zip` uploaded to S3; user data installs it and runs uvicorn under systemd |
| Scaling | Per request, automatic | New instance in a few minutes when CPU passes the target |
| DB connections | 2 per Lambda container (RDS Proxy optional) | Pool of 16 per uvicorn worker, 2 workers per instance |
| Idle cost | Lambda/API Gateway: near zero | Instance and ALB billed every hour |
| Schema on a new database | Load it yourself (restore or `migrate` action) | User data creates it at first boot |
| Frontend token refresh | Refreshes the Cognito ID token on a 401 and retries | Not included; users are signed out when the token expires (about 1 hour) |
| Measured at 101 users ([section 8](#9-performance-and-metrics)) | p50 53 ms, p99 140 ms, 0 % errors | p50 110 ms, p99 160 ms, 0 % errors |
| Measured at 501 users | 84 % errors (database connections exhausted by 399 concurrent Lambdas) | 7 % errors, p99 47 s (requests queue) |

The design rationale for the baseline is in `Baseline-Architecture.md` on the `baseline-infra-restore`
branch.

## 4. Repository layout

```
.github/workflows/deploy-frontend.yml   Builds the Flutter web app and publishes it to S3 + CloudFront
backend/      FastAPI application, tests, SQL schema and migrations        -> backend/README.md
frontend/     Flutter web app                                              -> frontend/README.md
terraform/    All AWS infrastructure, helper scripts, smoke tests         -> terraform/README.md
docs/         PRD, API reference, schema diagrams, deployment logs, session notes
PRD.md        The original project requirements, in Markdown
DEV.md        Developer guide: what each part of the codebase does
locust_load_testing/   (on main) Locust load-test suite and benchmark results
Cloud_Computing_Project-PRD.pdf        Product requirements
Proposal-Serverless-Architecture.jpg   The serverless design this branch implements
Baseline-Architecture.jpg              The EC2 baseline design
```

## 5. Deploy to AWS

These are the steps used for the deployment on 6 November 2026, in `ap-south-1`. Module and variable
detail is in [terraform/README.md](terraform/README.md). If a step fails, see
[Troubleshooting](#13-troubleshooting).

### 5.1 Prerequisites

| Tool | Why |
|---|---|
| AWS account and AWS CLI v2 | Use an IAM user or role with administrator access, not the root user |
| Terraform 1.5 or newer | Tested with 1.16 |
| Python 3 with `pip3` on `PATH` | `terraform apply` builds the Lambda zip with pip (Linux wheels are downloaded, so a Mac works) |
| Docker | Builds the PostgreSQL client layer for the data-tools Lambda |
| Flutter (stable) | Builds the web app |

### 5.2 Create the Terraform state bucket (once per AWS account)

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output state_bucket_name      # e.g. campushub-tfstate-1a2b3c4d
```

This creates an encrypted, versioned S3 bucket and the `campushub-tf-locks` DynamoDB table.

### 5.3 Build the PostgreSQL layer

```bash
terraform/modules/data_tools/pg_layer/build.sh     # needs Docker, a few minutes, writes pg-layer.zip
```

### 5.4 Configure

Create `terraform/terraform.tfvars`. It is gitignored. Every variable has a default; set at least
`alert_email`.

```hcl
alert_email        = "you@example.com"   # budget and alarm emails (confirm the SNS email AWS sends)
multi_az_db        = false               # true = standby replica in a second AZ, roughly 2x RDS cost
enable_cloudfront  = true                # needed for HTTPS, Cognito sign-in and the edge cache
enable_elasticache = true                # Redis cache; false = app runs uncached
```

### 5.5 Initialise and apply

`versions.tf` names one team member's state bucket. Point Terraform at your own bucket at init time
instead of editing the file:

```bash
cd terraform
terraform init -backend-config="bucket=<state_bucket_name from 5.2>"
terraform plan -out=deploy.tfplan
terraform apply deploy.tfplan
```

The first apply creates about 165 resources and takes 20 to 25 minutes. RDS, ElastiCache and CloudFront
take the longest. Then print the outputs:

```bash
terraform output
```

### 5.6 Allow sign-in from the CloudFront URL

Cognito accepts sign-in redirects only to URLs it knows. The CloudFront address exists only after the
first apply, so add it and apply again (a small in-place update):

```hcl
# terraform/terraform.tfvars
additional_callback_urls = ["https://<cloudfront_domain_name>/"]
```

```bash
terraform apply
```

### 5.7 Load the database

A new RDS database is empty. Load it in one of two ways.

**Option A: restore a data snapshot** (recommended). Put the snapshot (`campushub.dump`, `uploads/`,
`MANIFEST.txt`) in `terraform/data/snapshot/` (gitignored, since it holds personal data), then:

```bash
cd terraform
./scripts/snapshot_restore.sh
```

Then apply every migration in `backend/db/migrations/` newer than the snapshot, in order. The snapshot
of 3 November 2026 is at revision 24, so it needs `025_company_created_by.sql` and
`026_unblock_requests_bookmarks.sql`:

```bash
for m in 025_company_created_by 026_unblock_requests_bookmarks; do
  python3 -c 'import json,sys; print(json.dumps({"action":"migrate","sql":open(sys.argv[1]).read()}))' \
    ../backend/db/migrations/$m.sql > /tmp/migrate.json
  aws lambda invoke --function-name "$(terraform output -raw data_tools_function_name)" \
    --cli-binary-format raw-in-base64-out --payload file:///tmp/migrate.json /tmp/out.json && cat /tmp/out.json
done
```

The restored users have no account in this deployment's Cognito pool. They can sign up again with the
same email, and the backend links the new sign-in to their existing record. To mark the ones who
don't as deactivated instead (dry run first):

```bash
./scripts/deactivate_missing_cognito_users.sh            # lists who would be deactivated
./scripts/deactivate_missing_cognito_users.sh --apply
```

Full guide: [docs/restoring the data snapshot.md](docs/restoring%20the%20data%20snapshot.md).

**Option B: empty database.** Run the same `migrate` command with `backend/db/schema.sql`, then with
`backend/db/reference-data.sql` (campus services and default event tags).

### 5.8 Publish the web app

```bash
cd terraform
./scripts/deploy_frontend.sh
```

The script reads the CloudFront domain, bucket and Cognito settings from `terraform output`, builds
Flutter with `USE_MOCK=false`, syncs `build/web` to S3, marks the app's entry files (`index.html`,
`main.dart.js`, ...) `Cache-Control: no-cache` so browsers pick up a new build, and invalidates
CloudFront. For automatic
deploys, see the GitHub Actions workflow in [frontend/README.md](frontend/README.md#7-deploy).

### 5.9 Check it

```bash
CF=https://$(terraform output -raw cloudfront_domain_name)
curl -s $CF/api/v1/health                                  # {"status":"ok"}
curl -sI $CF/api/v1/departments | grep -i x-cache          # Miss from cloudfront
curl -sI $CF/api/v1/departments | grep -i x-cache          # Hit from cloudfront (within 20 s)
curl -s  $CF/api/v1/me                                     # {"detail":"Sign in to do this."} (JSON 401)
```

Then open the CloudFront URL and sign up.

## 6. Deploy locally

The whole app runs on one machine with no AWS account: PostgreSQL and MinIO (an S3-compatible store)
in Docker, the API with uvicorn, and the web app with Flutter. Sign-in uses the backend's dev mode
instead of Cognito.

### 6.1 Prerequisites

| Tool | Version |
|---|---|
| Docker Desktop | Any recent version |
| Python | 3.12 or 3.13 (asyncpg 0.30.0 has no 3.14 wheels) |
| Flutter | Stable channel, with Chrome for `flutter run -d chrome` |

### 6.2 Start the database and file storage

```bash
cd backend
docker compose up -d
```

| Service | Address | Notes |
|---|---|---|
| PostgreSQL 16 | `localhost:5432`, user/password/database `campushub` | Loads `db/schema.sql` and `db/reference-data.sql` on the first start |
| MinIO S3 API | `http://localhost:9000` | Creates the `campushub-uploads` bucket |
| MinIO console | `http://localhost:9001` | Login `minioadmin` / `minioadmin` |

Data lives in the Docker volumes `campushub_pgdata` and `campushub_s3data` and survives restarts.
Only `docker compose down -v` deletes it.

### 6.3 Start the API

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.local.example .env          # dev sign-in, local MinIO
uvicorn app.main:app --reload --env-file .env
```

Open http://localhost:8000/docs for the interactive API, and http://localhost:8000/api/v1/health for a
quick check. `--env-file` is required: it also passes the MinIO keys to boto3.

### 6.4 Optional: demo data, admin, Redis

```bash
python scripts/seed_dummy_data.py            # 50 students, courses, listings, events, chats, ...
```

To make yourself the admin (sign in once first; the database allows exactly one admin):

```bash
docker compose exec db psql -U campushub -c "UPDATE users SET base_role = 'admin' WHERE email = 'you@iisc.ac.in';"
```

To try the Redis cache locally, start Redis and point the API at it:

```bash
docker run -d --name campushub-redis -p 127.0.0.1:6379:6379 redis:7
echo 'CAMPUSHUB_REDIS_HOST=localhost' >> .env     # then restart uvicorn
```

Without `CAMPUSHUB_REDIS_HOST` the API simply runs uncached.

### 6.5 Start the web app

```bash
cd frontend
flutter pub get
flutter run -d chrome \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=http://localhost:8000
```

Sign in with any `@iisc.ac.in` email. With no mail server configured, the backend prints the 6-digit code in the uvicorn log (`CampusHub sign-in code for ...`). Type that code into the app. Seeded users can also be used, for example
`ananya.rao@iisc.ac.in`.

To serve a release build instead of `flutter run`:

```bash
flutter build web --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:8000
cd build/web && python3 -m http.server 8080      # http://localhost:8080
```

### 6.6 Stop

```bash
cd backend && docker compose stop        # keeps the data
docker compose down -v                   # deletes the database and uploaded files
```

More detail (sharing the backend on your network, Lost & Found matching models, upgrading an existing
local database): [backend/README.md](backend/README.md#run-it-locally) and
[frontend/README.md](frontend/README.md#4-run-locally).

## 7. Using CampusHub

Open the site (the CloudFront URL on AWS, or `flutter run` locally). Anyone can browse; signing in with an
`@iisc.ac.in` email unlocks posting.

### 7.1 Roles

| Role | Can do |
|---|---|
| **Guest** (not signed in) | Read every public feed: listings, Lost & Found, courses, placement pages, events, mess menus |
| **Signed-in user** | Everything a guest can, plus create, edit and delete their own posts, feedback, forum threads and profile; message other users; bookmark, follow and save searches |
| **Moderator** | Scoped by the admin to a module (Buy & Sell, Lost & Found, Placement Hub, Events) or, for Academic Help, a department or a single course. Removes posts in their scope and handles reports; department moderators manage courses, materials and course moderators |
| **Administrator** | Exactly one account. Everything, plus granting and revoking moderators, deactivating accounts, editing campus services and handing the admin role to someone else |

### 7.2 What each module does

| Module | Main actions |
|---|---|
| Buy & Sell | Post a listing with photos, price, category and location; mark it Available, Reserved or Sold; search and filter by category, price and keyword; watch prices and bookmark listings |
| Wanted | Post what you are looking for; you get an alert when a matching listing is posted |
| Lost & Found | File a lost or found report; see likely matches and get notified of them |
| Academic Help | Browse departments and courses; read and post course feedback; share materials; follow a course; read its survival guide; discuss in course forums |
| Placement Hub | Company pages with job descriptions, pre-placement talks, hiring statistics, interview experiences, seniors to contact and a company forum |
| Events | Timeline of Past / Present / Upcoming events, filtered by tag; bookmark events and follow tags for updates |
| Mess | Daily menus per mess; follow a mess for meal alerts |
| Messages | One chat per person; offers that reserve a listing |
| Notifications and alerts | Inbox for matches, replies, offers, event updates and saved-search alerts |
| Profile | Your details, verified phone number, "My postings", and deactivating your account |

### 7.3 Administrator and moderator tasks

**Make the first admin.** The database allows exactly one admin. After the person has signed in once:

```bash
# Locally
docker compose exec db psql -U campushub -c "UPDATE users SET base_role = 'admin' WHERE email = 'you@iisc.ac.in';"

# On AWS (through the data-tools Lambda, from terraform/)
echo '{"action":"migrate","sql":"UPDATE users SET base_role = '"'"'admin'"'"' WHERE email = '"'"'you@iisc.ac.in'"'"';"}' > /tmp/admin.json
aws lambda invoke --function-name "$(terraform output -raw data_tools_function_name)" \
  --cli-binary-format raw-in-base64-out --payload file:///tmp/admin.json /tmp/out.json && cat /tmp/out.json
```

After that, the admin hands the role over from the app (or `POST /api/v1/users/{id}/make-admin`).

| Task | Who | Where |
|---|---|---|
| Grant or revoke a moderator role | Admin | Admin panel → moderator grants (`POST`/`DELETE /api/v1/moderators`) |
| Review reported content | Moderators of that module, admin | Reports queue |
| Handle seller strikes, appeals and unblock requests | Buy & Sell moderators, admin | Admin panel → unblock requests |
| Import placement sheets, company lists and schedules | Placement Hub moderators | Placement Hub import; formats in [docs/placement-csv-formats.md](docs/placement-csv-formats.md) |
| Edit landing-page campus services | Admin | `PATCH /api/v1/campus-services/{id}` |

### 7.4 Using the API directly

- **Locally:** open http://localhost:8000/docs, click **Authorize** and enter any IISc email as
  `X-Dev-User` to act as that user.
- **On AWS:** send the Cognito ID token as a bearer token, for example
  `curl -H "Authorization: Bearer <id_token>" https://<cloudfront_domain_name>/api/v1/me`.
- Every endpoint, with its fields: [docs/api-reference.md](docs/api-reference.md).

## 8. Tests

```bash
cd backend && pytest                 # needs the docker compose database
cd frontend && flutter test
```

For a deployed stack, use the `curl` checks in [step 5.9](#59-check-it).

## 9. Performance and metrics

PRD Experiment 1 (concurrency and scalability) was run on 6 November 2026 against both stacks with the
Locust suite in [`locust_load_testing/`](https://github.com/gyeoroo24/CampusHub/tree/main/locust_load_testing)
(on `main`). The full report, with per-endpoint tables, is
[`locust_load_testing/output/BENCHMARK_SUMMARY.md`](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/BENCHMARK_SUMMARY.md).
The root-cause figures in 8.4 come from CloudWatch for the serverless stack.

### 9.1 Test setup

| Item | Serverless (Lambda) | EC2 baseline |
|---|---|---|
| Target | API Gateway URL of the `dev` stack | ALB of the `baseline` stack |
| Compute | 5 Lambda functions, account limit 400 concurrent executions | 3 x `t4g.micro` in the Auto Scaling group |
| Database | RDS PostgreSQL `db.t4g.micro` (Multi-AZ), RDS Proxy **off** | RDS PostgreSQL `db.t4g.micro` |
| Load tool | Locust 2.47.0, distributed over all local CPU cores (`--processes -1`) | same |
| Workload | Preset `acad_placement_preset`: 17 weighted read-only `GET` endpoints from Academic Help and Placement Hub, plus `/health`, with a Cognito ID token | same |
| Concurrency | 101 users (spawn 10/s), 250 users (25/s), 501 users (25/s) | same |
| Duration | 2 minutes per run | same |

Both targets bypass CloudFront, so the 20-second edge cache was not part of these runs.

**Differences from the PRD plan:** the PRD specifies 100 / 300 / 500 users, 10-minute steady-state runs,
a mixed read/write workload and a load generator on a `c5.large` in `ap-south-1`. These runs used
101 / 250 / 501 users for 2 minutes, read-only traffic, and a local load generator.

### 9.2 Results

Locust counts failed requests in its throughput, so the table also shows the rate of **successful**
requests (requests per second x share that succeeded). Latency percentiles include failed requests.

| Stack | Users | Requests | Failures | Throughput (req/s) | Successful (req/s) | Avg (ms) | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Lambda | 101 | 6,566 | 0 (0.00 %) | 54.69 | 54.69 | 73.8 | 53 | 74 | 140 | 4,765 |
| Lambda | 250 | 14,621 | 13,000 (88.91 %) | 121.79 | 13.5 | 182.6 | 150 | 280 | 3,200 | 6,131 |
| Lambda | 501 | 24,002 | 20,204 (84.18 %) | 199.84 | 31.6 | 556.8 | 430 | 1,500 | 3,500 | 7,164 |
| EC2 | 101 | 6,306 | 0 (0.00 %) | 52.53 | 52.53 | 104.6 | 110 | 120 | 160 | 375 |
| EC2 | 250 | 9,616 | 2,965 (30.83 %) | 80.05 | 55.4 | 1,304.0 | 130 | 5,800 | 24,000 | 60,091 |
| EC2 | 501 | 12,168 | 871 (7.16 %) | 101.29 | 94.0 | 2,907.3 | 440 | 13,000 | 47,000 | 61,266 |

Failure types: Lambda 250 users, 13,000 x HTTP 500; Lambda 501 users, 20,197 x 500 and 7 x 503;
EC2 250 users, 2,912 x 500, 52 x 502, 1 x 504; EC2 501 users, 725 x 500, 78 x 502, 68 x 504.

### 9.3 PRD targets

| PRD requirement | Target | Lambda | EC2 | Result |
|---|---|---|---|---|
| NFR-1 latency | p99 ≤ 600 ms, including cold starts | 140 ms at 101 users | 160 ms at 101 users | **Met** at 101 users. Lambda's first request per user (cold start) had p99 4.1 to 4.7 s |
| NFR-2 throughput | ≥ 50 req/s with < 1 % errors | 54.69 req/s, 0 % | 52.53 req/s, 0 % | **Met** at 101 users, by a small margin |
| NFR-3 scalability | ≥ 500 users with p99 ≤ 1,200 ms (2 x NFR-1) | p99 3.5 s, 84 % errors | p99 47 s, 7 % errors | **Not met** by either stack |
| NFR-4 availability | ≥ 99 % over 2 weeks | not measured | not measured | Needs the 2-week CloudWatch canary |
| NFR-5 cost | within free-tier credits | not measured | not measured | Experiment 2 not run yet |

### 9.4 Analysis

1. **At normal load, Lambda answers faster.** At 101 users both stacks met every target. Lambda's
   median was 53 ms against EC2's 110 ms, and most Lambda endpoints had p50 near 50 ms against about
   100 ms on EC2. On EC2, `/health` alone took 35 ms, so most of the 100 ms was database and
   application work on the small instances.
2. **Lambda failed at 250+ users because the database ran out of connections.** The PRD names this as
   risk 3. CloudWatch for the 501-user run (12:38 to 12:41 UTC) shows:
   - Lambda scaled to **399 concurrent executions** (the account limit is 400), with 7 throttles,
     which match the 7 HTTP 503 responses;
   - RDS peaked at **179 database connections**;
   - the functions logged thousands of `asyncpg TooManyConnectionsError: sorry, too many clients
     already` (nearly 11,000 in `academic-hub` alone).

   Each Lambda container opens its own pool, so 400 containers ask for far more connections than a
   `db.t4g.micro` has. Even `/health` failed (it runs `SELECT 1`). The headline throughput of
   122 to 200 req/s is mostly fast 500 responses; only 13.5 and 31.6 req/s succeeded.
3. **EC2 degraded by queueing instead.** Three instances with 2 uvicorn workers each have a bounded
   number of connections, so requests waited: p99 rose to 24 s at 250 users and 47 s at 501 users,
   with 500 errors from the exhausted application pool and 502/504 from the ALB. EC2 completed more
   successful requests (55 and 94 req/s) but far too slowly for NFR-3. The 501-user run had a lower
   error rate than the 250-user run; the two would need a rerun to explain.
4. **Cold starts are visible.** On Lambda, each simulated user's first request (`[Init]`) had p95 of
   3.6 to 4.4 s, the cost of starting new containers during the ramp-up. EC2 had no such outliers at
   101 users (max 375 ms).
5. **Caching was not exercised.** The tests called API Gateway and the ALB directly. Through
   CloudFront, the `/departments`, `/courses`, `/companies` and `/placement/stats` requests would be
   served from the edge for 20 seconds.

### 9.5 Recommended reruns

| Change | Why |
|---|---|
| `enable_rds_proxy = true` on the serverless stack | The PRD's mitigation for risk 3: pools connections across all Lambda containers |
| Cap Lambda concurrency (reserved concurrency per function) | Bounds the number of database clients even without RDS Proxy |
| Run through the CloudFront URL | Includes the edge cache that real users get |
| 10-minute runs at 100 / 300 / 500 users with writes in the mix | Matches the PRD's Experiment 1 and NFR-2 workload |
| Load generator on an EC2 `c5.large` in `ap-south-1` | PRD risk 2: keeps client CPU and network out of the measurements |
| Experiment 2 (24-hour bursty profile) and a 2-week canary | Measures NFR-5 (cost) and NFR-4 (availability) |

### 9.6 Raw results and charts

Each run folder has an interactive `report.html`, raw CSVs and charts (`chart_dashboard.png`,
`chart_response_times.png`, `chart_throughput_rps.png`, `chart_active_users.png`).

| Run | Report | Dashboard chart |
|---|---|---|
| Lambda, 101 users | [report.html](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/lambda_101users_acad_placement_20261106_195430_101u_10r_2m/report.html) | [chart_dashboard.png](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/lambda_101users_acad_placement_20261106_195430_101u_10r_2m/chart_dashboard.png) |
| Lambda, 250 users | [report.html](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/lambda_250users_acad_placement_20261106_193701_250u_25r_2m/report.html) | [chart_dashboard.png](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/lambda_250users_acad_placement_20261106_193701_250u_25r_2m/chart_dashboard.png) |
| Lambda, 501 users | [report.html](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/lambda_501users_acad_placement_20261106_180806_501u_25r_2m/report.html) | [chart_dashboard.png](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/lambda_501users_acad_placement_20261106_180806_501u_25r_2m/chart_dashboard.png) |
| EC2, 101 users | [report.html](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/ec2_101users_acad_placement_20261106_203135_101u_10r_2m/report.html) | [chart_dashboard.png](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/ec2_101users_acad_placement_20261106_203135_101u_10r_2m/chart_dashboard.png) |
| EC2, 250 users | [report.html](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/ec2_250users_acad_placement_20261106_215129_250u_25r_2m/report.html) | [chart_dashboard.png](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/ec2_250users_acad_placement_20261106_215129_250u_25r_2m/chart_dashboard.png) |
| EC2, 501 users | [report.html](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/ec2_501users_acad_placement_20261106_211502_501u_25r_2m/report.html) | [chart_dashboard.png](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/ec2_501users_acad_placement_20261106_211502_501u_25r_2m/chart_dashboard.png) |

### 9.7 How to reproduce

```bash
cd locust_load_testing/locust-automated      # on main
./start.sh                                   # creates .venv, installs Locust, opens the GUI
```

In the GUI: choose the target (Lambda API, Baseline ALB or `localhost:8000`), paste a Cognito ID token
and verify it, load the `acad_placement_preset` preset, set users, spawn rate and duration, and start.
Results are written to `locust_load_testing/output/<run>/`. Details:
[`locust_load_testing/README.md`](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/README.md).

## 10. Cost

Approximate monthly cost in `ap-south-1` if left running, at development traffic:

| Item | Approx. per month |
|---|---|
| 4 VPC interface endpoints x 3 AZs (Secrets Manager, Cognito, SSM, KMS) | ~$90 |
| RDS `db.t4g.micro`, 20 GB gp3 | ~$13 single-AZ, ~$26 Multi-AZ |
| ElastiCache `cache.t3.micro` | free for 12 months on a new account, then ~$12 |
| Lambda, API Gateway, CloudFront, S3, Cognito | mostly within the free tier |

The interface endpoints let the Lambdas reach AWS APIs without a NAT Gateway or internet route. They are
billed per endpoint, per AZ, per hour. The app code calls only Secrets Manager, Cognito and S3 directly,
so the SSM and KMS endpoints are candidates for removal (check first). The `monthly_budget_usd` alert
defaults to $50.

## 11. Tear down

```bash
cd terraform
./scripts/snapshot_export.sh       # optional: keep a copy of the data first
terraform destroy
```

Both S3 buckets use `force_destroy`, so their contents are deleted too. The state bucket from
`bootstrap/` is not removed by this; destroy it from `terraform/bootstrap` when you no longer need the
state.

## 12. Documentation index

| Document | Contents |
|---|---|
| [PRD.md](PRD.md) | The original project requirements (Markdown copy of the PRD PDF) |
| [DEV.md](DEV.md) | Developer guide: code map, request flow, conventions, common tasks |
| [backend/README.md](backend/README.md) | Running, testing and configuring the API; every endpoint |
| [frontend/README.md](frontend/README.md) | Flutter app structure, build flags, deploy |
| [terraform/README.md](terraform/README.md) | Modules, variables, outputs, troubleshooting |
| [docs/api-reference.md](docs/api-reference.md) | Every API endpoint, for frontend work |
| [docs/schema/README.md](docs/schema/README.md) | Database diagrams, one per module |
| [docs/restoring the data snapshot.md](docs/restoring%20the%20data%20snapshot.md) | Export and restore data between deployments |
| [docs/cloud-deployment-checklist.md](docs/cloud-deployment-checklist.md) | What to check before going live |
| [docs/deployment errors resolution.md](docs/deployment%20errors%20resolution.md) | Errors hit while deploying the Lambda stack, with fixes |
| [docs/placement-csv-formats.md](docs/placement-csv-formats.md) | Placement sheet import formats |
| [docs/category-suggest-accuracy.md](docs/category-suggest-accuracy.md), [docs/auto-flag-accuracy.md](docs/auto-flag-accuracy.md) | ML feature evaluations |
| `docs/session-notes-*.md` | What each work session added and fixed |
| [Cloud_Computing_Project-PRD.pdf](Cloud_Computing_Project-PRD.pdf) | Product requirements |

## 13. Troubleshooting

| Step | Symptom | Cause | Fix |
|---|---|---|---|
| 5.5 `terraform init` | `403 Forbidden` on `HeadObject` for `campushub-tfstate-...` | `versions.tf` names a team member's state bucket, in another account | `terraform init -reconfigure -backend-config="bucket=<your state bucket>"` |
| 5.5 `terraform plan` | `filemd5 ... pg_layer/pg-layer.zip: no such file or directory` | The PostgreSQL layer was not built | Run step 5.3 (`pg_layer/build.sh`, needs Docker running) |
| 5.5 `terraform apply` | `build_lambda_zip.sh: no pip/pip3 on PATH` | Python/pip missing on the machine running Terraform | Install Python 3 with pip |
| 5.5 `terraform apply` | CloudFront `AccessDenied`: the account must be verified | New AWS accounts cannot create CloudFront distributions until verified | Open an AWS support case. Meanwhile `enable_cloudfront = false` works, but without HTTPS Cognito sign-in does not |
| 5.5 `terraform apply` | ElastiCache `CreateReplicationGroup`: `Invalid AuthToken provided` | The generated Redis password used characters ElastiCache rejects (hit on 6 November 2026) | Fixed on this branch (commit `1601629`: only `! & # $ ^ < > -`). On an older checkout, pull and apply again |
| 5.5 `terraform plan` | Every plan shows in-place updates to CloudFront `minimum_protocol_version` and the RDS parameter group `rds.force_ssl` | Provider quirks: the default certificate always reports `TLSv1` | Harmless; apply or ignore |
| 5.5 `terraform init` | Warning: `dynamodb_table` is deprecated, use `use_lockfile` | Newer Terraform versions | Harmless; locking still works |
| 5.7 / 5.9 | API returns 500; Lambda logs show `relation "listings" does not exist` | The new RDS database is empty | Load the schema or restore a snapshot (step 5.7) |
| 5.9 sign-in | Cognito Hosted UI shows `redirect_mismatch` | The CloudFront URL is not an allowed callback | Step 5.6: add it to `additional_callback_urls` and apply |
| 7 tests | `terraform/tests/smoke_test.py` scores 0/10 (all 404) against a working stack | The script calls old paths (`/api/buy-sell/health`, `/api/<module>/items`) instead of `/api/v1/...`; `test_permission_matrix.py` too | Use the `curl` checks in step 5.9 |
| After deploy | Calls to Amazon Comprehend or to another Lambda time out | The private subnets have no endpoint for those services | Only if `CAMPUSHUB_SENTIMENT_BACKEND=comprehend` or `CAMPUSHUB_MATCH_MODE=lambda`; add the interface endpoints or a NAT Gateway first |
| 6.5 local | Reloading `/events` on `python3 -m http.server` returns 404 | `http.server` has no fallback to `index.html` | Open the site from `/`, or use `flutter run` |

Logs: `aws logs tail /aws/lambda/campushub-dev-<function> --since 15m`. More rows, including the first
Lambda deployment's errors, are in [terraform/README.md](terraform/README.md#10-troubleshooting) and
[docs/deployment errors resolution.md](docs/deployment%20errors%20resolution.md).

## 14. Team

**Team Order of Phoenix**, DS252 Introduction to Cloud Computing, Indian Institute of Science (IISc).

| SR No. | Name | Email |
|---|---|---|
| 26898 | Mohammad Sufyan Azam | [mohammadazam@iisc.ac.in](mailto:mohammadazam@iisc.ac.in) |
| 26643 | Adithya Chippa | [cadithya@iisc.ac.in](mailto:cadithya@iisc.ac.in) |
| 26648 | Dinky Lakhani | [dinkylakhani@iisc.ac.in](mailto:dinkylakhani@iisc.ac.in) |
| 25862 | Mukund Kukreja | [kmukund@iisc.ac.in](mailto:kmukund@iisc.ac.in) |
