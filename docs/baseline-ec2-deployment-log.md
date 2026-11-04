# Baseline EC2 deployment and data restore: errors and fixes

This log covers the `baseline-infra` deployment (EC2 Auto Scaling group behind an ALB, S3 website,
Cognito, RDS) and the restore of the team's snapshot, from 4 to 5 November 2026. It also records
local-development problems hit on the way. The older log for the Lambda deployment is
[deployment errors resolution.md](deployment%20errors%20resolution.md).

Secret values (passwords, keys, the database password) are deliberately not written here.

## Status at a glance

| # | Area | Symptom | Status |
|---|---|---|---|
| A1 | AWS | CloudFront `AccessDenied` on create | Open: waiting for AWS support to verify the account |
| A2 | Terraform | Backend bucket in `versions.tf` does not exist | Worked around with `-backend-config`; repo still needs fixing |
| A3 | EC2 | ALB returns 502 for every path | Fixed (numpy pin), broken instance replaced |
| A4 | EC2 | User data prints "Completed Successfully" after a failed install | Open |
| A5 | S3 | Website returns 404 | Fixed by a manual build and sync; `deploy_frontend.sh` still assumes CloudFront |
| A6 | Terraform | `Error acquiring the state lock` on the first apply | Resolved by a retry; cause not confirmed |
| A7 | Terraform | `Inconsistent dependency lock file` on a saved plan | Resolved: run apply from the same directory as the plan |
| A8 | Cognito | `redirect_mismatch` on sign-in from the S3 site | Open: needs HTTPS (CloudFront) |
| A9 | AWS | Deployments use the account root user | Open |
| D1 | Snapshot | `Operation not permitted` reading `~/Downloads` | Resolved: copied the folder out |
| D2 | Snapshot | Manifest has no code commit line | Matched to `f923372` (schema revision 24); manifest not yet updated |
| D3 | Restore | Restore scripts need an output that the stack did not create | Fixed: `data_tools` module wired, `run_sql` action added |
| D4 | Restore | PostgreSQL layer needs Docker | Fixed: Docker started, layer built |
| D5 | Restore | Dump is revision 24, deployed code is revision 25 | Fixed: migration 025 applied with `run_sql` |
| D6 | Restore | Target database already has tables | Resolved: all tables were empty, so `FORCE=1` lost nothing |
| D7 | Restore | Five `.DS_Store` files copied into the media bucket | Open: cleanup needs approval |
| L1 | Local | Old Placement Hub pages | Fixed: web build rebuilt from current source |
| L2 | Local | Deep links 404 on reload | Fixed: `frontend/tool/serve_web.py` |
| L3 | Local | API port busy, launch config failed | Fixed: absolute path in `launch.json` |
| L4 | Local | Sign-in code | Temporary bypass, uncommitted |
| L5 | Local | Only one admin allowed | Local database handover done |
| G1 | Git | Test password committed in `terraform/README.md` | Open |

## AWS deployment

### A1. CloudFront `AccessDenied` on create

**Symptom:** `terraform apply` failed creating `module.cdn[0].aws_cloudfront_distribution.distribution`
with a 403 `AccessDenied`: the account must be verified before CloudFront resources can be added.

**Cause:** the AWS account is not yet verified for CloudFront.

**Fix:** `enable_cloudfront = false` in `terraform.tfvars`. The `cdn` module is gated by that flag, and
S3 public access is then allowed. AWS support has a ticket open for verification.

**Still open:** the frontend is served from the S3 website endpoint, which is HTTP only (see A8).

### A2. Backend bucket name in `versions.tf` does not exist

**Symptom:** `terraform init` would point at `campushub-tfstate-4a2783e6`, which is not in the account.

**Cause:** the bootstrap stack generates a random suffix for the state bucket. The name hardcoded in
`versions.tf` came from a different run.

**Fix:** the real state bucket is `campushub-tfstate-5402a26e` (key `campushub/baseline/terraform.tfstate`,
region `ap-south-1`). Every init in this session used
`-backend-config="bucket=campushub-tfstate-5402a26e"`, so the repo was not changed.

**Still open:** update `versions.tf` to the real bucket name.

### A3. ALB returns 502 for every path (numpy has no Python 3.11 wheel)

