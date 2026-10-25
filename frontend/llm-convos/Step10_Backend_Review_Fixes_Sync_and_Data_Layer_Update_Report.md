# Step 10: Backend Review Fixes Sync & Data/Domain Layer Alignment Report

**Date:** 24 October 2026  
**Backend Commit Inspected:** `3a7aa05` ("Fix bugs and inconsistencies from the 23 Oct backend review") on branch `origin/add-backend-and-docs`  
**Frontend Scope:** Data and Domain layers updated; UI layer untouched (awaiting user discussion).  
**Test Status:** 25 / 25 automated tests passing (100%), `flutter analyze` 0 issues.

---

## 1. Summary of Changes Pushed to `origin/add-backend-and-docs`

The backend team addressed 31 review items (B-1 through B-31) spanning security, authentication, uploads, moderation, query handling, and permissions:

### 1.1 Security & Authentication
1. **Email Verification Before API Calls (B-2):**
   - Accounts are only provisioned for verified IISc emails (`@iisc.ac.in`).
   - If an unverified user attempts an API call, Cognito returns HTTP 403 instructing the user to verify their code.
2. **Cognito Token Verification on All Routes (B-20):**
   - Every route validates tokens; returns **503** if Cognito key retrieval temporarily fails (client should retry) and **401** if expired/invalid.
3. **Deactivated Accounts (B-23):**
   - New database column `u.is_active` on `users`.
   - Deactivated accounts receive **403** ("This account has been deactivated") on all authenticated endpoints.
   - For items posted by deactivated users, `seller_contact` and `reporter_contact` are returned as `null` even to signed-in viewers.
4. **Local Dev Auth Restrictions (B-3):**
   - `X-Dev-User` and `X-Dev-Name` headers are only honored when running with `CAMPUSHUB_ALLOW_DEV_AUTH=true` and connecting from `localhost`.

### 1.2 New Endpoints & Model Changes
1. **Admin Account Status Management:**
   - **`PATCH /api/v1/users/{user_id}`** (Admin only).
   - Request: `AccountUpdate(is_active: bool?, is_admin: bool?)`.
   - Response: `AccountStatus(id: UUID, email: str, name: str, is_active: bool, is_admin: bool)`.
   - Admins can deactivate/reactivate users and grant/revoke admin status (cannot alter their own account).
2. **Device Push Token De-registration:**
   - **`DELETE /api/v1/me/devices`** previously expected `?push_token=...` query param.
   - Changed to JSON request body: `{"push_token": "..."}` so sensitive device tokens do not appear in web server access logs.
3. **Upload Presigned Ticket & Tagging (B-4, B-7, B-10):**
   - `POST /api/v1/uploads` returns header `"x-amz-tagging": "status=pending"`.
   - Presigned upload enforces exact `Content-Length` matching `size_bytes`.
   - Files unattached after 24 hours are auto-purged. Attached files transition out of pending status upon listing/report creation.

### 1.3 Permissions & Content Moderation
1. **Admin Content Editing:**
   - Admins can now edit any listing (`PATCH /listings/{id}`), change status (`PATCH /listings/{id}/status`), and replace photos (`PUT /listings/{id}/photos`).
   - Admins can edit any lost/found report (`PATCH /lost-reports/{id}`), change status, and replace photos.
   - Admins can rename threads (`PATCH /threads/{id}`) and edit comments (`PATCH /comments/{id}`).
   - All admin edits on behalf of other users are logged in `moderation_actions` audit table.
2. **Cascade Report Resolution (B-12):**
   - Deleting content via its `DELETE` endpoint automatically closes all open moderation reports on that item.
3. **Course Moderator Feedback Deletion (B-1):**
   - Course moderators can delete feedback for their specific course (`DELETE /courses/{id}/feedback/{feedback_id}`).

### 1.4 Queries, Paging & Search
1. **Paging Stability (B-21):**
   - Feeds now order by `ORDER BY created_at DESC, id DESC` to eliminate duplicate/skipped items on pagination boundaries.
2. **Search Sanitization & Text Constraints (B-15, B-16):**
   - Backend strips whitespace and treats whitespace-only queries as `None` (clearing filter).
   - Wildcards in LIKE searches (`%`, `_`, `\`) are safely escaped.

---

## 2. Modifications Applied to Frontend Data & Domain Layer

Without touching any UI widgets, the following data/domain layer adjustments were implemented:

1. **`User` Domain Entity ([`user.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/domain/user.dart)):**
   - Added `final bool isActive;` (default `true`) to `User`.
   - Handled in `fromJson` (`json['is_active'] != false`), `toJson`, and `copyWith`.
   - `User.guest` sets `isActive: false`.

2. **New Model: `AccountStatus` ([`account_status.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/domain/account_status.dart)):**
   - Model matching backend `AccountStatus` response schema for `PATCH /api/v1/users/{id}`:
     - `id: String`, `email: String`, `name: String`, `isActive: bool`, `isAdmin: bool`.

3. **Auth Repository Updates ([`auth_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/data/auth_repository.dart)):**
   - Added `updateAccountStatus(String userId, {bool? isActive, bool? isAdmin})` contract to `IAuthRepository`.
   - Implemented in `ApiAuthRepository` sending `PATCH /api/v1/users/{userId}` with payload `{is_active, is_admin}`.
   - Implemented in `MockAuthRepository` with local state persistence and user update.

4. **Upload Service (`Content-Length` enforcement) ([`upload_service.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/services/upload_service.dart)):**
   - In `uploadToS3`: Explicitly passed `'Content-Length': fileBytes.length.toString()` alongside presigned `ticket.headers` (which now dynamically receives `"x-amz-tagging": "status=pending"`), preventing S3 403 size mismatch errors.

5. **API Exception Layer ([`api_exception.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/api/api_exception.dart)):**
   - Added typed `ServiceUnavailableException` (HTTP 503) representing temporary Cognito public key / network outages, enabling UI retry mechanisms.

---

## 3. Recommended UI Layer Changes (For Discussion Before Execution)

The following UI changes are recommended based on the updated backend contracts:

1. **Admin User Management Controls:**
   - On user profile or moderator modal: allow administrators (`currentUser.isAdmin`) to view an "Admin Controls" section to deactivate/reactivate users or promote students to admins.
2. **Deactivated Account Feedback:**
   - Display an informational warning banner or snackbar when a signed-in account is deactivated (HTTP 403 response).
   - Display a "Seller/Reporter account is no longer active" note in contact cards when `sellerContact == null` on posts by deactivated members.
3. **Owner/Admin Action Buttons:**
   - In `BuySellDetailDialog` and `LostFoundDetailDialog`, enable status change and editing controls if `isOwner || currentUser.isAdmin`.
4. **Cognito 503 Retry Toast:**
   - If an API request encounters HTTP 503 (`ServiceUnavailableException`), display a retry action button in the toast or feed rather than a fatal session expiry error.

---

## 4. Verification
- `flutter analyze`: **0 issues found** (0 errors, 0 warnings, 0 hints).
- `flutter test`: **25 / 25 automated tests passing** (100% pass rate).
