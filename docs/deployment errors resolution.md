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
| 15 | Messaging search lists people who aren't in the app; picking one gives an error | The local dev seed's accounts (`cognito_sub` `dev|...`) were restored into the cloud database. They never signed in to Cognito, so they can't receive messages | Search lists only accounts whose `cognito_sub` isn't a `dev|` row, when `auth_mode` is `cognito` | `backend/app/routers/users.py` | Code (uncommitted) |
| 16 | Admin can't appoint department or course moderators | The admin panel's module list left out Academic Help. The API already supported department and course grants | Academic Help added to the admin's module list; the existing Covers / Department / Course pickers now appear | `frontend/lib/features/admin/ui/moderator_grants_panel.dart` | Code (uncommitted) |
| 17 | Course and department moderators can't remove other people's course feedback | Feedback responses had no moderator flag, so the app offered Remove only on your own review | `can_remove` on each feedback item (author, or a moderator of the course); Remove button for moderators; no strike | `backend/app/routers/academic.py`, `frontend/lib/features/academics/ui/course_guide_screen.dart` | Code (uncommitted) |
| 18 | Admin Controls has a Backend & Health tab that isn't used | Left over from development (demo connection form and canary checks) | Tab, its header button, the demo connection form and the health provider removed | `frontend/lib/features/admin/ui/admin_controls_screen.dart` | Code (uncommitted) |
| 19 | Notification panel doesn't show new notifications until it's closed and reopened | The inbox refreshed only when opened, and the background refresh ran every 60 s without reaching an open inbox | The open inbox refreshes every 15 s, and the bell badge every 30 s | `frontend/lib/features/alerts/` | Code (uncommitted) |
| 20 | Deleting your own listing from the reports queue leaves its report on screen | The queue reloaded only after a moderator action from its own buttons, not after the listing's dialog (where the owner deleted it) closed | The queue reloads whenever a report's listing or Lost & Found dialog closes | `frontend/lib/features/admin/ui/admin_controls_screen.dart` | Code (uncommitted) |
| 21 | Switching module on the cloud site lags 3-4 s the first time | Each module has its own Lambda (5 in all). The first request to an idle one is a cold start: load the app, fetch the database secret, connect to RDS | EventBridge calls `GET /api/v1/health` on each Lambda every 5 minutes, which keeps one instance of each warm | `terraform/modules/compute/warmer.tf`, `variables.tf` (`warm_schedule`) | Yes (not yet applied) |
| 22 | My Profile's last postings tab ("Academic & Placement") was an empty placeholder | Never built | Course Feedback and Course Materials tabs for everyone; Placement Companies and Events & Mess Menus tabs for moderators and the admin. New `GET /me/posts`; companies now record who added them (`companies.created_by`, migration 025) | `backend/app/routers/my_posts.py`, `backend/app/routers/placement.py`, `backend/db/migrations/025_company_created_by.sql`, `frontend/lib/features/profile/` | Code (uncommitted); migration 025 must be run on RDS |
| 23 | Phone numbers are saved without a real SMS code | `otp.py` only logs the phone code (no SMS provider), keeps codes in process memory, and accepts 123456 | Not implemented yet: plan below | — | — |
| 24 | Searching in the top bar filters the Buy & Sell and Lost & Found pages | The search box wrote its text into those pages' filters, and its results came from their (now filtered) lists | The search runs its own server lookups for listings, lost and found reports; it no longer touches any page's filters | `frontend/lib/core/widgets/super_search_bar.dart` | Code (uncommitted) |
| 25 | In chat, only the newest read message shows two blue ticks; older read ones show one grey tick | Ticks were drawn from the "Seen" marker, which is on one message only | Every message of mine the other person has read shows two blue ticks; "Seen" stays under the newest one | `frontend/lib/features/messages/ui/conversation_view.dart` | Code (uncommitted) |
| 26 | Accepting an offer in Messages doesn't show the listing as Reserved in Buy & Sell until the page is reloaded | The Buy & Sell feed is kept in memory across pages and only reloaded on a filter change | The feed reloads quietly (no spinner) after an offer is answered and whenever the Buy & Sell page opens | `frontend/lib/features/buy_sell/providers/buy_sell_providers.dart` (`refreshQuietly`), `buy_sell_feed_screen.dart`, `messages/ui/conversation_view.dart` | Code (uncommitted) |
| 27 | Sign-in dialog's "Cancel / Browse as Guest" | Wording | A red "Cancel" button | `frontend/lib/features/auth/ui/auth_dialog.dart` | Code (uncommitted) |
| 28 | Wanted matches ignore listings a little over budget that are negotiable | Matching compared price with the budget only | A listing marked negotiable matches up to 20% over the budget | `backend/app/alerts.py` (`NEGOTIABLE_MARGIN`) | Code (uncommitted) |
| 29 | Category suggestion doesn't work on the cloud (Buy & Sell, and now Lost & Found) | It runs an ONNX model in the API, but the Lambda zip leaves out onnxruntime, tokenizers, numpy and the model (250 MB limit), so the API answers "no suggestion" | New ML layer (onnxruntime 1.16.3, tokenizers, numpy 1.26, bge-small model; 132 MB unzipped) on the buy-sell and lost-found Lambdas; the two `/categories/suggest` routes go to them | `terraform/modules/compute/ml_layer/build.sh`, `modules/compute/main.tf`, `modules/api_gateway/main.tf`, `variables.tf` (`ml_layer_zip`) | Yes (not yet applied) |
| 30 | Lost & Found reports have no title, and no category suggestion | Never built | Optional `title` on reports (required in the app), searched with the description, used in chat topics, the reports queue, removal notices, matching and suggestion examples. The report form suggests a category from the title, as Buy & Sell does | `backend/app/routers/lost_found.py`, migration 025, `frontend/lib/features/lost_found/` | Code (uncommitted); migration 025 must be run on RDS |
| 31 | Posting a new mess menu adds it after the old one instead of replacing it | "Post the next menu" started the new menu after the last one ended, and overlapping a menu that had meals was refused (409) | A new menu replaces the mess's menu from its first day: a menu that started earlier now ends the day before, and menus starting within the new dates are removed (their files deleted). The button is "Post a new menu" and starts today | `backend/app/routers/mess.py` (`_replace_older_menus`), `frontend/lib/features/mess/ui/mess_screen.dart` | Code (uncommitted) |

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

