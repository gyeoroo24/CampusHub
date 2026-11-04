# Deployment errors and resolutions

This log records problems hit while deploying CampusHub to AWS (branch
`fix/cloud-deploy-zip-and-routes`), their causes, and their fixes.

The "Codified?" column says whether the Terraform in this repo reproduces the fix on a fresh
`terraform apply`. Fixes that are not in code yet are listed under Open items. Secret values (keys,
passwords) are deliberately not written here.

## How to deploy (any AWS account)

1. `terraform init` and `terraform apply` in `terraform/`. Set `cognito_domain_prefix` to a
   name unique to your account (or leave it empty for `campushub-<env>-<account id>`).
2. Optional, for mess-menu reading: `terraform/modules/compute/tesseract_layer/build.sh` (needs
   Docker, 30-60 min on an ARM Mac), then set `tesseract_layer_zip` to the zip path in
   `terraform.tfvars`.
3. Copy the CloudFront domain from the outputs into `additional_callback_urls`
   (`["https://<cloudfront-domain>/"]`) and apply again, so Cognito allows the web app's redirect.
4. `terraform/scripts/deploy_frontend.sh` builds the web app with this account's API and Cognito
   settings and publishes it to S3 and CloudFront. Repeat it after every frontend change.
5. Load the database schema (see item 2 and 3 below). Terraform does not do this.

## Summary

| # | Symptom | Cause | Fix | Where | Codified? |
|---|---|---|---|---|---|
| 1 | Site shows `AccessDenied` | Frontend S3 bucket empty | Built web app with cloud defines, synced to bucket, invalidated CloudFront | `terraform/scripts/deploy_frontend.sh` | Yes |
| 2 | Buy & Sell: status 500, `relation "listings" does not exist` | RDS had no tables | Ran `db/schema.sql` and `db/reference-data.sql` via a temporary VPC Lambda | Temporary Lambda (deleted) | No |
| 3 | Cloud needed the local `campushub` data | Cloud schema was empty | Replaced cloud schema with a dump of `campushub` via a temporary VPC Lambda, one transaction | Temporary Lambda (deleted) | No |
| 4 | Email-code dialog shown; API returns 404 "signs in through Cognito" | App used local OTP flow | Hosted UI sign-in (authorization code + PKCE) enabled by build-time defines | Frontend code + `deploy_frontend.sh` | Partly (frontend code not committed) |
| 5 | Cognito sign-in works but app stays signed out | Repository rebuilt on startup; code exchanged twice; profile never loaded | One shared exchange per code; capture redirect URL before router; load `/me` after exchange | Code (uncommitted) | No |
| 6 | No Create-account button; sign-out leaves Cognito session | Missing `/signup` and `/logout` calls | "Create account" opens `/signup`; sign-out calls `/logout` | Code (uncommitted) | No |
| 7 | Cognito rejects the app's redirect | Callback and logout URLs listed only localhost | Added the CloudFront URL; created Hosted UI domain | `modules/auth` (`cognito_domain_prefix`, `additional_callback_urls`) | Yes |
| 8 | Photo and mess-menu uploads: network error | Upload URL signed for global S3 host; S3 redirects (307); browsers don't follow on cross-origin PUT | `CAMPUSHUB_S3_ENDPOINT_URL` set to the regional S3 host on the API Lambdas | `modules/compute/main.tf` | Yes |
| 9 | Uploads: 403 | Lambda role lacked `s3:PutObjectTagging` (upload tickets carry a tag) | Added `s3:PutObjectTagging` and `s3:GetObjectTagging` | `modules/compute/iam.tf` | Yes |
| 10 | Menu reader: "isn't set up on this server" | numpy, Pillow, pypdfium2 and `tesseract` not in Lambda package | Tesseract layer attached to the events function; memory 1024 MB; `TESSDATA_PREFIX` | `modules/compute/tesseract_layer/` + `modules/compute/main.tf` (optional via `tesseract_layer_zip`) | Yes (layer optional) |
| 11 | C mess menu: header not found | Layer v1 used Tesseract 5.3.4 and unpinned packages | Rebuilt layer: Tesseract 5.5.3, leptonica 1.87.0, numpy 2.2.6, Pillow 12.2.0, pypdfium2 5.14.0 | `modules/compute/tesseract_layer/inside.sh` | Yes |
| 12 | Dev sign-in not possible on Lambda | `backend/app/main.py` refuses dev mode in Lambda, by design | Not changed | — | — |
| 13 | Textract unusable | `SubscriptionRequiredException`: not enabled on the account | Not used; Tesseract layer chosen | — | — |
| 14 | Menu reader takes ~15 s per menu | One `tesseract` process per cell, each reloading the language model | libtesseract called in-process (`ctypes`); engines kept and reused; orientation on an `osd` engine | `backend/app/mess_extract.py` | Code (uncommitted; no Terraform change) |