**Symptom:** `http://<alb>/` and `/api/v1/health` both returned `502 Bad Gateway`. The target group
showed the instance as `unhealthy` with `Health checks failed`, while the Auto Scaling group reported
it healthy.

**Cause:** `backend/requirements.txt` pinned `numpy==2.5.4`, which only has a `cp312` wheel. The EC2
image runs Python 3.11 (`python3.11` in the user-data script), so `pip install -r` failed with
`No matching distribution found for numpy==2.5.4`. The script ran that step with `|| true`, so the
failure was ignored. The matching modules import numpy at startup, so uvicorn never started and the
health check failed.

**Fix:** pin `numpy==2.4.6`, which has a `cp311` wheel (commit `a543230` on `baseline-infra`). Ran
`terraform apply`, which re-uploaded `_deploy/backend.zip` with the new requirements. Terminated the
broken instance (`i-02cb8176718f8c81a`) with `--no-should-decrement-desired-capacity`, so the Auto
Scaling group launched a replacement from the updated package. The replacement became healthy about
8 minutes after termination. `/api/v1/health`, `/api/v1/placement/stats` and `/api/v1/events` now return 200.

**Lesson:** the instance's boot log (`aws ec2 get-console-output`) showed the failure clearly.
Check it first.

### A4. User data reports success after a failed install

**Symptom:** the boot log ends with `=== CampusHub EC2 Baseline User Data Completed Successfully ===`,
even though the pip install failed and the health check timed out.

**Cause:** `set -e` is not set, `pip install -r ... || true` swallows the error, and the health-check
loop does not exit non-zero.

**Fix:** not made. Remove `|| true` for the requirements install, add `set -euo pipefail`, and make the
script exit non-zero when the health check fails, so the failure is visible in the instance state.

### A5. S3 website returns 404

**Symptom:** the S3 website endpoint returned 404 with no page.

**Cause:** the frontend bucket was empty. `deploy_frontend.sh` builds and syncs the app, but it reads its
settings from CloudFront outputs, which do not exist while CloudFront is disabled.

**Fix:** built the Flutter web app with `USE_MOCK=false`, `API_BASE_URL=http://<alb dns>` (the ALB root,
since the app adds `/api/v1` itself), and the Cognito domain and client ID from `terraform output`.
Synced `build/web` to the bucket with `aws s3 sync --delete`. The bucket now has the same 39 files and
the same `main.dart.js` hash as the local build. The site loads and shows the Buy & Sell page. Lists
are empty until the restore below.

**Still open:** `deploy_frontend.sh` should support a non-CloudFront mode, or the S3 build path should be
documented.

### A6. `Error acquiring the state lock` on the first apply

**Symptom:** the first apply of the saved plan stopped with a state-lock error. A second attempt with the
same plan file succeeded (`Apply complete! Resources: 0 added, 2 changed, 0 destroyed`).

**Cause:** not confirmed. The lock was not left behind (no `.tflock` object existed afterwards). The
likely cause is overlapping runs, but this was not checked.

**Fix:** retried. Check the lock object in the state bucket if this happens again.

### A7. `Inconsistent dependency lock file` on a saved plan

**Symptom:** `terraform apply <planfile>` reported the providers as "required by this configuration but
no version is selected".

**Cause:** the command ran from a directory whose configuration did not match the plan. The plan was made
in `~/.cache/ch-restore/terraform`.

**Fix:** run the apply from the same directory as the plan:

```bash
cd ~/.cache/ch-restore/terraform && terraform apply ~/.cache/ch-restore/restore.tfplan
```

### A8. Cognito `redirect_mismatch` on sign-in

**Symptom:** the Cognito Hosted UI page shows `redirect_mismatch` after the sign-in button.

**Cause:** two problems. First, the S3 website's own address was not in the Cognito app client's callback
URLs (`http://localhost:3000/`, `http://localhost:8080/` and the Postman callback were). Second, Cognito
accepts only HTTPS callback URLs, except `localhost`. The S3 website endpoint is HTTP only, so it cannot
be added as a callback.

**Fix:** not possible until the site is served over HTTPS. Options: enable CloudFront (A1), which
gives an HTTPS address to add to `additional_callback_urls`; run the web app locally on port 8080 and
sign in there (Cognito already allows `localhost:8080`); or add an HTTPS domain in front of the ALB.