### 15 to 19. Found on the cloud site
- **15, messaging search.** The search matched every active account, including the dev seed rows
  restored with the database snapshot. Those accounts have `cognito_sub` values starting `dev|` and never
  signed in on the deployed app, so a chat with them failed. The search now skips those rows when
  `auth_mode` is `cognito`. Dev auth still lists everyone, because every local account is a `dev|` row.
  The exact error text wasn't captured, so this fix is based on the cause above. If the error appears
  for a real account, capture the message and check `POST /chat/conversations`.
  Test: `test_search_lists_only_people_who_signed_in` (`backend/tests/test_chat.py`).
- **16, admin appointing Academic Help moderators.** The API accepted department and course grants
  (`POST /moderators`), but the admin's module list was `buy_sell`, `lost_found`, `placement_hub`,
  `events`. Academic Help is now in that list, so the Covers picker (a whole department or one course)
  and the department and course pickers appear for the admin.
- **17, moderators and course feedback.** The rules were already in the API: a course moderator and a
  department moderator (for that course's department) may remove feedback, and an admin may too. The app
  didn't show the action. Each feedback item now carries `can_remove`, which is true for its author and
  for the course's moderators. Removing another person's feedback writes a `remove_course_feedback` row to
  the moderation log and closes its open reports. It creates no seller strike, because strikes apply only
  to Buy & Sell listings. Test: `test_moderators_remove_course_feedback_without_strikes`.
  Materials and forum posts already allowed moderator removal (`can_manage_course`, `can_moderate_forum`).
- **18, Backend & Health tab.** Removed: the tab, the "Live Backend" header button that jumped to it,
  the demo connection form and its test and save actions, and `systemHealthProvider`. The repository's
  `getSystemHealth` method remains, unused.
- **19, notifications.** The inbox was only refreshed when opened, and the background refresh ran every
  60 s, so an open inbox missed new items. The open inbox now refreshes every 15 s, and the provider that
  feeds the badge refreshes every 30 s. This is polling over HTTP, not a live push. A push would need a
  WebSocket or SNS/FCM delivery (see `backend/app/notify.py`).

### 20 to 25. Found on the cloud site (4 Nov)
- **20, reports queue after an owner delete.** Opening a report shows the listing (or Lost & Found
  report) dialog. If you own it, you can delete it there; deleting it removes its reports, but the queue
  only reloaded after its own Dismiss/Remove buttons. It now reloads when the dialog closes, whatever
  happened inside it.
- **21, module-switch lag.** All 5 Lambdas run the same app, but API Gateway sends each module's paths
  to its own function (`modules/api_gateway`), so the first visit to a module after a few idle minutes
  starts that function cold. Locally there is one always-running server, so this never showed.
  `warmer.tf` adds an EventBridge rule (`warm_schedule`, default `rate(5 minutes)`, empty turns it off)
  that sends each function an API Gateway-shaped `GET /api/v1/health`. That request goes through the real
  app, so it also loads the database secret and opens the connection pool. Tested locally: the same event
  through `app.main.handler` returns 200. Limits: it keeps one instance per function warm, so several
  requests at the same moment can still start a second, cold instance. Provisioned concurrency would
  remove that too, but it is billed per hour. Cost of the warmer: about 8,640 invocations of ~50 ms a
  month per function, inside the Lambda free tier. Apply with `terraform apply`.
- **22, My Profile postings.** `GET /me/posts` returns my course feedback and materials, and the
  companies, events and mess menus I added (empty lists for people who can't add them), newest first,
  at most 200 each, removed items left out. The app shows two new tabs to everyone (Course Feedback, Course
  Materials) and two more to moderators and the admin (Placement Companies, Events & Mess Menus; events
  and mess menus share a tab). Tapping an item opens its course, company, event or mess page.
  Companies had no "added by" column, so migration `025_company_created_by.sql` adds `created_by`.
  Companies added from now on (by hand or by any CSV import) record it; older ones stay NULL and aren't
  listed for anyone. **Run migration 025 on RDS before deploying this backend**, or adding a company fails.
  Test: `test_my_posts_lists_feedback_materials_companies_and_events`.
- **24, top-bar search.** It used to write the text into the Buy & Sell and Lost & Found filters and then
  read those pages' lists, so after a search those pages stayed filtered. It now asks the server for up to
  6 listings, lost and found reports itself, like it already did for companies and events.
- **25, chat ticks.** Option chosen: every read message gets two blue ticks (WhatsApp style); only the
  newest read message also says "Seen". Unread messages keep one grey tick. Based on
  `peer_last_read_seq`, which the server already sends.

### 26 to 31. Found on the cloud site (4 Nov, second batch)
- **26, Reserved status after an offer.** The feed's list lives in a provider that outlives the page, so
  it kept the old status. `refreshQuietly()` reloads the listings already shown (same count, up to 50)
  without a loading spinner. It runs when the Buy & Sell page opens and right after an offer is
  accepted, declined or withdrawn in Messages. Cost: one extra list request per visit to Buy & Sell. A
  live push (WebSocket) would avoid even that, but isn't worth it here.
- **28, negotiable listings and Wanted posts.** Evidence for the margin: a 2023 study of about 26 million
  eBay Best Offer negotiations (Leuphana University Lüneburg, published in PNAS) found that the offer
  that best balances a low price against the seller walking away averages about 80% of the asking price.
  The margin is set a little more cautiously at 20% over the budget: a ₹3,600 negotiable listing matches a
  ₹3,000 budget if the buyer offers about 83% of the asking price. Firm listings still need to be within
  budget. It applies to the Wanted post's match list and to the alerts. One constant,
  `NEGOTIABLE_MARGIN` in `backend/app/alerts.py`. Test: `test_negotiable_listings_match_up_to_20_percent_over_budget`.
- **29, category suggestion on the cloud.** Locally the API has the model; on Lambda the zip leaves the
  ML stack out to stay under the 250 MB limit, and `categories_suggest.py` then answers "no suggestion"
  instead of failing, which is why nothing showed. The fix is a separate layer:
  - `terraform/modules/compute/ml_layer/build.sh` builds `ml-layer.zip` without Docker (pip fetches the
    Linux wheels; the model comes from `scripts/fetch_match_models.py --suggest-only`). Versions:
    onnxruntime 1.16.3 is the newest that runs on Lambda's Python 3.11 (Amazon Linux 2, glibc 2.26), and
    it needs numpy 1.x, so the layer has numpy 1.26.4.
  - Size: 132 MB unzipped, plus the API's own ~75 MB, under the 250 MB limit. It can't go on
    community-events, whose Tesseract layer already uses 185 MB, so the layer is on buy-sell and
    lost-found, and API Gateway sends `GET /api/v1/buy-sell/categories/suggest` and
    `GET /api/v1/lost-found/categories/suggest` to them. Those functions get `CAMPUSHUB_MATCH_MODEL_DIR=/opt/models`.
    Only the category model is in the layer, so Lost & Found matching stays off as before.
  - Checked in the `public.ecr.aws/lambda/python:3.11` image with the layer at `/opt`: the model loads
    (about 3 s under emulation on a Mac, less on Lambda) and ranks "Hero Sprint 26T gear cycle" as
    Cycles (0.645, next 0.466).
  - To deploy: run `build.sh`, set `ml_layer_zip = "modules/compute/ml_layer/ml-layer.zip"` in
    `terraform.tfvars`, then `terraform apply`. Cold starts on those two functions get slower by the
    model load the first time a suggestion is asked for; the warmer (item 21) keeps them up.
- **30, Lost & Found titles.** Migration 025 also adds `title` (1-120 characters, NULL on older reports) to
  `lost_reports` and `found_reports`. The API takes it as optional so older clients keep working; the
  app requires it on new reports and on edits. Places that showed a description as the name now show the
  title when there is one: chat topics ("Lost: Black JBL earbuds"), the reports queue, the moderator
  removal notice. Matching and automatic flagging read the title together with the description, and
  category suggestion learns from report titles. Test: `test_reports_have_titles_that_search_and_chat_use`.
- **31, mess menus.** `_replace_older_menus` runs before a new menu is saved, inside the same
  transaction: earlier menus are cut off the day before the new one starts, and menus that start inside
  the new dates are removed (logged as `replace_mess_menu`; their files are deleted unless the new menu
  uses the same file). Editing a menu's dates still refuses an overlap, since that edits one menu rather
  than posting a new one. Tests: `test_menu_with_meals_replaces_a_file_only_menu` and the mess test in
  `test_seniors_and_mess.py`.

### 23. SMS codes for phone numbers (plan, not implemented)
Today `POST /me/phone/code` and `POST /me/phone/verify` exist, but `otp.py` writes the code to the log
instead of texting it, keeps codes in process memory (on Lambda the verify call can land on a different
instance and fail), and accepts `123456`. Two ways to make it real:

**A. Cognito verifies the number (recommended, since sign-in already uses Cognito).**
1. Terraform (`modules/auth`): give the user pool an `sms_configuration` (an IAM role Cognito assumes to
   publish to SNS, with an external ID) and keep `phone_number` as a standard attribute. Leave sign-in on
   email; phone is only an attribute, so no MFA is needed.
2. App: the hosted UI sign-in must request the `aws.cognito.signin.user.admin` scope so the access token
   may change the user's own attributes. "Verify" calls Cognito `UpdateUserAttributes` with
   `phone_number` (Cognito texts the code), then `VerifyUserAttribute` with the code the user types.
3. API: replace the two endpoints with one, `POST /me/phone/sync`, which reads the user from Cognito
   (`AdminGetUser`, or the claims of a fresh ID token) and saves the phone into `users.phone` only when
   `phone_number_verified` is true. The Lambda role needs `cognito-idp:AdminGetUser`.
4. Remove the phone code paths and `123456` from `otp.py`.

**B. Our API sends the SMS through SNS.** Keep the two endpoints; `_send_sms` calls SNS `Publish`
(transactional), codes move from memory into a database table (hashed, with expiry and attempt count),
and the Lambda role gets `sns:Publish`. More code than A, but no Cognito scope change.

**What either option needs from the AWS account (the real blockers):**
- SNS starts in the **SMS sandbox**: it only texts numbers you have verified in the SNS console. Leaving
  it is a support request to AWS (a day or more).
- Texts to **Indian numbers** need DLT registration (a registered sender ID and message template under
  TRAI rules); unregistered messages may be blocked by Indian carriers.
- The account's default SMS **spend limit** is USD 1 a month; raise it in SNS settings.
For the course demo, the sandbox with a few verified team numbers is enough to show it working.

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
8. **Commit the frontend changes** for items 15 to 19 along with the earlier frontend work (see item 1).
9. **Academic Help moderators on the cloud:** check that a course moderator can remove feedback, a
   material and a forum post on their own course, and that they cannot on another course.
10. **Run migration 025** (`backend/db/migrations/025_company_created_by.sql`) on RDS before deploying the
    backend for items 22 and 30, then `terraform apply` for the Lambda warmer (item 21) and redeploy the frontend.
11. **SMS codes for phone numbers** (item 23): pick option A or B and do the account steps (SNS sandbox,
    DLT, spend limit).
12. **ML layer for category suggestion** (item 29): run `terraform/modules/compute/ml_layer/build.sh`, set
    `ml_layer_zip` in `terraform.tfvars`, and `terraform apply`.
