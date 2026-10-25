# Step 20: Frontend Review Fixes — Roles, Photos, Feedback Rules, Search and Consistency

**Timestamp:** 2026-10-25T23:30:00+05:30
**Status:** Complete & Verified
**TestSuite:** 70/70 Tests Passing • 0 Flutter Analyze Issues
**Backend:** needs `backend_v2` with schema rev 7 (`db/migrations/007_feedback_rules.sql`)

---

## 1. Summary

Fixes for the issues found in the 25 Oct gap analysis and by Sufyan's own testing. The frontend now shows what the server says, waits for the server before reporting success, and fills the gaps users hit first.

## 2. What changed

| Area | Problem | Fix |
| :--- | :--- | :--- |
| Roles | Live sign-in filled in moderator grants from `MockAdminRepository` and forced admin for `kmukund@iisc.ac.in`, so users saw moderator screens the server refused (this is why mohammadazam looked like a moderator) | Roles come only from `/me`; any error other than 401/403 keeps the session instead of signing out |
| Detail dialogs | Opened from the feed's summary, which has no contact or description, so signed-in users saw "account inactive" | Listing and report dialogs load the full item (`listingDetailProvider`, `lostFoundDetailProvider`) |
| Profile posts | "My lost/found reports" asked for 100 items (API max 50) and always failed; "My listings" filtered other people's posts by name | Fetched by `seller_id` / `reporter_id`, 50 per page |
| Photos | The forms took a URL the API ignores, plus a random picsum fallback | `PhotoPickerField` (image_picker) + `uploadPickedPhotos` (presigned upload, then `photo_keys`); `UploadService` sends bytes, not a stream, and no Content-Length (browsers forbid it) |
| Feeds | Errors looked like "No listings found"; category chips filtered one page on the device; Buy & Sell sort and L&F date chips did nothing in live mode | `ErrorState` with Retry; category sent as `category_id`; `sort` and `from_date`/`to_date` sent (backend now reads them; dates in UTC) |
| Create, delete, status | Create listing wasn't awaited; deletes closed before the server answered and caught nothing; L&F status chips didn't update the feed; chips did nothing when the dialog was opened from profile or notifications | All awaited with errors shown; the dialog owns status changes and updates the feed; the admin also gets edit/status controls (the API allows it) |
| Categories | Rename/delete reported success though the API has no such endpoints | Live mode now says the server doesn't support it |
| Mode switch | Wanted, alerts, campus services, academics read the fixed `AppConfig.useMockData` | They watch `serverConfigProvider` like the other modules |
| Sign in / out | Hidden behind a name pill or bare avatar; the account dialog also held the admin's paste-a-UUID tools | `AccountMenuButton`: "Sign in" for guests; My profile / Admin panel or Moderation tools / Sign out for signed-in users. Sign-in dialog says signing in creates the account. Email rule matches the API (`alum.iisc.ac.in` accepted) |
| Profile form | No limits enforced | Validated form: name 1–100, phone `+` and 10–15 digits (spaces/dashes stripped), programme ≤ 100, year 1950–2100; clearing the phone removes it |
| Search | Super search covered only Buy & Sell and L&F; course codes needed the exact spacing | Courses section in super search; "ds252", "DS-252", "ds 252" all find DS 252; the Courses tab search spans all departments |
| Feedback | Repeat reviews could skew the guide; no edit/delete; names shown to everyone | One review per course (server 409); "Your review" card with Edit/Delete; "Post anonymously"; guests never see names |
| Moderators | Grant form had no department/course picker (Academic Help grants always failed); no way to step down; admin and moderator screens mixed | `ModeratorGrantsPanel` with pickers, also for department moderators (course moderators in their department); role-based admin tabs (moderators see only Reports, Categories, Course moderators as applicable); `RoleCard` on the profile with Step down |
| Admin accounts | Deactivate / hand over looked users up in an always-empty list | Use `GET /users/lookup?email=` |
| Consistency | "Email"/"Call" only copied; status names differed per screen; new dialogs left the page on browser back; some dialogs overflowed on short screens | `contactBy` opens mail/dialer; one `label` per status enum; `ModalHistoryWrapper` on new dialogs; scrollable dialog content |

## 3. Backend changes this needed (backend_v2)

`GET /users/lookup`, moderators may revoke their own grant, `GET /listings?sort=`, `from_date`/`to_date`/`sort` on report lists, `GET /reports?status=all`, feedback `is_anonymous` + `is_mine` + `GET /courses/{id}/feedback/mine` + one review per course (migration 007), sentiment scoring fixes (17/17 seed opinion templates now labelled as intended).

## 4. Verification

`flutter analyze` clean; `flutter test` 70/70 (2 new: feedback write/edit/delete, short-screen dialog); backend `pytest` 97/97. Checked in the browser against the live backend: sign-in and account menu, profile lost/found tabs, listing detail contact, review post/409/delete.

## 5. Not done

Content reporting by users, course materials and forums, push notifications, Placement Hub and Events, real Cognito sign-in, and phone OTP verification (options in the bug review doc).