**Still open:** waiting for CloudFront.

### A9. Deployments run with the root account

**Symptom:** the AWS CLI identity is `arn:aws:iam::<account>:root`.

**Cause:** the access keys in `~/.aws/credentials` belong to the root user.

**Fix:** not made. Create an IAM user (or role) with administrator access for deployments, use its keys,
and rotate or delete the root access keys.

## Data restore

### D1. `Operation not permitted` reading `~/Downloads`

**Symptom:** `ls`, `cat` and the file reader all failed on `~/Downloads/snapshot.zip` and then the
unzipped `snapshot/` folder with `Operation not permitted`.

**Cause:** macOS privacy protection blocks the agent's process from `~/Downloads`.

**Fix:** the user copied the folder with `cp -R ~/Downloads/snapshot ~/Desktop/cloud_computing/snapshot-import`,
which lives outside the git repo.

### D2. Manifest has no code commit line

**Symptom:** `docs/restoring the data snapshot.md` says the manifest's `code commit` line identifies the
commit to check out, but `MANIFEST.txt` has no such line.

**Cause:** the manifest was written by an export before that line existed.

**Fix:** matched the dump to the repo's history. `pg_restore -l` lists 55 tables, and that set matches
`backend/db/schema.sql` exactly at commit `f923372` (2026-11-03, schema revision 24). The next commit,
`35d4cbd`, adds three columns (`companies.created_by`, `lost_reports.title`, `found_reports.title`), and
the dump does not have them. The export time (21:21 UTC, 3 November) falls between the two commits.

**Still open:** add `code commit: f923372` to the manifest.

### D3. Restore scripts need an output the stack did not create

**Symptom:** `snapshot_restore.sh` and `snapshot_export.sh` read `terraform output -raw
data_tools_function_name`, which failed.

**Cause:** `modules/data_tools` existed but the root `main.tf` never called it, so there was no output.

**Fix:** added `module "data_tools"` to `terraform/main.tf` and a root output `data_tools_function_name`
in `outputs.tf`. The module's inputs come from the networking (`lambda_subnet_ids`,
`app_security_group_id`), database (`db_address`, `db_name`, `db_secret_arn`) and storage
(`media_bucket_id`, `media_bucket_arn`) modules. Applied: 7 added, 1 changed (the database parameter group,
`rds.force_ssl` moved from pending-reboot to immediate, same value), 0 destroyed. The function is
`campushub-baseline-data-tools`.

**Also added:** a `run_sql` action in `modules/data_tools/lambda_src/handler.py`. It runs a SQL file from
`_snapshots/` only, because that is the only prefix the function's IAM role can read. The restore did not
have a way to run migrations before this.

### D4. PostgreSQL layer needs Docker

**Symptom:** `pg_layer/build.sh` needs Docker, which was not running. The first build run exited after
pulling `amazonlinux:2`, and its log showed no error.

**Fix:** started Docker Desktop and reran the build. It exited 0 and wrote `pg-layer.zip` (2 MB), which
contains `pg_dump`, `pg_restore` and `psql` built from PostgreSQL 16.15. The cause of the first silent exit
was not identified.

### D5. Dump is schema revision 24, deployed code is revision 25

**Symptom:** the deployed code expects `companies.created_by` and `lost_reports.title`, which the dump
does not have.

**Cause:** the dump was taken before revision 25. The EC2 user data had already created revision-25 tables
at boot.

**Fix:** after the restore, ran `backend/db/migrations/025_company_created_by.sql` with `run_sql`. The
migration uses `BEGIN`/`COMMIT` and `IF NOT EXISTS`. It has run three times, each returning
`{"ran": "_snapshots/025.sql"}`, with no change on re-runs.

**Not verified:** the new columns were not queried directly, since the function can only run SQL files.
The app's company and Lost & Found pages still need checking.

### D6. Target database already had tables

**Symptom:** the restore script refused: `the database already has N tables; send force=true`.

**Cause:** the EC2 user data auto-creates the schema at boot.

**Fix:** before running with `FORCE=1`, counted every main table: all 0 rows. So the force restore only
replaced an empty schema.