## Details

### 1. Frontend bucket empty
- CloudFront's default origin is the private bucket `campushub-dev-frontend-ee248345`, which had no
  files, so `index.html` was missing.
- Fix: `flutter build web --release` with `USE_MOCK=false` and `API_BASE_URL` set to the CloudFront
  URL; `aws s3 sync build/web s3://<frontend bucket>/ --delete`; `aws cloudfront create-invalidation`
  for `/*` on the distribution.
- Repeat on every release. Not automated.

### 2 and 3. Database
- The RDS instance is private, so it can't be reached from a laptop. A temporary Lambda in the same
  subnets and security group (which the database already allows on port 5432) ran the SQL.
- Fix 2: schema and reference data, in `psycopg2`. Refuses if `users` already has rows.
- Fix 3: the local `campushub` database was dumped as `--section=pre-data`, `--section=data --inserts`
  and `--section=post-data`. A first attempt that included `DISABLE TRIGGER ALL` failed, because it
  needs superuser. The successful load ran all three sections in one transaction.
- The temporary function and its role were deleted after each use.
- The cloud database now holds the `backend_v2` schema and data. Check that the schema matches the
  code on the deploy branch before deploying again.

### 4 to 6. Sign-in (code, uncommitted in `CampusHub-cloud-web`)
- `frontend/lib/features/auth/data/cognito_hosted_ui.dart` (new): authorization code + PKCE, sign-up
  (`/signup`), logout (`/logout`), token refresh. Exchanges are shared across repository instances
  (a static map keyed by code), so a second instance does not spend the one-time verifier.
- `frontend/lib/main.dart`: captures `Uri.base` before the router. The router turns `/?code=...`
  into `/buy` and drops the query string.
- `frontend/lib/features/auth/data/auth_repository.dart`: after a successful exchange, `_init` calls
  `getCurrentUser()` so `/me` is loaded. This was missing and caused the signed-out state.
- `frontend/lib/features/auth/ui/auth_dialog.dart`: "Create account" and "Sign in" when Cognito is
  configured.
- `frontend/lib/core/constants/app_config.dart`: `cognitoDomain` and `cognitoClientId` from
  `--dart-define`; `cognitoEnabled` is true only when both are set.
- Cloud build needs `COGNITO_DOMAIN` and `COGNITO_CLIENT_ID` defines (values in the Cognito console).
  Without them, the app uses the local OTP dialog.

### 7. Cognito domain and callback URLs
- Created the Hosted UI domain `campushub-dev-iisc` on the user pool.
- Added the CloudFront URL to the app client's callback and logout URLs.
- Caution: `update-user-pool-client` resets any setting not passed in. Copy the full current
  configuration first, then change only the URL lists.
- Not in Terraform: `auth` module needs the domain and the URL lists.

### 8 and 9. Photo and mess-menu upload
- Symptom 8: `XMLHttpRequest onError` on the PUT. Cause: the URL was signed for the global host; S3
  answered 307 to the regional host, and browsers don't follow that for cross-origin PUTs. Bucket CORS
  was already open (`AllowedOrigins *`).
- Fix 8: `CAMPUSHUB_S3_ENDPOINT_URL=https://s3.ap-south-1.amazonaws.com` on `campushub-dev-buy-sell`,
  `campushub-dev-lost-found`, `campushub-dev-academic-hub`, `campushub-dev-placement-hub` and
  `campushub-dev-community-events`.
- Symptom 9: 403 after 8. Cause: the upload ticket includes `x-amz-tagging: state=pending`, and the
  role had no `s3:PutObjectTagging`.
- Fix 9: new default version `v2` of `campushub-dev-lambda-app-permissions`, adding the two tagging
  actions to the media-bucket statement. IAM simulator confirms both are allowed.
- Not in Terraform: `terraform/modules/compute/iam.tf` lists only four S3 actions;
  `terraform/modules/compute/main.tf` has no regional endpoint variable.

### 10 and 11. Mess-menu reader (Tesseract layer)
- Symptom 10: "Reading menus from files isn't set up on this server". The reader's built-in fallback,
  triggered because numpy, Pillow, pypdfium2 and `tesseract` are missing from the Lambda package.
  `backend/Dockerfile.lambda` already notes that a Tesseract layer is needed.
