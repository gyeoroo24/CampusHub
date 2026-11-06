# CampusHub web app (Flutter)

The CampusHub user interface, built with Flutter for the web. The same build runs against the local
FastAPI backend, the serverless AWS stack or the EC2 baseline (this branch). Only the build flags change.

## Table of contents

1. [Stack](#1-stack)
2. [Folder structure](#2-folder-structure)
3. [Build flags](#3-build-flags)
4. [Run locally](#4-run-locally)
5. [Sign-in](#5-sign-in)
6. [Build for AWS](#6-build-for-aws)
7. [Deploy](#7-deploy)
8. [Tests](#8-tests)
9. [Troubleshooting](#9-troubleshooting)

## 1. Stack

| Concern | Package |
|---|---|
| Language and SDK | Dart `^3.13.5`, Flutter stable |
| State management | `flutter_riverpod`, `riverpod_annotation` (code generation with `riverpod_generator`) |
| Routing | `go_router` |
| HTTP | `dio` |
| Token storage | `shared_preferences` |
| Opening the Cognito Hosted UI | `url_launcher` |

## 2. Folder structure

```
lib/
├── main.dart
├── core/                  Shared by every feature
│   ├── api/               ApiClient (Dio, auth header), endpoint paths, ApiException
│   ├── config/            ServerConfig (API URL and dev key, changeable at runtime by the admin)
│   ├── constants/         AppConfig: compile-time build flags (see section 3)
│   ├── router/            go_router routes
│   ├── storage/           Token storage
│   ├── services/          File uploads (presigned S3 URLs)
│   ├── models/, enums/    Shared data types
│   ├── theme/, widgets/   Look and shared UI components
│   └── utils/             Formatters, validators, file pickers, web history
└── features/              One folder per module
    ├── auth/  profile/  admin/  alerts/  messages/
    ├── buy_sell/  wanted/  seller_trust/  lost_found/
    ├── academics/  forums/  placement/  events/  mess/  campus_services/
test/                      Widget, data-layer and integration tests
web/                       index.html, manifest, icons
```

Each feature follows the same layout: `data/` (repositories that call the API), `domain/` (models),
`providers/` (Riverpod) and `ui/` (screens and widgets).

## 3. Build flags

Settings are compile-time `--dart-define` values, read in `lib/core/constants/app_config.dart`.

| Flag | Default | Meaning |
|---|---|---|
| `USE_MOCK` | `true` | `true` shows built-in mock data with no backend. **Set `false` for any real build** |
| `API_BASE_URL` | `http://localhost:8000` | Backend origin, without `/api/v1` (the app adds it). On AWS, the CloudFront URL |
| `COGNITO_DOMAIN` | `""` | Cognito Hosted UI host, without `https://` (output `cognito_hosted_ui_domain`) |
| `COGNITO_CLIENT_ID` | `""` | Cognito app client ID (output `cognito_client_id`) |
| `DEV_KEY` | `""` | Key for the backend's local dev sign-in |

Cognito sign-in is on only when both `COGNITO_DOMAIN` and `COGNITO_CLIENT_ID` are set. Otherwise the
app uses the backend's local email-code sign-in.

The admin's "server connection" screen can change the API URL for one browser at run time, for demos.

## 4. Run locally

Start the backend first ([backend/README.md](../backend/README.md#run-it-locally)). Then:

```bash
cd frontend
flutter pub get
flutter run -d chrome \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=http://localhost:8000
```

For a UI-only session without a backend, leave out both flags (mock mode):

```bash
flutter run -d chrome
```

To sign in through a deployed Cognito pool from your machine, run on port 8080 (already an allowed
callback) and add the two Cognito flags:

```bash
flutter run -d chrome --web-port 8080 \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=https://<cloudfront_domain_name> \
  --dart-define=COGNITO_DOMAIN=<cognito_hosted_ui_domain> \
  --dart-define=COGNITO_CLIENT_ID=<cognito_client_id>
```

## 5. Sign-in

With Cognito enabled (`lib/features/auth/data/cognito_hosted_ui.dart`):

1. The app opens the Cognito Hosted UI with the authorization-code flow and PKCE, using the current
   site root (`https://<host>/`) as the redirect URL. That URL must be in the app client's callback
   list (Terraform `additional_callback_urls`).
2. Cognito redirects back with a code, which the app exchanges at `/oauth2/token` for ID, access and
   refresh tokens, kept in `shared_preferences`.
3. Every API call sends the ID token as `Authorization: Bearer ...`. The backend verifies it against the
   pool's signing keys.
4. **No token refresh on this branch.** The ID token lasts about an hour; after that, API calls return
   `401` and the user has to sign in again. The `fix/cloud-deploy-zip-and-routes` branch adds the
   refresh (`ApiClient.onUnauthorized` in `lib/core/api/api_client.dart`).

## 6. Build for AWS

```bash
cd frontend
flutter build web --release \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=https://<cloudfront_domain_name> \
  --dart-define=COGNITO_DOMAIN=<cognito_hosted_ui_domain> \
  --dart-define=COGNITO_CLIENT_ID=<cognito_client_id>
```

Output goes to `build/web/` (gitignored). The values come from `terraform output` in `../terraform`.

## 7. Deploy

**From your machine:**

```bash
cd terraform
./scripts/deploy_frontend.sh
```

It reads the values above from `terraform output`, builds, runs `aws s3 sync build/web s3://<bucket>
--delete` and invalidates CloudFront.

**From GitHub Actions:** `.github/workflows/deploy-frontend.yml` runs on every push to `main` that
changes `frontend/**`, or when started by hand (`workflow_dispatch`). On this branch the workflow passes
only `API_BASE_URL` to the build, not the Cognito flags, so a workflow build has Cognito sign-in turned
off. Use `deploy_frontend.sh` for this stack. The workflow reads these repository secrets:

| Secret | Value |
|---|---|
| `API_BASE_URL` | `https://<cloudfront_domain_name>` |
| `FRONTEND_S3_BUCKET` | `frontend_s3_bucket` output |
| `CLOUDFRONT_DISTRIBUTION_ID` | `cloudfront_distribution_id` output (optional; skips invalidation if empty) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | An IAM user allowed to write the bucket and create invalidations |

## 8. Tests

```bash
flutter test
```

`test/live_backend_integration_test.dart` calls a running backend (default `http://localhost:8000`;
override with `--dart-define=LIVE_BACKEND_URL=...`). Start the backend first, or run the other tests
by file.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| The app shows sample data, not real data | The build used the default `USE_MOCK=true`. Rebuild with `--dart-define=USE_MOCK=false` |
| Old screens after a deploy | Flutter's service worker caches the app. Hard reload (Cmd+Shift+R) or clear site data |
| Signed out after about an hour | No token refresh on this branch (section 5) |
| Cognito shows `redirect_mismatch` | Add `https://<site>/` to Terraform `additional_callback_urls` and apply |
| API calls fail with a CORS error | `API_BASE_URL` points at another origin. On AWS, use the CloudFront URL so the site and the API share one origin |
| Deep links (`/events`) return 404 on a local static server | Use `flutter run`, or a server that falls back to `index.html`. CloudFront's SPA rewrite handles this on AWS |
