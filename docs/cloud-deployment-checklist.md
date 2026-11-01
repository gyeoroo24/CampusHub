# Deploying CampusHub to the cloud: what still has to change

*Last updated 1 Nov 2026 (database revision 12)*

Local development takes shortcuts that must not reach a real deployment. This page lists them,
plus the cloud work each feature still needs. How to build and wire the Lambda, RDS Proxy, S3,
CloudFront and IAM is in [backend/README.md → Deploying on AWS](../backend/README.md#deploying-on-aws).
Update this page whenever a new shortcut or cloud dependency is added.

## Must do before going live

1. **Run the database migrations** on RDS, in order, if the database is older than revision 12.
   A brand-new database only needs `backend/db/schema.sql`.
   - `008_encrypted_chat`
   - `009_server_held_chat_keys`
   - `010_chat_per_person`
   - `011_drop_matched_status`
   - `012_lf_matching` (then invoke the matcher once with `{"backfill": true}`)

   `010` merges older per-listing chats into one chat per person. Back up the `chat_*` tables
   first.
2. **Sign-in must use Cognito:**
   - Keep `CAMPUSHUB_AUTH_MODE=cognito` (the default). Dev sign-in (`X-Dev-User` with an emailed
     code) refuses to start inside Lambda, but on EC2 nothing stops it if the `.env` says `dev`.
   - Do not deploy any build where `backend/app/otp.py` accepts a fixed code. During local
     testing that file has a "TEMP HARDCODED OTP" block that accepts `123456`. It has never been
     committed, and must not be.
   - Set `CAMPUSHUB_SMTP_*` if dev sign-in is ever used on a shared server.
3. **The web app must renew Cognito tokens.**
   - Cognito ID tokens expire after about an hour, and the Flutter app does not yet use the
     refresh token to get a new one.
   - Without that, people are signed out every hour.
   - Store the refresh token with the access token (`SharedPrefsTokenStorage` already has a slot
     for it) and refresh it on 401 before giving up.
4. **Build the web app for the live API:**
   - `flutter build web --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<api>`.
   - The default build is mock mode.
   - The admin "server connection" tab can override the API URL per browser. Hide it, or limit it
     to the admin, in production.
5. **Configure CORS:** set `CAMPUSHUB_CORS_ALLOW_ORIGINS` to the web app's origin (S3 + CloudFront,
   Amplify or Vercel).
6. **Ship the new Python dependency:** `cryptography` is now a direct dependency (the server
   creates messaging keys). It is in `requirements.txt` and builds for `linux/arm64`. Rebuild the
   Lambda image.

## Messaging

- **The server can read messages today:**
  - Each user's private messaging key is stored in `chat_keys` (`backup_kdf = 'none'`), so
    anyone with database access can decrypt chats.
  - Treat `chat_keys` as sensitive data: RDS encryption at rest, no public snapshots, limited
    database users.
  - For true end-to-end encryption, the plan is passkeys (WebAuthn PRF) plus QR device linking;
    see the future plan §1.1.
  - A short PIN guarded by AWS KMS or Nitro Enclaves with a guess limit is the heavier
    alternative.
- **Delivery is polling:**
  - An open chat asks for changes every 3 s, the inbox every 15 s and the badge every 20 s.
  - On Lambda this means many small invocations per active user. Watch cost and concurrency, or
    raise the intervals.
  - For instant delivery, add an **API Gateway WebSocket API**: store connection ids in
    DynamoDB, and on each message `postToConnection` a "conversation X changed" signal so the
    app syncs with `?after=`. Keep polling every 30–60 s as a fallback.
  - With EC2 behind a load balancer, FastAPI WebSockets with Postgres `LISTEN/NOTIFY` (or Redis
    pub/sub) between instances also works.
- **Push for closed apps:** chat notifications are written to the inbox, but `app/notify.py` only
  logs pushes. Plug in SNS or FCM / Web Push.
- **Rate limit:** 30 messages per user per minute, counted in Postgres. Add WAF or API Gateway
  throttling for abuse at scale.

## Lost & Found matching

- **Deploy the matcher Lambda** from `backend/Dockerfile.matcher` (handler
  `app.matching.handler.handler`; arm64, 1536 MB, 30 s, async retries 2). Steps are in
  [backend/README.md → Deploying on AWS](../backend/README.md#deploying-on-aws).
  - Give it the API's database, S3 and VPC settings. Its role needs `s3:GetObject` and
    `secretsmanager:GetSecretValue`.
  - On the API: set `CAMPUSHUB_MATCH_FUNCTION` and allow `lambda:InvokeFunction` on it. From
    private subnets the API needs a `lambda` interface endpoint (or NAT) for that call.
- **If the matcher isn't deployed, matching silently falls back** to the old same-category
  rule (`match_mode` resolves to `off` because the API image has no models). Check
  `GET /lost-reports/{id}/matches` answers `ready`/`pending`, not `unavailable`.
- **Retry missed work:** an EventBridge schedule (e.g. every 15 minutes) sending
  `{"backfill": true}` re-matches any report a failed invocation left pending.
- **Latency and cost:** about 7 ms per description and 40 ms per photo on one Mac thread;
  expect 2–3× on Graviton, plus ~0.3 s to load the models on a cold start. It runs after the
  API has answered, so users don't wait for it.
- **Tuning:** `CAMPUSHUB_MATCH_POSSIBLE` (0.4) and `CAMPUSHUB_MATCH_STRONG` (0.75) set what is
  listed and what alerts. `lf_matches` keeps the raw similarities for re-tuning;
  `backend/scripts/calibrate_matching.py` re-measures them.
- **Licence:** the MobileCLIP-S0 weights are under Apple's ML research licence (fine for this
  course project; check it before any commercial use). all-MiniLM-L6-v2 is Apache-2.0.

## Phone verification

- `POST /me/phone/code` sends a 6-digit code to the number, but there is **no SMS provider**:
  the code is only written to the log (`_send_sms` in `backend/app/otp.py`). Use **Amazon SNS**
  (SMS), and register a sender ID / DLT template for Indian numbers.
- Codes are kept in process memory, which is fine for one dev server but not for Lambda, where
  each container has its own memory. Store them in DynamoDB (with TTL) or a Postgres table.
  Sign-in codes have the same limitation, but Cognito replaces those in production.

## Notifications and jobs

- Deploy the daily purge job (`app.jobs.purge_handler`, EventBridge schedule).
- Users can now delete their own notifications (`DELETE /me/notifications…`). This needs no
  extra infrastructure.

## Already handled in code (no action needed)

- **Moderator rights** are checked against the database on every request, and revoking a role
  takes effect immediately. The app also re-checks `/me` regularly, so tools disappear for a
  removed moderator.
- **Guests** no longer send a dev identity with API calls.