### D7. Restore result, and five extra files in the media bucket

**Result:** the restored row counts match `MANIFEST.txt` exactly:

| Table | Manifest | Restored |
|---|---|---|
| users | 74 | 74 |
| listings | 89 | 89 |
| notifications | 563 | 563 |
| comments | 274 | 274 |
| threads | 61 | 61 |
| placement_records | 1071 | 1071 |
| course_feedback | 952 | 952 |
| events | 36 | 36 |
| mess_menus | 6 | 6 |
| moderation_log | 328 | 328 |

**Symptom:** the restore reported `uploads restored: 13 files`, but the manifest says `uploads: 8 files`.

**Cause:** the `uploads/` folder contains 5 macOS `.DS_Store` files, and `aws s3 sync` copied them.

**Open:** remove the five `.DS_Store` objects from `campushub-baseline-media-57393eba` after confirmation.

### D8. Agent commands blocked by the permission classifier

**Symptom:** `terraform apply` and `snapshot_restore.sh` were denied by the automatic permission
classifier when run by the assistant.

**Fix:** the user ran both commands in their own terminal. This is a workflow note, not a data problem.

## Local development

### L1. Old Placement Hub pages

**Symptom:** the Placement Hub on `http://localhost:8081` showed the older screens.

**Cause:** the web build in `frontend/build/web` was older than the source. Also `USE_MOCK` defaults to
`true`, so the build could show mock data.

**Fix:** rebuilt with `flutter build web --release --dart-define=USE_MOCK=false
--dart-define=API_BASE_URL=http://localhost:8000`. Browsers can still show an old copy: Flutter's service
worker caches the app, so a hard reload (Cmd+Shift+R) or clearing site data may be needed.

### L2. Deep links 404 on reload

**Symptom:** `/placements` returned 404 when opened directly.

**Cause:** `python3 -m http.server` has no fallback to `index.html`.

**Fix:** `frontend/tool/serve_web.py` (commit `47468f8`) serves the app and falls back to `index.html`.
The `campushub-web` entry in `.claude/launch.json` runs it.

### L3. API port busy and the launch config failed

**Symptom:** `campushub-api` failed with `CampusHub/backend/.venv/bin/uvicorn: No such file or directory`,
and then started on port 8002 when 8000 was taken.

**Cause:** the config used paths relative to the tool's working directory, and an old uvicorn was still
holding port 8000.

**Fix:** the `cd` in `.claude/launch.json` uses the absolute path. The old process was stopped.

### L4. Sign-in code is fixed to `123456` (local only)

**What:** `backend/app/routers/auth_otp.py` accepts `123456` on the sign-in verify route, so local sign-in
works when SMTP is not configured. It is marked `TEMP HARDCODED OTP`.

**Status:** uncommitted on `backend_v3`, and deliberately left out of every push.
`docs/cloud-deployment-checklist.md` says this code must never be committed or deployed, so keep it out
of the repo and remove it before any real deployment.

### L5. Only one admin allowed (local database)

**What:** the database enforces a single admin (`uq_users_single_admin`). The admin role was handed to
a team member's account in the local database, and the previous admin was demoted in the same transaction.

**Status:** local database only. The handover can be reversed with the SQL in the chat history.

## Git

### G1. Test-account password in `terraform/README.md`

**What:** the Cognito walkthrough in `terraform/README.md` (on `origin/main`, and in the merged history)
has a test-user password in the `sign-up` and `initiate-auth` examples.

**Fix:** not made. Replace it with a placeholder, change the test account's password, and rewrite the
history only if the team agrees.

## Open items

- A1: CloudFront verification (AWS support ticket).
- A2: set the real state bucket name in `versions.tf`.
- A4: fix the user-data script's error handling.
- A5: support a non-CloudFront mode in `deploy_frontend.sh`.
- A8: sign-in needs HTTPS (after A1).
- A9: switch deployments to an IAM user.
- D2: add `code commit: f923372` to `MANIFEST.txt`.
- D7: remove the five `.DS_Store` objects from the media bucket.
- G1: remove the test password from `terraform/README.md`.
- Check the `terraform/.terraform.lock.hcl` changes before committing anything in the worktree.
