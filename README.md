# CampusHub (EC2 baseline)

CampusHub is one web app for IISc students: Buy & Sell, Lost & Found, Academic Help, Placement Hub,
Community Events, mess menus and forums. It is the group project of team **Order of Phoenix** for
**DS252 Introduction to Cloud Computing** (IISc).

The same FastAPI backend and Flutter web app are deployed on AWS in two ways, so that the two can be
compared (PRD section 7):

- **Serverless** (`fix/cloud-deploy-zip-and-routes`, the `main` branch): CloudFront → API Gateway → AWS Lambda.
- **Baseline** (this branch): CloudFront → Application Load Balancer → EC2 Auto Scaling group.

Both use PostgreSQL on RDS, ElastiCache Redis, S3 and Cognito.

## Table of contents

1. [Branches](#1-branches)
2. [EC2 baseline architecture (this branch)](#2-ec2-baseline-architecture-this-branch)
3. [EC2 baseline vs serverless](#3-ec2-baseline-vs-serverless)
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
| [`fix/cloud-deploy-zip-and-routes`](https://github.com/gyeoroo24/CampusHub/tree/fix/cloud-deploy-zip-and-routes) (planned `main`) | Serverless | 5 AWS Lambda functions (Python 3.11, zip package) behind API Gateway HTTP API | `dev` | `campushub/dev/terraform.tfstate` |
| **`baseline-infra-restore`** (this branch) | EC2 baseline | EC2 Auto Scaling group (Amazon Linux 2023, `t4g.micro`) behind an Application Load Balancer | `baseline` | `campushub/baseline/terraform.tfstate` |

The application code (`backend/`, `frontend/`) is nearly the same on both branches. The differences are
listed in [section 3](#3-ec2-baseline-vs-serverless). Every AWS resource name includes the
`environment`, so both stacks can run side by side in one AWS account.

The design rationale, security model and load-testing plan for this branch are in
[Baseline-Architecture.md](Baseline-Architecture.md).

## 2. EC2 baseline architecture (this branch)

```
                         Users (browser)
                               |
                               v
              +----------------------------------+
              |  Amazon CloudFront               |   HTTPS, *.cloudfront.net certificate
              |  - /*        -> S3 (Flutter web) |   SPA rewrite function for deep links
              |  - /api/v1/<list pages> cached   |   20 s default / 60 s max edge cache
              |  - /api/*    -> ALB              |   adds the X-Origin-Verify header
              +----------------+-----------------+
                 |                         |
                 v                         v
     +-------------------+     +-----------------------------+    +----------------------+
     | S3 frontend bucket|     | Application Load Balancer   |    | Cognito user pool    |
     | (Origin Access    |     | port 80, public subnets     |    | Hosted UI, PKCE,     |
     |  Control)         |     | 10.0.1-3.0/24               |    | 4 groups             |
     +-------------------+     +--------------+--------------+    +----------------------+
                                              | HTTP :8000, health check /api/v1/health
   +------------------------------------------|-------------------------------------------+
   | VPC 10.0.0.0/16                          v                                           |
   |   +----------------------------------------------------------------------------+    |
   |   | Auto Scaling group, app subnets 10.0.4-6.0/24 (ap-south-1a / 1b / 1c)       |    |
   |   | EC2 t4g.micro, Amazon Linux 2023, uvicorn (2 workers) under systemd         |    |
   |   | min 3, desired 3, max 5; target tracking on 60 % CPU and 200 req/instance  |    |
   |   +---------+----------------------+---------------------+--------------------+    |
   |             |                      |                     |                          |
   |             v                      v                     v                          |
   |   +------------------+   +-------------------+   +------------------------------+  |
   |   | ElastiCache Redis|   | RDS PostgreSQL 16 |   | VPC endpoints: S3 (gateway), |  |
   |   | cache.t3.micro   |   | db.t4g.micro      |   | Secrets Manager, SSM, KMS    |  |
   |   | TLS + AUTH token |   | subnets 10.0.10-12|   | (interface)                  |  |
   |   +------------------+   +-------------------+   +------------------------------+  |
   |   data-tools Lambda (pg_dump / pg_restore / psql) for snapshots and migrations      |
   +-------------------------------------------------------------------------------------+
        S3 media bucket (uploads, backend.zip)   CloudWatch alarms, SNS email, AWS Budgets
```

**How an instance starts.** Terraform zips `backend/` and uploads it to the media bucket as
`_deploy/backend.zip`. Each instance's user data (`terraform/modules/compute_ec2/user_data.sh.tftpl`):

1. installs OS packages and downloads `backend.zip` (plus the optional Tesseract and ONNX model zips);
2. reads the database password and the Redis AUTH token from Secrets Manager and writes
   `/opt/campushub/backend/.env`;
3. creates a Python 3.11 virtual environment and installs `backend/requirements.txt`;
4. loads `db/schema.sql` and `db/reference-data.sql` if the database has no `users` table;
5. starts `campushub.service` (uvicorn on port 8000, 2 workers) and polls `/api/v1/health`.

There is no SSH: port 22 is closed, and administrators use SSM Session Manager.

**Caching** works as on the serverless branch: CloudFront caches 11 list/browse GET paths for 20 s
(the key includes `Authorization` and the query string), and the app checks Redis
(`backend/app/cache.py`) for 7 of them before querying Postgres. If Redis fails, requests are served
uncached.

## 3. EC2 baseline vs serverless

| | EC2 baseline (this branch) | Serverless (`fix/cloud-deploy-zip-and-routes`) |
|---|---|---|
| API entry point | Application Load Balancer (port 80, `X-Origin-Verify` header from CloudFront) | API Gateway HTTP API |
| Compute | Auto Scaling group: min 3, desired 3, max 5; scales on 60 % CPU or 200 requests per instance | 5 Lambda functions, 512 MB (community-events 1024 MB), 29 s timeout |
| Packaging | `backend.zip` uploaded to S3; user data installs it and runs uvicorn under systemd | `build_lambda_zip.sh` builds a zip at `terraform apply` |
| Python packages | Full `requirements.txt` (ML and OCR features available) | Trimmed `requirements-lambda-zip.txt` (ML and OCR off unless layers are added) |
| Scaling | New instance in a few minutes when CPU passes the target | Per request, automatic |
| DB connections | Pool of 16 per uvicorn worker, 2 workers per instance | 2 per Lambda container (RDS Proxy optional) |
| Idle cost | Instance and ALB billed every hour | Lambda/API Gateway: near zero |
| Schema on a new database | User data creates it at first boot | Load it yourself (restore or `migrate` action) |
| Frontend token refresh | Not included; users are signed out when the token expires (about 1 hour) | Refreshes the Cognito ID token on a 401 and retries |
| Load-testing hypothesis | Steady latency with warm processes; scale-out waits for the ASG | Cold starts raise p95 latency; scales out instantly |

## 4. Repository layout

```
.github/workflows/deploy-frontend.yml   Builds the Flutter web app and publishes it to S3 + CloudFront
backend/      FastAPI application, tests, SQL schema and migrations        -> backend/README.md
frontend/     Flutter web app                                              -> frontend/README.md
terraform/    All AWS infrastructure, helper scripts, smoke tests         -> terraform/README.md
docs/         PRD, API reference, schema diagrams, deployment logs, session notes
locust_load_testing/   (on main) Locust load-test suite and benchmark results
Baseline-Architecture.md               Design of this branch: rationale, security, load-test plan
Baseline-Architecture.jpg              The EC2 baseline diagram
Proposal-Serverless-Architecture.jpg   The serverless design (other branch)
Cloud_Computing_Project-PRD.pdf        Product requirements
```

## 5. Deploy to AWS

Module and variable detail is in [terraform/README.md](terraform/README.md). If a step fails, see
[Troubleshooting](#12-troubleshooting).

### 5.1 Prerequisites

| Tool | Why |
|---|---|
| AWS account and AWS CLI v2 | Use an IAM user or role with administrator access, not the root user |
| Terraform 1.5 or newer | |
| Docker | Builds the PostgreSQL client layer for the data-tools Lambda (and the optional Tesseract build) |
| Flutter (stable) | Builds the web app |

### 5.2 Create the Terraform state bucket (once per AWS account)

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output state_bucket_name      # e.g. campushub-tfstate-1a2b3c4d
```

If the serverless stack already uses a state bucket in this account, reuse it: the two branches use
different state keys.

### 5.3 Build the PostgreSQL layer

```bash
terraform/modules/data_tools/pg_layer/build.sh     # needs Docker, a few minutes, writes pg-layer.zip
```

Optional: OCR for mess menus, built for the instance's architecture (arm64 for `t4g.*`):

```bash
terraform/modules/compute_ec2/tesseract_build/build.sh                       # arm64
terraform/modules/compute_ec2/tesseract_build/build.sh --platform linux/amd64  # for t3.* instances
```

### 5.4 Configure

Create `terraform/terraform.tfvars` (gitignored). Set at least `alert_email`.

```hcl
alert_email        = "you@example.com"
multi_az_db        = false        # true = standby replica in a second AZ, roughly 2x RDS cost
enable_cloudfront  = true         # needed for HTTPS, Cognito sign-in and the edge cache
enable_elasticache = true         # Redis cache; false = app runs uncached
origin_verify_header = "<a long random string>"   # header CloudFront sends to the ALB
```

### 5.5 Initialise and apply

`versions.tf` names one team member's state bucket. Override it at init time:

```bash
cd terraform
terraform init -backend-config="bucket=<state_bucket_name from 5.2>"
terraform plan -out=baseline.tfplan
terraform apply baseline.tfplan
terraform output
```

After the apply, the first instance needs about 5 to 10 minutes to install packages and pass the ALB
health check. Watch it:

```bash
aws elbv2 describe-target-health --target-group-arn "$(terraform output -raw target_group_arn)" \
  --query 'TargetHealthDescriptions[].TargetHealth.State'
```

### 5.6 Allow sign-in from the CloudFront URL

```hcl
# terraform/terraform.tfvars
additional_callback_urls = ["https://<cloudfront_domain_name>/"]
```

```bash
terraform apply
```

### 5.7 Load the database

The first instance creates an empty schema at boot, so a new deployment already answers with empty
lists. To load the team's data snapshot instead, put it in `terraform/data/snapshot/` and replace that
empty schema:

```bash
cd terraform
FORCE=1 ./scripts/snapshot_restore.sh
```

Check first that the tables really are empty: `FORCE=1` replaces whatever is there. Then apply every
migration newer than the snapshot. The 3 November 2026 snapshot is at revision 24; on this branch it
needs `025`. The data-tools Lambda runs SQL files from the media bucket's `_snapshots/` prefix:

```bash
BUCKET=$(terraform output -raw media_s3_bucket)
aws s3 cp ../backend/db/migrations/025_company_created_by.sql "s3://$BUCKET/_snapshots/025.sql"
echo '{"action":"run_sql","key":"_snapshots/025.sql"}' > /tmp/run_sql.json
aws lambda invoke --function-name "$(terraform output -raw data_tools_function_name)" \
  --payload fileb:///tmp/run_sql.json /tmp/out.json && cat /tmp/out.json
```

Full guide: [docs/restoring the data snapshot.md](docs/restoring%20the%20data%20snapshot.md).

### 5.8 Publish the web app

```bash
cd terraform
./scripts/deploy_frontend.sh
```

The script needs CloudFront enabled: it reads the CloudFront domain, bucket and Cognito settings from
`terraform output`, builds Flutter with `USE_MOCK=false`, syncs to S3 and invalidates CloudFront.

### 5.9 Check it

```bash
CF=https://$(terraform output -raw cloudfront_domain_name)
curl -s $CF/api/v1/health                                  # {"status":"ok"}
curl -sI $CF/api/v1/departments | grep -i x-cache          # Miss, then Hit within 20 s
curl -s "http://$(terraform output -raw alb_dns_name)/api/v1/health"   # the ALB directly
```

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

Sign in with any `@iisc.ac.in` email. On this branch the backend accepts the code `123456` (the `TEMP HARDCODED OTP` block in `backend/app/otp.py`). Seeded users can also be used, for example
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
[`locust_load_testing/locust-automated/`](https://github.com/gyeoroo24/CampusHub/tree/main/locust_load_testing/locust-automated) on `main`. The current deployment of this branch is the **EC2 baseline** stack.

## 9. Cost

Approximate monthly cost in `ap-south-1` if left running:

| Item | Approx. per month |
|---|---|
| 3 VPC interface endpoints x 3 AZs (Secrets Manager, SSM, KMS) | ~$65 |
| Application Load Balancer | ~$16 plus usage |
| EC2 `t4g.micro` x 3 (the minimum), 20 GB volume each | ~$20 (750 free hours a month on a new account cover about one instance) |
| RDS `db.t4g.micro`, 20 GB gp3 | ~$13 single-AZ, ~$26 Multi-AZ |
| ElastiCache `cache.t3.micro` | free for 12 months on a new account, then ~$12 |
| CloudFront, S3, Cognito | mostly within the free tier |

Unlike the serverless stack, the instance and the ALB cost the same whether or not anyone uses the
site. The app subnets also route to the internet gateway, so the interface endpoints are a candidate for
removal on this branch (check first). The `monthly_budget_usd` alert defaults to $50.

## 10. Tear down

```bash
cd terraform
./scripts/snapshot_export.sh       # optional: keep a copy of the data first
terraform destroy
```

Both S3 buckets use `force_destroy`, so their contents are deleted too. The state bucket is not
removed.

## 11. Documentation index

| Document | Contents |
|---|---|
| [Baseline-Architecture.md](Baseline-Architecture.md) | Design of this branch: TLS termination, no NAT, security groups, load-test plan |
| [backend/README.md](backend/README.md) | Running, testing and configuring the API; every endpoint |
| [frontend/README.md](frontend/README.md) | Flutter app structure, build flags, deploy |
| [terraform/README.md](terraform/README.md) | Modules, variables, outputs, troubleshooting |
| [docs/baseline-ec2-deployment-log.md](docs/baseline-ec2-deployment-log.md) | Errors hit while deploying this baseline, with fixes |
| [docs/api-reference.md](docs/api-reference.md) | Every API endpoint, for frontend work |
| [docs/schema/README.md](docs/schema/README.md) | Database diagrams, one per module |
| [docs/restoring the data snapshot.md](docs/restoring%20the%20data%20snapshot.md) | Export and restore data between deployments |
| [docs/cloud-deployment-checklist.md](docs/cloud-deployment-checklist.md) | What to check before going live |
| [docs/deployment errors resolution.md](docs/deployment%20errors%20resolution.md) | Errors from the first Lambda deployment |
| `docs/session-notes-*.md` | What each work session added and fixed |
| [Cloud_Computing_Project-PRD.pdf](Cloud_Computing_Project-PRD.pdf) | Product requirements |

## 12. Troubleshooting

| Step | Symptom | Cause | Fix |
|---|---|---|---|
| 5.5 `terraform init` | `403` or `NoSuchBucket` for the state bucket | `versions.tf` names a team member's state bucket | `terraform init -reconfigure -backend-config="bucket=<your state bucket>"` |
| 5.5 `terraform plan` | `filemd5 ... pg_layer/pg-layer.zip: no such file or directory` | The PostgreSQL layer was not built | Run step 5.3 (needs Docker running) |
| 5.5 `terraform apply` | CloudFront `AccessDenied`: the account must be verified | New AWS accounts cannot create CloudFront distributions until verified | Open an AWS support case. Without CloudFront there is no HTTPS, so Cognito sign-in and `deploy_frontend.sh` do not work |
| 5.5 `terraform apply` | ElastiCache `CreateReplicationGroup`: `Invalid AuthToken provided` | `terraform/modules/elasticache/main.tf` lets the Redis password use characters ElastiCache rejects | Set `override_special = "!&#$^<>-"` there (the fix in commit `1601629` on `fix/cloud-deploy-zip-and-routes`), or deploy with `enable_elasticache = false` |
| 5.5 `terraform apply <plan>` | `Inconsistent dependency lock file` | `apply` ran in another directory than `plan` | Run `apply` in the directory where `plan` ran |
| 5.5 `terraform apply` | `Error acquiring the state lock` | Overlapping Terraform runs | Retry; check for a `.tflock` object in the state bucket |
| 5.5 / 5.9 | ALB returns `502` for every path; target `unhealthy` | The app did not start on the instance (for example a failed `pip install`). The user data still prints "Completed Successfully" | Read the boot log: `aws ec2 get-console-output --instance-id <id> --latest --output text \| tail -50`, or `sudo journalctl -u campushub` over SSM. Fix, then replace the instance |
| 5.7 | `snapshot_restore.sh`: `the database already has N tables` | The first instance created an empty schema at boot | Check the tables are empty, then `FORCE=1 ./scripts/snapshot_restore.sh` |
| After a code change | The site still runs the old backend after `terraform apply` | Running instances keep the `backend.zip` they booted with | `aws autoscaling start-instance-refresh --auto-scaling-group-name "$(terraform output -raw asg_name)"` |
| 5.8 / 5.9 sign-in | Cognito Hosted UI shows `redirect_mismatch` | The CloudFront URL is not an allowed callback | Step 5.6: add it to `additional_callback_urls` and apply |
| 5.8 | Web app built by GitHub Actions has no Cognito sign-in | On this branch `deploy-frontend.yml` passes only `API_BASE_URL` | Publish with `scripts/deploy_frontend.sh` |
| After sign-in | Users are signed out after about an hour | This branch's web app does not refresh the Cognito ID token | Sign in again; the refresh is on `fix/cloud-deploy-zip-and-routes` |
| After deploy | Phone verification accepts `123456` and no code is sent | The `TEMP HARDCODED OTP` block in `backend/app/otp.py` (meant for local runs) | Remove the block before deploying |
| After deploy | The ALB answers requests directly, bypassing CloudFront | `X-Origin-Verify` is sent but not checked, and the ALB allows port 80 from anywhere | Add an ALB listener rule that forwards only with the header, or restrict the ALB security group ([terraform/README.md](terraform/README.md#5-network-and-security)) |
| 7 tests | `terraform/tests/smoke_test.py` fails against a working stack | It calls `/api/<module>/...` instead of `/api/v1/...` | Use the `curl` checks in step 5.9 |
| 6.5 local | Reloading `/events` on `python3 -m http.server` returns 404 | `http.server` has no fallback to `index.html` | Open the site from `/`, or use `flutter run` |

More detail: [terraform/README.md](terraform/README.md#11-troubleshooting) and the first baseline
deployment's log, [docs/baseline-ec2-deployment-log.md](docs/baseline-ec2-deployment-log.md).

## 13. Team

**Team Order of Phoenix**, DS252 Introduction to Cloud Computing, Indian Institute of Science (IISc).

| SR No. | Name | Email |
|---|---|---|
| 26898 | Mohammad Sufyan Azam | [mohammadazam@iisc.ac.in](mailto:mohammadazam@iisc.ac.in) |
| 26643 | Adithya Chippa | [cadithya@iisc.ac.in](mailto:cadithya@iisc.ac.in) |
| 26648 | Dinky Lakhani | [dinkylakhani@iisc.ac.in](mailto:dinkylakhani@iisc.ac.in) |
| 25862 | Mukund Kukreja | [kmukund@iisc.ac.in](mailto:kmukund@iisc.ac.in) |
