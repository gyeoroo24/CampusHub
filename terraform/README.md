# CampusHub infrastructure (Terraform, EC2 baseline)

This folder deploys the EC2 baseline in `ap-south-1`: CloudFront, an Application Load Balancer, an EC2
Auto Scaling group, RDS PostgreSQL, ElastiCache Redis, S3, Cognito and monitoring. The step-by-step
deploy guide is in the [root README](../README.md#5-deploy-to-aws). This file is the reference.

The serverless stack is on the `fix/cloud-deploy-zip-and-routes` branch, with its own
`terraform/README.md`.

## Table of contents

1. [Layout](#1-layout)
2. [Modules](#2-modules)
3. [The EC2 tier](#3-the-ec2-tier)
4. [Caching](#4-caching)
5. [Network and security](#5-network-and-security)
6. [Remote state](#6-remote-state)
7. [Variables](#7-variables)
8. [Outputs](#8-outputs)
9. [Build artifacts](#9-build-artifacts)
10. [Helper scripts](#10-helper-scripts)
11. [Troubleshooting](#11-troubleshooting)

## 1. Layout

```
terraform/
├── main.tf            Root composition
├── variables.tf       Root variables (toggles, sizes, ASG settings, alert email)
├── outputs.tf         URLs, IDs and endpoints
├── providers.tf       AWS provider for ap-south-1, plus a us-east-1 alias (WAF for CloudFront)
├── versions.tf        Terraform >= 1.5, provider versions, S3 backend (key campushub/baseline/...)
├── bootstrap/         One-time: S3 state bucket and DynamoDB lock table
├── modules/           One folder per tier (see below)
├── scripts/           deploy_frontend.sh, snapshot_export.sh, snapshot_restore.sh
└── tests/             smoke_test.py, test_permission_matrix.py (out of date, see Troubleshooting)
```

## 2. Modules

| Module | Used | Creates |
|---|---|---|
| `networking` | yes | VPC `10.0.0.0/16`; public subnets `10.0.1-3.0/24` (ALB) with an internet gateway; app subnets `10.0.4-6.0/24` (instances); database subnets `10.0.10-12.0/24`; security groups; S3 gateway endpoint; interface endpoints for SSM, KMS and Secrets Manager (no Cognito endpoint, see section 5) |
| `database` | yes | RDS PostgreSQL 16 (`db.t4g.micro`, 20 GB gp3, `rds.force_ssl=1`), password in Secrets Manager and SSM |
| `elasticache` | yes | Redis 7.1 (`cache.t3.micro`), TLS, encryption at rest, AUTH token in Secrets Manager |
| `storage` | yes | Frontend bucket (CloudFront OAC) and media bucket (uploads and `_deploy/backend.zip`) |
| `auth` | yes | Cognito user pool, app client (code flow with PKCE), Hosted UI domain, 4 groups |
| `compute_ec2` | yes | IAM instance profile, ALB, target group, listener, launch template, Auto Scaling group, target-tracking policy, the backend zip upload |
| `cdn` | yes | CloudFront with two origins (S3 frontend, ALB over HTTP), SPA rewrite function, API cache policy |
| `waf` | optional | WAFv2 web ACL (`enable_waf`) |
| `monitoring` | yes | SNS email, AWS Budgets guardrail, alarms for RDS CPU and ALB target 5XX (the module's Lambda and API Gateway alarms are not created here) |
| `data_tools` | yes | Lambda with `pg_dump`, `pg_restore` and `psql` in the VPC |
| `compute`, `api_gateway` | **no** | Serverless modules kept from the other branch; `main.tf` does not call them |

## 3. The EC2 tier

| Setting | Value |
|---|---|
| AMI | Latest Amazon Linux 2023 (arm64 for `t4g.*`, x86_64 otherwise) |
| Instance type | `ec2_instance_type`, default `t4g.micro` |
| Root volume | 20 GB |
| Auto Scaling | min `asg_min_size` (3), desired `asg_desired_capacity` (3), max `asg_max_size` (5) |
| Scaling policies | Target tracking on average CPU at `asg_target_cpu_utilization` (60 %) and on ALB requests per instance at `asg_target_requests_per_instance` (200); the ASG follows whichever needs more instances |
| Health check | ELB: `GET /api/v1/health` on port 8000, expects 200 |
| Process | `campushub.service`: uvicorn, 2 workers, port 8000, restarts on failure |
| DB pool | `ec2_db_pool_max_size` (16) per uvicorn worker, so up to 32 per instance |
| Shell access | SSM Session Manager (policy attached); no SSH, port 22 closed |

The user data steps are listed in the [root README](../README.md#2-ec2-baseline-architecture-this-branch).
Changing anything under `backend/` re-uploads `backend.zip` on the next apply, but **running instances
do not pick it up**. Start an instance refresh (or terminate instances) so new ones boot with the new
package:

```bash
aws autoscaling start-instance-refresh --auto-scaling-group-name "$(terraform output -raw asg_name)"
```

## 4. Caching

| Layer | Where | What | TTL |
|---|---|---|---|
| CloudFront static | `default_cache_behavior` | Flutter web files from S3 | Managed `CachingOptimized` |
| CloudFront API | `modules/cdn`, `aws_cloudfront_cache_policy.api_short_ttl` | GET/HEAD on 11 list paths: `listings`, `lost-reports`, `found-reports`, `wanted`, `events`, `event-tags`, `departments`, `courses`, `messes`, `companies`, `placement/stats` | 20 s default, 60 s max |
| Redis | `modules/elasticache`, `backend/app/cache.py` | 7 of those queries (`listings`, `lost-reports`, `found-reports`, `events`, `departments`, `courses`, `messes`), per viewer | 20 s |

The cache key includes `Authorization` and the query string, so users never share a response. Writes
are never cached, other `/api/*` paths use `CachingDisabled`, and there is no distribution-wide
`custom_error_response` (a 403 rewrite used to hide real API errors).

## 5. Network and security

- CloudFront reaches the ALB over HTTP on port 80 and adds an `X-Origin-Verify` header
  (`origin_verify_header`).
- **That header is not checked.** The ALB security group allows 80/443 from anywhere, the listener
  forwards every request, and the backend does not read `CAMPUSHUB_ORIGIN_VERIFY_SECRET`. The ALB can
  be called directly, bypassing CloudFront and WAF. Enforce it with an ALB listener rule that forwards
  only when the header matches (default action: fixed 403), or restrict the ALB security group to the
  CloudFront origin-facing prefix list.
- Instances accept port 8000 only from the ALB security group. RDS (5432) and Redis (6379) accept
  connections only from the app security group.
- The app subnets route outbound traffic through the internet gateway (PyPI, Cognito). Interface
  endpoints exist for Secrets Manager, SSM and KMS. There is deliberately no Cognito endpoint: AWS
  blocks `AdminGetUser` over PrivateLink for a user pool with a Hosted UI domain, so Cognito is reached
  through the internet gateway.
- The instance role can read the database and Redis secrets, the media bucket, and write CloudWatch
  logs.

## 6. Remote state

`bootstrap/` creates `campushub-tfstate-<random>` and `campushub-tf-locks`. `versions.tf` hardcodes a
team member's bucket and uses `use_lockfile = true`. Override the bucket at init time:

```bash
terraform init -backend-config="bucket=campushub-tfstate-<yours>"
```

The key is `campushub/baseline/terraform.tfstate`, so this stack and the serverless one can share a
bucket.

## 7. Variables

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `ap-south-1` | |
| `environment` | `baseline` | Part of every resource name |
| `alert_email` | a team member's address | **Change this** |
| `monthly_budget_usd` | `50.0` | |
| `enable_cloudfront` | `true` | Needed for HTTPS, Cognito sign-in, the edge cache and `deploy_frontend.sh` |
| `enable_waf` | `false` | |
| `enable_elasticache` | `true` | **Set `false` until the AUTH-token fix is applied** (see Troubleshooting) |
| `redis_node_type`, `redis_num_cache_clusters` | `cache.t3.micro`, `1` | |
| `multi_az_db` | `true` | `false` for a single-AZ, free-tier database |
| `db_instance_class`, `db_allocated_storage`, `db_engine_version` | `db.t4g.micro`, `20`, `16` | |
| `db_name`, `db_username` | `campushub`, `campushub_admin` | |
| `cognito_domain_prefix` | `""` | Empty uses `campushub-<environment>-<account id>` |
| `additional_callback_urls` | `[]` | Add `https://<cloudfront_domain_name>/` after the first apply |
| `ec2_instance_type` | `t4g.micro` | `t4g.*` is arm64; the Tesseract build must match |
| `asg_min_size`, `asg_desired_capacity`, `asg_max_size` | `3`, `3`, `5` | 3 always-on instances is past the free tier |
| `asg_target_cpu_utilization` | `60` | Percent |
| `asg_target_requests_per_instance` | `200` | ALB requests per instance |
| `ec2_db_pool_max_size` | `16` | Connections per uvicorn worker (2 workers per instance) |
| `origin_verify_header` | `CampusHub-Origin-Auth-Baseline` | Sent by CloudFront; not enforced (section 5) |
| `tesseract_layer_zip` | `""` | Optional OCR zip for the instances (section 9) |
| `ml_models_zip` | `""` | Optional zip of `backend/models` (category suggestion, sentiment) |
| `lambda_memory_size`, `community_events_memory_size`, `throttling_rate_limit`, `throttling_burst_limit`, `ml_layer_zip` | | Declared but unused on this branch |

## 8. Outputs

| Output | Use |
|---|---|
| `app_url`, `frontend_url`, `cloudfront_domain_name` | The site |
| `api_endpoint` | `<app_url>/api` |
| `alb_dns_name` | The ALB directly (HTTP), useful for load tests |
| `asg_name`, `target_group_arn` | Instance refresh, target health |
| `cloudfront_distribution_id` | Cache invalidations |
| `cognito_user_pool_id`, `cognito_client_id`, `cognito_hosted_ui_domain` | Frontend build flags |
| `database_endpoint`, `database_name`, `database_password_ssm_parameter` | Database access |
| `frontend_s3_bucket`, `media_s3_bucket` | Buckets |
| `data_tools_function_name` | Snapshot scripts |
| `cost_guardrail_budget` | Budget name |

## 9. Build artifacts

| Artifact | Built by | Required |
|---|---|---|
| `backend.zip` | Terraform (`archive_file` over `backend/`), uploaded to `_deploy/` in the media bucket | Yes, automatic |
| `modules/data_tools/pg_layer/pg-layer.zip` | `modules/data_tools/pg_layer/build.sh` (Docker) | Yes |
| Tesseract for EC2 | `modules/compute_ec2/tesseract_build/build.sh` (arm64 by default, `--platform linux/amd64` for `t3.*`), then set `tesseract_layer_zip` | No |
| ONNX models | `backend/scripts/fetch_match_models.py --suggest-only`, zip `backend/models`, then set `ml_models_zip` | No |

The `tesseract_layer_zip` description in `variables.tf` points at the Lambda layer build; on this branch
use the EC2 build above, which matches the AMI and CPU architecture.

## 10. Helper scripts

Run them from `terraform/` after `terraform apply`.

| Script | Does |
|---|---|
| `scripts/deploy_frontend.sh` | Builds Flutter for this stack, syncs to S3, invalidates CloudFront. Needs CloudFront |
| `scripts/snapshot_export.sh` | Writes `data/snapshot/` (dump, media files, manifest) |
| `scripts/snapshot_restore.sh` | Restores `data/snapshot/`. This stack's instances create an empty schema at boot, so use `FORCE=1` after checking the tables are empty |

Data-tools payloads on this branch:

```json
{"action": "counts"}
{"action": "export"}
{"action": "restore", "key": "_snapshots/x.dump", "force": false}
{"action": "run_sql", "key": "_snapshots/x.sql"}
```

`run_sql` reads only from `_snapshots/`, because that is the only prefix its role can read.

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform init`: 403 or `NoSuchBucket` for the state bucket | `versions.tf` names another bucket | `terraform init -reconfigure -backend-config="bucket=<yours>"` |
| `filemd5 ... pg-layer.zip: no such file` | Layer not built | `modules/data_tools/pg_layer/build.sh` |
| ElastiCache `Invalid AuthToken provided` | `override_special` in `modules/elasticache/main.tf` allows characters ElastiCache rejects | Use `override_special = "!&#$^<>-"` (fixed on the serverless branch, commit `1601629`), or `enable_elasticache = false` |
| CloudFront `AccessDenied` on create | Account not yet verified for CloudFront | Ask AWS support. Without CloudFront there is no HTTPS, so Cognito sign-in will not work |
| ALB returns 502 everywhere, target `unhealthy` | The app did not start on the instance (for example a failed `pip install`) | `aws ec2 get-console-output --instance-id <id> --latest`, or `journalctl -u campushub` over SSM. The user data prints "Completed Successfully" even after a failure |
| `Inconsistent dependency lock file` on `apply <plan>` | Applied from another directory than the plan | Run `apply` in the directory where `plan` ran |
| `Error acquiring the state lock` | Overlapping runs | Retry; check for a `.tflock` object in the state bucket |
| Restore refuses: `the database already has N tables` | The first instance created the schema | Check the tables are empty, then `FORCE=1 ./scripts/snapshot_restore.sh` |
| Cognito `redirect_mismatch` | The site URL is not a callback URL | Add it to `additional_callback_urls` and apply |
| New backend code not live after apply | Running instances keep the old package | Start an instance refresh (section 3) |
| `tests/smoke_test.py` fails against a working stack | It calls `/api/<module>/...`, not `/api/v1/...` | Out of date; use the `curl` checks in the root README |

The full record of the first baseline deployment is in
[docs/baseline-ec2-deployment-log.md](../docs/baseline-ec2-deployment-log.md).
