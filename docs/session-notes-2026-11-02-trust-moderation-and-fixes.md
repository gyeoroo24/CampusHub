# CampusHub — Seller Trust, Moderation, Flagging & Price Watch

*1–2 Nov 2026, branch `backend_v2`*

This round shipped the rest of the Buy & Sell trust/safety work: the seller trust score (rebuilt
once, per feedback, to reversibly hide listings instead of deleting them), automatic flagging,
price-drop watch with a "Negotiable" badge, and a rebuilt category suggester. Alongside that,
moderation got clearer notices and a tidier queue, a few smaller bugs were fixed, and a separate
pass this session audited a teammate's cloud-deployment error report against the real code (see
the dedicated section below). Database revision 12 → 16 (migrations `013`–`016`). Nothing was
deployed; everything was tested locally against `campushub-db-1`/`campushub-s3-1` via curl and
interactive two-role browser testing.

## ⚠️ Known risk before merging into `main` — hardcoded OTP is now committed

`docs/cloud-deployment-checklist.md` has always warned that `backend/app/otp.py` must never ship
with a fixed OTP, and used to say that code "has never been committed." **That's no longer true.**
Commit `7bce283` ("simplifying email sign in for testing purposes") added a `TEMP HARDCODED OTP`
block to `backend_v2` that makes `verify_otp()` accept `"123456"` for **any email, unconditionally**
— it isn't gated behind `CAMPUSHUB_AUTH_MODE` or any dev-only check. This must be removed before
`backend_v2` is merged into `main` or any deploy image is built from it; the checklist text has
been corrected to reflect that it's now committed, not just a local edit (see below).

## New features

### Seller trust score, reversible listing hide & seller appeal (future plan §1.5)

Full technical detail and the verification log are in
[future-plan-2026-10-31-next-level-features.md §1.5](future-plan-2026-10-31-next-level-features.md);
summary:

- A moderator resolving a report by removing a listing records a **strike** against the seller
  (severe items block at once; non-severe strikes show "Negative Seller" at 2 and "Blocked Seller"
  + posting suspension at 3 — all three thresholds configurable in `Settings`).
- **Reworked after first-pass feedback:** the listing is **hidden, not deleted**
  (`listings.hidden_by_strike_id`, migration `014`) — visible only to its seller and a Buy & Sell
  moderator/admin, and restored to everyone if the strike is overturned.
- The seller gets a "Seller strikes" screen (account menu) to see their strikes and file one appeal
  per strike. A moderator's new "Seller Strikes" tab shows contested strikes (defaulting to
  `PENDING`) and can **overturn** (restores the listing, drops the strike) or **reject the appeal**
  (strike and hidden state stand, but it leaves the review queue).
- Fixed a gap where a moderator deleting a reported listing *from the listing itself* (not through
  the report queue) never actually recorded a strike — it now resolves the report and records one,
  with a severity choice in the dialog (defaults to non-severe on the API if omitted).

### Automatic flagging (future plan §1.6, `backend/app/screening.py`)

- Every new or edited Buy & Sell listing and Lost & Found report is screened automatically; a hit
  files a system-sourced report (shows as `AUTO` in the moderator queue) instead of waiting for a
  student to report it.
- **Prohibited items:** bge-small similarity against banned-item examples and harmless look-alikes,
  plus a short word list. A hit **holds the listing** (hidden from other users) until a moderator
  decides, same severity-weighted reasoning as §1.5's severe tier.
- **Gibberish and spam:** cheap heuristics, no model.
- **Obscene photos:** Falconsai NSFW (int8 ONNX) run in the matcher Lambda or a background task
  after the response, so it doesn't add upload latency.
- `CAMPUSHUB_AUTO_FLAG=false` turns the whole pipeline off.

### Price watch + "Negotiable" badge (future plan §2.3)

- `listings.negotiable` (migration `015`) shows a badge; a seller can mark an existing listing
  negotiable without changing its price.
- "Watch price" on someone else's listing, surfaced in a "Watched listings" menu; watchers get a
  `listing_watch` notification on an actual price change or when the listing is marked negotiable.

### Smarter category suggestion (future plan §2.4)

- Replaced the first version (MiniLM on bare category names — it suggested "Bottle" for "plant"
  when there was no Plant category) with `bge-small-en-v1.5` (int8, 34 MB): category phrases blended
  with recent listings in that category, a score-plus-margin rule, calibrated against 87 labelled
  titles (`backend/scripts/calibrate_category_suggest.py`), beating MiniLM, an NLI re-ranker and a
  0.5B LLM baseline on the same set. Full comparison in
  [future-plan-2026-10-31-next-level-features.md §2.4](future-plan-2026-10-31-next-level-features.md).
- Category dropdowns got type-to-jump-by-prefix and a shorter scrolling menu.

### Moderation notices and queue

- The reported item's owner is told once when it's first reported (never by whom), and again when
  a moderator keeps it up or removes it, with the moderator's reason.
- A user is notified when they're made, or stop being, a moderator or admin.
- The report queue sorts newest first and shows each item's title, not just its id.
- A moderator can delete a Buy & Sell / Lost & Found category; its posts and saved searches move to
  another category instead of breaking.

## Bugs fixed

