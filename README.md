# CampusHub

CampusHub is one web app for IISc students: Buy & Sell, Lost & Found, Academic Help, Placement Hub,
Community Events, mess menus and forums. It is the group project of team **Order of Phoenix** for
**DS252 Introduction to Cloud Computing** (IISc).

The same FastAPI backend and Flutter web app are deployed on AWS in two ways, so that the two can be
compared (PRD section 7):

- **Serverless** (this branch): CloudFront → API Gateway → AWS Lambda.
- **Baseline** (`baseline-infra-restore`): CloudFront → Application Load Balancer → EC2 Auto Scaling group.

Both use PostgreSQL on RDS, ElastiCache Redis, S3 and Cognito.

## Table of contents

1. [Branches](#1-branches)
2. [Serverless architecture (this branch)](#2-serverless-architecture-this-branch)
3. [Serverless vs EC2 baseline](#3-serverless-vs-ec2-baseline)
4. [Repository layout](#4-repository-layout)
5. [Deploy to AWS](#5-deploy-to-aws)
6. [Deploy locally](#6-deploy-locally)
7. [Tests](#7-tests)
8. [Performance and metrics](#8-performance-and-metrics)
9. [Cost](#9-cost)
10. [Tear down](#10-tear-down)
11. [Documentation index](#11-documentation-index)
12. [Troubleshooting](#12-troubleshooting)
13. [Team](#13-team)

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
| Load-testing hypothesis | Cold starts raise p95 latency; scales out instantly | Steady latency with warm processes; scale-out waits for the ASG |

The design rationale for the baseline is in `Baseline-Architecture.md` on the `baseline-infra-restore`
branch.

## 4. Repository layout

```
.github/workflows/deploy-frontend.yml   Builds the Flutter web app and publishes it to S3 + CloudFront
backend/      FastAPI application, tests, SQL schema and migrations        -> backend/README.md
frontend/     Flutter web app                                              -> frontend/README.md
terraform/    All AWS infrastructure, helper scripts, smoke tests         -> terraform/README.md
docs/         PRD, API reference, schema diagrams, deployment logs, session notes
locust_load_testing/   (on main) Locust load-test suite and benchmark results
Cloud_Computing_Project-PRD.pdf        Product requirements
Proposal-Serverless-Architecture.jpg   The serverless design this branch implements
Baseline-Architecture.jpg              The EC2 baseline design
```

## 5. Deploy to AWS

These are the steps used for the deployment on 6 November 2026, in `ap-south-1`. Module and variable
detail is in [terraform/README.md](terraform/README.md). If a step fails, see
[Troubleshooting](#12-troubleshooting).

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

## 7. Tests

```bash
cd backend && pytest                 # needs the docker compose database
cd frontend && flutter test
```

For a deployed stack, use the `curl` checks in [step 5.9](#59-check-it).

## 8. Performance and metrics

> **Placeholder.** Fill in this section with the results of the load tests (PRD section 7). The
> serverless and EC2 baseline stacks should be tested with the same workload, region and data.
>
> The Locust suite and the raw results of the 6 November 2026 runs are in
> [`locust_load_testing/`](https://github.com/gyeoroo24/CampusHub/tree/main/locust_load_testing) on `main`, with a summary in
> [`locust_load_testing/output/BENCHMARK_SUMMARY.md`](https://github.com/gyeoroo24/CampusHub/blob/main/locust_load_testing/output/BENCHMARK_SUMMARY.md).

### 8.1 Test setup

| Item | Value |
|---|---|
| Load generator | _TBD_ (Locust or k6; instance type and region, e.g. `c5.large` in `ap-south-1`) |
| Workload mix | _TBD_ (planned: 50 % reads, 30 % searches, 20 % writes; see `Baseline-Architecture.md`) |
| Endpoints exercised | _TBD_ (e.g. `GET /api/v1/listings`, `GET /api/v1/listings?q=...`, `POST /api/v1/listings`) |
| Concurrent users and ramp-up | _TBD_ |
| Test duration | _TBD_ |
| Data set | _TBD_ (e.g. the 3 November 2026 snapshot) |
| Caching | _TBD_ (CloudFront and Redis on or off for each run) |
| Date of the runs | _TBD_ |

### 8.2 Results

| Metric | Serverless (Lambda) | EC2 baseline | Notes |
|---|---|---|---|
| p50 latency (ms) | _TBD_ | _TBD_ | |
| p95 latency (ms) | _TBD_ | _TBD_ | |
| p99 latency (ms) | _TBD_ | _TBD_ | |
| Peak throughput (requests/s) | _TBD_ | _TBD_ | |
| Error rate at peak (%) | _TBD_ | _TBD_ | |
| Cold start / scale-out time | _TBD_ | _TBD_ | Lambda cold start vs ASG launching an instance |
| CloudFront cache hit ratio (%) | _TBD_ | _TBD_ | CloudFront console, or `x-cache` headers |
| Redis hit ratio (%) | _TBD_ | _TBD_ | ElastiCache `CacheHitRate` metric |
| RDS CPU at peak (%) | _TBD_ | _TBD_ | |
| RDS connections at peak | _TBD_ | _TBD_ | |
| Cost at idle (USD/month) | _TBD_ | _TBD_ | |
| Cost per 1 million requests (USD) | _TBD_ | _TBD_ | |

### 8.3 Charts

_TBD: latency over time, throughput vs concurrent users, and cost vs load for both stacks._

### 8.4 Findings

_TBD: which architecture did better on each metric, and why._

### 8.5 How to reproduce

_TBD: the exact command and the CloudWatch metrics collected._ The load-test suite is
[`locust_load_testing/locust-automated/`](https://github.com/gyeoroo24/CampusHub/tree/main/locust_load_testing/locust-automated) on `main`. The current deployment of this branch is the **serverless** stack.

## 9. Cost

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

## 10. Tear down

```bash
cd terraform
./scripts/snapshot_export.sh       # optional: keep a copy of the data first
terraform destroy
```

Both S3 buckets use `force_destroy`, so their contents are deleted too. The state bucket from
`bootstrap/` is not removed by this; destroy it from `terraform/bootstrap` when you no longer need the
state.

## 11. Documentation index

| Document | Contents |
|---|---|
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

## 12. Troubleshooting

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

## 13. Team

**Team Order of Phoenix**, DS252 Introduction to Cloud Computing, Indian Institute of Science (IISc).

| SR No. | Name | Email |
|---|---|---|
| 26898 | Mohammad Sufyan Azam | [mohammadazam@iisc.ac.in](mailto:mohammadazam@iisc.ac.in) |
| 26643 | Adithya Chippa | [cadithya@iisc.ac.in](mailto:cadithya@iisc.ac.in) |
| 26648 | Dinky Lakhani | [dinkylakhani@iisc.ac.in](mailto:dinkylakhani@iisc.ac.in) |
| 25862 | Mukund Kukreja | [kmukund@iisc.ac.in](mailto:kmukund@iisc.ac.in) |
