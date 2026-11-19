# CampusHub infrastructure (Terraform, serverless)

This folder deploys the serverless CampusHub stack in `ap-south-1`: CloudFront, API Gateway, five API Lambda
functions (plus the push-sender and data-tools functions), RDS PostgreSQL,
ElastiCache Redis, S3, Cognito and monitoring. The step-by-step deploy guide
is in the [root readme](../readme.md#5-deploy-to-aws). This file is the reference.

The EC2 baseline is on the `STALE]-baseline-infra` branch. It has its own `terraform/README.md` **CAUTION: USED ONLY FOR COMPARISON PURPOSES**

## Table of contents

1. [Layout](#1-layout)
2. [Modules](#2-modules)
3. [Caching](#3-caching)
4. [Network and security](#4-network-and-security)
5. [Remote state](#5-remote-state)
6. [Variables](#6-variables)
7. [Outputs](#7-outputs)
8. [Build artifacts](#8-build-artifacts)
9. [Helper scripts](#9-helper-scripts)
10. [Troubleshooting](#10-troubleshooting)

## 1. Layout

```
terraform/
├── main.tf            Root composition: calls every module below
├── variables.tf       Root variables (toggles, sizes, alert email)
├── outputs.tf         URLs, IDs and endpoints printed by `terraform output`
├── providers.tf       AWS provider for ap-south-1, plus a us-east-1 alias (WAF for CloudFront)
├── versions.tf        Terraform >= 1.5, provider versions, S3 backend
├── bootstrap/         One-time: S3 state bucket and DynamoDB lock table
├── modules/           One folder per tier (see below)
├── scripts/           deploy_frontend.sh, create_vapid_keys.sh, snapshot_export.sh,
│                      snapshot_restore.sh, deactivate_missing_cognito_users.sh
└── tests/             smoke_test.py, test_permission_matrix.py (out of date, see Troubleshooting)
```

## 2. Modules

| Module | Creates |
|---|---|
| `networking` | VPC `10.0.0.0/16`; private Lambda subnets `10.0.4-6.0/24` and database subnets `10.0.10-12.0/24` in 3 AZs; security groups for the app, RDS, Redis and the endpoints; S3 gateway endpoint; interface endpoints for SSM, KMS, Secrets Manager and Cognito, plus Lambda when `enable_web_push` is on |
| `database` | RDS PostgreSQL 16 (`db.t4g.micro`, 20 GB gp3, `rds.force_ssl=1`), subnet and parameter groups, password in Secrets Manager and SSM, optional RDS Proxy |
| `elasticache` | Redis 7.1 replication group (`cache.t3.micro`, 1 node by default), TLS in transit, encryption at rest, AUTH token in Secrets Manager, `allkeys-lru` eviction |
| `storage` | Frontend bucket (served through CloudFront OAC) and media bucket (uploads, CORS, versioning, a lifecycle rule for abandoned uploads) |
| `auth` | Cognito user pool, app client, Hosted UI domain, groups `Guest`, `Signed-in`, `Moderator`, `Administrator`. The web app signs in through the Hosted UI with the authorization-code flow and PKCE, and renews sessions with refresh tokens. |
| `compute` | The Lambda zip build, 5 API Lambda functions (`buy-sell`, `lost-found`, `placement-hub`, `academic-hub`, `community-events`), IAM role, log groups, optional Tesseract and ML layers, an EventBridge warmer (every 5 minutes). With `enable_web_push`, also the push-sender function (`push.tf`), which runs outside the VPC from the same zip |
| `api_gateway` | HTTP API with per-prefix routes to the 5 Lambdas and a catch-all, stage throttling, access logs. Sign-in is checked by the app, not by a gateway authorizer |
| `cdn` | CloudFront distribution with two origins (S3 frontend, API Gateway), SPA rewrite function, API cache policy |
| `waf` | Optional WAFv2 web ACL with managed rules and rate limiting (`enable_waf`) |
| `monitoring` | SNS alert topic and email subscription, AWS Budgets guardrail, alarms for RDS CPU, Lambda errors and API Gateway 5XX |
| `data_tools` | A Lambda with `pg_dump`, `pg_restore` and `psql` in the VPC, for snapshots and migrations |

All 5 API Lambdas run the same zip (the whole FastAPI app through Mangum). Separate functions give
per-module metrics, memory and scaling; any one of them can answer any route.

## 3. Caching

| Layer | Where | What | TTL |
|---|---|---|---|
| CloudFront static | `default_cache_behavior` | Flutter web files from S3 (managed `CachingOptimized`) | Managed policy |
| CloudFront API | `modules/cdn`, `aws_cloudfront_cache_policy.api_short_ttl` | GET/HEAD on 11 list paths: `listings`, `lost-reports`, `found-reports`, `wanted`, `events`, `event-tags`, `departments`, `courses`, `messes`, `companies`, `placement/stats` | 20 s default, 60 s max, honours origin `Cache-Control` |
| Redis | `modules/elasticache`, `backend/app/cache.py` | 7 of those list queries (`listings`, `lost-reports`, `found-reports`, `events`, `departments`, `courses`, `messes`), per viewer | `CAMPUSHUB_REDIS_DEFAULT_TTL_SECONDS` (20 s) |

Rules that keep this safe:

- The CloudFront cache key includes `Authorization` and the full query string. Guests share one entry
  per query. Signed-in GETs are not edge-cached: the API sends them with `Cache-Control: private,
  no-store` (`backend/app/main.py`). `companies` needs sign-in, so in practice it is never edge-cached.
- `cached_methods` is GET/HEAD only. POST, PUT, PATCH and DELETE always reach the origin.
- Every other `/api/*` path uses the managed `CachingDisabled` policy.
- There is no distribution-wide `custom_error_response`. One used to rewrite every 403 into
  `index.html`, which hid real API errors. Deep links are handled by the `spa_rewrite` function on the
  S3 behaviour only.
- Redis keys include the viewer (`app/cache.py`, `build_key`). Any Redis error is logged once and
  treated as a cache miss.

## 4. Network and security

- The Lambda subnets have no internet route and no NAT Gateway. AWS APIs are reached through VPC
  endpoints: S3 (gateway, free) and Secrets Manager, Cognito, SSM and KMS (interface, billed per AZ per
  hour), plus Lambda when `enable_web_push` is on, so the API can hand pushes to the push-sender.
- Cognito's management API (`AdminGetUser`, used when granting a moderator role) is not available over
  PrivateLink for a user pool with a Hosted UI domain. The app logs that the check could not be made and
  grants the role anyway (`backend/app/cognito_accounts.py`). Token checks are unaffected.
- RDS accepts 5432 and Redis accepts 6379 only from the app security group.
- Lambda environment variables hold `CAMPUSHUB_DATABASE_SECRET_ARN` and
  `CAMPUSHUB_REDIS_AUTH_SECRET_ARN`, not the secrets themselves. The API Lambdas' IAM role reads the
  database credentials and the Redis AUTH token from Secrets Manager, and its environment's parameters
  (`/campushub/<environment>/*`) from SSM Parameter Store (`modules/compute/iam.tf`).
- S3 buckets use SSE-S3 (AES-256) encryption at rest, a deliberate choice for the AWS Free Tier.
- The frontend bucket is private. CloudFront reads it through Origin Access Control.

## 5. Remote state

`bootstrap/` creates an S3 bucket named `campushub-tfstate-<random>` and the `campushub-tf-locks` table.
Its own state is local (`bootstrap/terraform.tfstate`): keep that file.

`versions.tf` hardcodes one team member's bucket. Everyone else should override it at init time
instead of editing the file:

```bash
terraform init -backend-config="bucket=campushub-tfstate-<yours>"
```

Add `-reconfigure` when switching an existing working directory to another bucket. The state key is
`campushub/dev/terraform.tfstate`.

## 6. Variables

Set these in `terraform.tfvars` (gitignored).

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `ap-south-1` | |
| `environment` | `dev` | Part of every resource name |
| `project_name` | `campushub` | |
| `alert_email` | a team member's address | **Change this.** Receives SNS alarms and budget alerts |
| `monthly_budget_usd` | `50.0` | AWS Budgets alert at 80 % and 100 % |
| `enable_cloudfront` | `true` | Needed for HTTPS, Cognito sign-in and the edge cache |
| `enable_waf` | `false` | WAF costs about $5/month plus $1 per rule |
| `enable_elasticache` | `true` | `false` unsets the Redis variables; the app runs uncached |
| `redis_node_type` | `cache.t3.micro` | |
| `redis_num_cache_clusters` | `1` | More than 1 adds replicas with automatic failover |
| `multi_az_db` | `true` | `false` for a single-AZ, free-tier database |
| `db_instance_class` | `db.t4g.micro` | |
| `db_allocated_storage` | `20` | GB |
| `db_engine_version` | `16` | |
| `db_name`, `db_username` | `campushub`, `campushub_admin` | |
| `enable_rds_proxy` | `false` | About $22/month; changes only the Lambdas' database URL |
| `cognito_domain_prefix` | `""` | Empty uses `campushub-<environment>-<account id>` |
| `additional_callback_urls` | `[]` | Add `https://<cloudfront_domain_name>/` after the first apply |
| `lambda_memory_size` | `512` | MB, for 4 of the 5 functions |
| `community_events_memory_size` | `1024` | MB; this function also handles everything else |
| `tesseract_layer_zip` | `""` | Optional OCR layer for reading mess menus (see section 8) |
| `ml_layer_zip` | `""` | Optional category-suggestion model layer |
| `throttling_rate_limit`, `throttling_burst_limit` | `1000`, `2000` | API Gateway stage throttling |
| `cognito_threat_protection` | `false` | Cognito threat protection in ENFORCED mode; needs the Plus feature plan, billed per monthly active user |
| `enable_web_push` | `true` | Push-sender Lambda outside the VPC plus a Lambda VPC endpoint (about USD 0.01 per hour per AZ). Run `scripts/create_vapid_keys.sh` once, or push stays off |

## 7. Outputs

| Output | Use |
|---|---|
| `app_url`, `frontend_url`, `cloudfront_domain_name` | The site, for example `https://dxxxx.cloudfront.net` |
| `cloudfront_distribution_id` | Cache invalidations |
| `api_endpoint` | API Gateway URL (bypasses CloudFront and its cache) |
| `cognito_user_pool_id`, `cognito_client_id`, `cognito_hosted_ui_domain` | Frontend build flags, CLI user management |
| `database_endpoint`, `database_connect_host`, `database_name`, `database_password_ssm_parameter` | Database access |
| `rds_proxy_enabled` | Whether RDS Proxy is on |
| `redis_primary_endpoint` | Redis host (reachable only inside the VPC) |
| `frontend_s3_bucket`, `media_s3_bucket` | Buckets |
| `lambda_functions` | The 5 API function names |
| `data_tools_function_name` | Used by the snapshot scripts |
| `cost_guardrail_budget` | Budget name |

## 8. Build artifacts

| Artifact | Built by | Required |
|---|---|---|
| Lambda zip | `modules/compute/build_lambda_zip.sh`, run automatically by `terraform apply` from `backend/requirements-lambda-zip.txt` and `backend/app`. Needs `pip3` | Yes |
| `modules/data_tools/pg_layer/pg-layer.zip` | `modules/data_tools/pg_layer/build.sh` (Docker, a few minutes) | Yes. Terraform fails without it |
| Tesseract layer | `modules/compute/tesseract_layer/build.sh` (Docker, 30 to 60 minutes on an ARM Mac), then set `tesseract_layer_zip` | No. Without it, mess menus cannot be read from uploaded files |
| ML layer | `modules/compute/ml_layer/build.sh`, then set `ml_layer_zip` | No. Without it, category suggestion returns nothing |

The Lambda zip leaves out onnxruntime, numpy, tokenizers, Pillow and pypdfium2 to stay under Lambda's
250 MB limit. The features that need them degrade without errors (see the header of
`backend/requirements-lambda-zip.txt`).

## 9. Helper scripts

Run them from `terraform/` after `terraform apply`. They read everything they need from
`terraform output`.

| Script | Does |
|---|---|
| `scripts/deploy_frontend.sh` | Builds Flutter for this stack, syncs it to the frontend bucket, sets `Cache-Control: no-cache` on the entry files, invalidates CloudFront |
| `scripts/create_vapid_keys.sh` | Once per environment: creates the Web Push (VAPID) key pair in SSM (`/campushub/<env>/push/`). Keeps existing keys. Needs `python3` with `cryptography` (the backend venv has it) |
| `scripts/snapshot_export.sh` | Writes `data/snapshot/` (database dump, media files, `MANIFEST.txt`) |
| `scripts/snapshot_restore.sh` | Restores `data/snapshot/` into this stack. Refuses if tables exist, unless `FORCE=1` |
| `scripts/deactivate_missing_cognito_users.sh` | After a restore: deactivates users with no account in this Cognito pool (dry run without `--apply`; the admin is never touched) |

Don't have the team's real snapshot? `data/mock-snapshot/` is committed to the repo and has the same
schema but fully synthetic data (no admin user, no real people). Copy it into `data/snapshot/` and run
`snapshot_restore.sh` as usual — see the root [readme.md, 5.7](../readme.md#57-load-the-database) for
details and for how to create your own first admin afterwards.

The data-tools Lambda also takes these payloads directly:

```json
{"action": "counts"}
{"action": "export"}
{"action": "restore", "key": "_snapshots/x.dump", "force": false}
{"action": "migrate", "sql": "<contents of a .sql file>"}
```

## 10. Troubleshooting

Errors seen while deploying this stack, and their fixes.

| Symptom | Cause | Fix |
|---|---|---|
| `terraform init`: 403 on `HeadObject` for the state bucket | `versions.tf` names a bucket in another account | `terraform init -reconfigure -backend-config="bucket=<yours>"` |
| `filemd5 ... pg_layer/pg-layer.zip: no such file` | Layer not built | Run `modules/data_tools/pg_layer/build.sh` |
| `build_lambda_zip.sh: no pip/pip3 on PATH` | Python missing | Install Python 3 with pip |
| CloudFront `AccessDenied` on create | Account not yet verified for CloudFront | Ask AWS support, or set `enable_cloudfront = false` for now (no HTTPS, so Cognito sign-in will not work) |
| ElastiCache `Invalid AuthToken provided` | The token used characters ElastiCache rejects | Fixed on this branch (commit `1601629`): only `! & # $ ^ < > -` are used |
| API returns 500 and the logs show `relation "listings" does not exist` | New, empty database | Load the schema or restore a snapshot ([root README 5.7](../readme.md#57-load-the-database)) |
| Cognito Hosted UI shows `redirect_mismatch` | The site URL is not a callback URL | Add it to `additional_callback_urls` and apply |
| Cognito callback refused for an `http://` S3 website URL | Cognito accepts HTTPS callbacks only (except localhost) | Serve the site through CloudFront |
| Every plan shows CloudFront `minimum_protocol_version` and RDS `rds.force_ssl` updates | Provider quirks; the default certificate always reports `TLSv1` | Harmless, apply or ignore |

Lambda logs: `aws logs tail /aws/lambda/campushub-dev-<function> --since 15m`.

Older errors from the first Lambda deployment are in
[docs/deployment errors resolution.md](../docs/deployment%20errors%20resolution.md).