- Build: Amazon Linux 2023 container (`--platform linux/amd64`), leptonica and Tesseract compiled from
  source, language data copied in, Python packages installed to `/opt/python`, shared libraries
  collected with `ldd` into `/opt/lib`, unneeded files removed (training tools, `.la`, cmake, pkgconfig,
  tests, `*.dist-info`).
- Zip with `zip -ry`. The `-y` flag is needed: without it symlinked libraries are stored twice and the
  unzipped size exceeds Lambda's 250 MB limit.
- Upload: the zip is over the 50 MB direct limit, so it was staged in a temporary private S3 bucket,
  published as a layer, and the bucket was deleted.
- Attached: `campushub-tesseract` version 2 to `campushub-dev-community-events`; memory 512 → 1024 MB;
  `TESSDATA_PREFIX=/opt/share/tessdata`.
- Symptom 11: C mess menu: "Couldn't find the Breakfast / Lunch / Snacks / Dinner header".
  Cause: layer v1 used Tesseract 5.3.4 and unpinned packages. Local setup uses Tesseract 5.5.3,
  leptonica 1.87.0 and the project's pins. The pinned `numpy==2.5.4` needs Python 3.12+, but Lambda
  runs Python 3.11, so the layer uses numpy 2.2.6, Pillow 12.2.0 and pypdfium2 5.14.0.
- Verified in an Amazon Linux container with the layer mounted at `/opt`: C menu reads all 28 meals
  with no warnings. (About 93 s under emulation; not measured on Lambda.)
- Not in Terraform: the layer, its attachment, memory and the environment variable. The build script
  is in a session scratch folder and is not in the repo yet.

### 14. Mess-menu reader speed
- Symptom: about 15 s per menu in the cloud. The E menu needs about 67 Tesseract calls: one per cell, plus
  the title, notes and orientation check.
- Cause: each call started the `tesseract` program, which loaded `eng.traineddata` again. Loading the
  model took most of each call.
- Fix: `mess_extract.py` calls libtesseract in-process through `ctypes`. Engines are kept in a pool, so
  the model loads once per engine and is reused across cells and across requests while the Lambda is
  warm. Orientation runs on an engine started with `osd`: on an `eng` engine, libtesseract aborts the
  whole process. The `tesseract` program remains as a fallback when libtesseract isn't found.
- No Terraform change. The layer already holds `libtesseract.so.5` (the `tesseract` binary links it),
  and Lambda puts `/opt/lib` on the library path.
- Checked: the old and new readers gave the same result on the five sample menus (28 meals each, same
  notes, month, start date and warnings), and the same orientation for each sample at 0°, 90°, 180° and
  270°. On this Mac the E menu went from 2.4 s to 1.2 s.
- Deployed to `campushub-dev-community-events` (3008 MB, layer `campushub-tesseract:4`). Cloud timing:
  not yet measured at the time of writing.

### 12 and 13. Not resolved
- Dev sign-in on Lambda: refused by design in `backend/app/main.py`. Enabling it needs that check
  removed, which has not been done.
- Textract: `SubscriptionRequiredException`. Enabling Textract on the account is a console step.

## Open items

1. **Commit the frontend changes** under `frontend/lib/` on the deploy branch (auth files and
   `main.dart`). They are uncommitted in the `CampusHub-cloud-web` worktree, so
   `deploy_frontend.sh` builds them only on the machine that has them.
2. **Database schema and data.** Terraform doesn't load them. Decide between a one-off load
   (the temporary-Lambda method in items 2 and 3) and a migration job, and check the schema revision
   against the deploy branch's code.
3. **Remove the 123456 shortcut** from `backend/app/otp.py` on `backend_v2` (commit `7bce283`) before
   deploying from that branch. The local build's 123456 check is separate and only applies to the
   local build.
4. **Rotate the team dev key** that appears in git history, and the database password that was
   written into frontend code earlier.
5. **Dev sign-in on Lambda** (item 12) is refused by design. Enabling it means changing that check,
   which is a decision for the team.
6. **Textract** (item 13) needs enabling on the account before it can be used.
7. **Existing deployment:** Terraform does not know about the Cognito domain or the manually added
   layer and IAM version created earlier. Before applying, either import them
   (`terraform import`) or set `cognito_domain_prefix = "campushub-dev-iisc"` and check the plan for
   changes to the Lambda policy, environment and layers.