| Bug | Cause | Fix |
| --- | --- | --- |
| Saved searches with no filter matched everything (e.g. a search for "hero cycle" alerted on a "Drugs" listing) | A filterless saved search matched every new listing by design | A saved search now needs a keyword, category or price to match anything |
| A hard-coded team dev key and LAN IP were sitting in app config | Left over from local testing | Removed from `app/config.py` and dev notes |

## Cloud deployment investigation (2 Nov)

Separately this session, a teammate's deployment agent reported four cloud errors (appoint
moderator, resolve-report 500s, chat send/receive failures, a Flutter chat-key crash) and
attributed specific SQL/constraint/routing bugs. All four claims were checked against the actual
code and schema and **none held up** — see `backend/scripts/diagnose_cloud_deploy.sh` and `.sql`
for the diagnostic checklist written to confirm this. The real, much more likely explanation:
`backend_v2` (all the application code, including everything in this doc) and `origin/main` (all
the Terraform/CI/CD) diverged completely after PR #1 and were never reconciled — `main`'s Terraform
currently deploys a separate, hand-written ~500-line Lambda stub
(`terraform/modules/compute/lambda_src/app.py`) that doesn't implement moderator grants, report
resolution or chat messaging at all, which alone explains every reported symptom. This is why the
planned merge of `backend_v2` into `main` (see the OTP warning above first) needs to also address
which Lambda deployment approach `main` actually uses going forward.

## Verification

Curl, end-to-end, for the full seller-trust flow (report → resolve → hide → visibility gating →
appeal → moderator queue → overturn/reject) plus negative-path checks (permissions, double-submit),
and a full interactive two-role browser walkthrough (a seller account and a Buy & Sell moderator
account) confirming the UI matches. **Not run this session:** the backend pytest suite and Flutter
test suite weren't re-run against today's changes — worth doing before merging into `main`.

## Bugs reported and fixed (2 Nov, from UI testing)

Reported during a UI pass, then fixed and verified the same day (signed in as a seller and as the
`cadithya` Buy & Sell moderator, both roles, via the browser).

1. **Dropped "Got it" as a Wanted post status.** Closing a Wanted post already means the author
   either found it or no longer wants it, so a separate "Got it" state added a choice that changed
   nothing downstream. The status-switch chips in
   [wanted_detail_dialog.dart](../frontend/lib/features/wanted/ui/wanted_detail_dialog.dart) now
   only offer Looking/Closed. **Scoped down from the original ask:** the Postgres enum
   `wanted_status` still has its `'fulfilled'` value (schema.sql:135) — dropping a value from a live
   enum needs its own migration and a decision on any existing `fulfilled` rows, so this round only
   removed it from the UI/workflow (nothing can create a `fulfilled` post anymore); the schema change
   is a separate follow-up if wanted.
2. **Wanted tab no longer shows everyone's posts by default.** Added a "What I want" (default) /
   "What others want" toggle, mirroring the existing For Sale/Wanted switch. The backend already
   supported this via `GET /wanted`'s `author_id` filter — only the frontend
   ([wanted_feed_sliver.dart](../frontend/lib/features/wanted/ui/wanted_feed_sliver.dart),
   [wanted_providers.dart](../frontend/lib/features/wanted/providers/wanted_providers.dart)) needed
   wiring.
3. **"Show closed" now shows closed posts only**, not closed plus everything else — it requested
   every status before; fixed in
   [wanted_providers.dart](../frontend/lib/features/wanted/providers/wanted_providers.dart).
4. **Listing price field rejects letters as you type**, not just on submit — an `inputFormatters`
   regex blocks non-numeric characters outright, and the form now validates live
   (`AutovalidateMode.onUserInteraction`) in both
   [create_listing_dialog.dart](../frontend/lib/features/buy_sell/ui/widgets/create_listing_dialog.dart)
   and [edit_listing_dialog.dart](../frontend/lib/features/buy_sell/ui/widgets/edit_listing_dialog.dart).
5. **Category dropdown now uses an explicit, lighter shade** (`#E2E8F0` light / `#1E293B` dark —
   one step off the form's own field color, not Material 3's heavier default menu surface) in
   [category_picker.dart](../frontend/lib/core/widgets/category_picker.dart).
6. **Dark mode now persists** across a refresh, stored per-browser via `SharedPreferences`
   (`ThemeModeStorage` in
   [app_theme.dart](../frontend/lib/core/theme/app_theme.dart), applied once on start and saved on
   every change in [main.dart](../frontend/lib/main.dart)).
7. **Trimmed the "Negotiable" checkbox's helper text** to "Shows a 'Negotiable' badge" in both
   listing dialogs.
8. **Removed the "NONE" appeal filter chip** from the moderator's Seller Strikes tab
   ([admin_controls_screen.dart](../frontend/lib/features/admin/ui/admin_controls_screen.dart)) —
   it now offers `PENDING`, `RESOLVED`, `ALL`.

**Verified in browser:** all 8, signed in as a seller (`mohammadazam@iisc.ac.in`) and as the
`cadithya` Buy & Sell moderator. **Not run:** the backend pytest suite and Flutter test suite —
these were pure-frontend changes with no new backend behavior, but worth a pass before merging.
