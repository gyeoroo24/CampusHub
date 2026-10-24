# CampusHub: Step 11 Live Backend Integration & Connectivity Report

**Date:** 24 October 2026  
**Backend Target URL:** `http://10.217.103.203:8000`  
**S3/MinIO Storage URL:** `http://10.217.103.203:9000`  
**Developer Security Key:** `kSH3AyYRCzXn8Czy8xXCZbC9`  
**Mock Data Setting:** `useMockData = false` (Default active in `AppConfig`)  
**Test Suite Status:** 30 / 30 Automated Tests Passing (100%)  
**Static Code Analysis:** `flutter analyze` 0 issues (clean)

---

## 1. Executive Summary

We established a live connection between the Flutter frontend and the backend FastAPI instance running on the teammate's laptop across the local network at `http://10.217.103.203:8000`.

### Key Connectivity Findings:
1. **Network Authentication Protocol (`X-Dev-Key`)**:
   - The remote backend enforces a custom developer security scheme for non-localhost callers: `X-Dev-Key: kSH3AyYRCzXn8Czy8xXCZbC9`.
   - When paired with `X-Dev-User: <iisc_email>`, the live FastAPI backend verifies network authorization and automatically provisions the user row in its PostgreSQL database.
2. **Mock Backend Deactivation**:
   - Switched `AppConfig.useMockData` default from `true` to `false`.
   - Updated `AppConfig.apiBaseUrl` default to `http://10.217.103.203:8000`.
   - Added `AppConfig.devKey` default to `kSH3AyYRCzXn8Czy8xXCZbC9`.
3. **End-to-End Live Validation**:
   - Categories loaded live from remote PostgreSQL: `books`, `bottle`, `cycles`, `hello`.
   - Direct HTTP operations verified end-to-end: Listing Creation (`POST`), Feed Listing (`GET`), Detail Retrieval (`GET /api/v1/listings/{id}`), Status Update (`PATCH /api/v1/listings/{id}/status`), and Soft Deletion (`DELETE /api/v1/listings/{id}`).
   - Privacy Gating: Confirmed live backend returns `seller_contact: null` to unauthenticated guests and reveals contact info once authenticated.
4. **S3/MinIO Presigned Upload Verification**:
   - Calling `POST /api/v1/uploads` generates presigned PUT tickets targeting the backend teammate's MinIO storage at `http://10.217.103.203:9000/campushub-uploads/...`.

---

## 2. Code Changes Implemented

### 2.1 Configuration Layer (`lib/core/constants/app_config.dart`)
- Set `useMockData` to default to `false`.
- Set `apiBaseUrl` to default to `http://10.217.103.203:8000`.
- Added `devKey` set to `kSH3AyYRCzXn8Czy8xXCZbC9` with `--dart-define=DEV_KEY` override capability.

### 2.2 Network Client Layer (`lib/core/api/api_client.dart`)
- Updated `ApiClient` interceptor to attach `X-Dev-Key: AppConfig.devKey` to all requests targeting the backend base URL.
- Added automatic injection of `X-Dev-User: <email>` and `X-Dev-Name: <name>` when a session is active in token storage.
- Allowed overriding `devKey` per `ApiClient` instance.

### 2.3 Authentication Layer (`lib/features/auth/data/auth_repository.dart`)
- In `ApiAuthRepository.verifyOtp`, immediately persist user credentials so the subsequent call to `getCurrentUser()` via `GET /api/v1/me` successfully carries the `X-Dev-User` and `X-Dev-Key` headers.
- Refined `getCurrentUser()` to check saved user profiles alongside tokens.

### 2.4 Test Suite Hardening (`test/widget_test.dart` & `test/ui_components_test.dart`)
- Decoupled offline widget and UI unit tests from global `AppConfig.useMockData` state by injecting `MockBuySellRepository()` and `MockLostFoundRepository()` via provider overrides.
- Ensures unit and widget tests remain fast, offline, and independent of laptop network availability.

### 2.5 Live Integration Test Suite (`test/live_backend_integration_test.dart`)
Created an automated end-to-end live integration test executing 5 scenarios directly against `http://10.217.103.203:8000`:
- **Scenario 1:** Backend connectivity & category fetching (`GET /api/v1/buy-sell/categories`).
- **Scenario 2:** Unauthenticated guest feed browsing (`GET /api/v1/listings`).
- **Scenario 3:** User dev sign-in & PostgreSQL user creation (`GET /api/v1/me`).
- **Scenario 4:** End-to-end listing lifecycle: Create (`POST`), Query (`GET`), Status Update (`PATCH`), and Delete (`DELETE`).
- **Scenario 5:** Lost & Found feed and category connectivity.

---

## 3. Recommended Manual Integration Scenarios for UI Testing

To run the application against the live backend:
```bash
cd CampusHub/frontend
flutter run -d chrome
```

### Scenario 1: Guest Browsing & Category Loading
1. Open the web app without signing in.
2. Verify that the category pills under the search bar show the live categories from the backend database: **Books**, **Bottle**, **Cycles**, **Hello**.
3. Observe the initial feed: if empty, verify the clean empty state message is displayed.

### Scenario 2: Student Sign-In Flow
1. Click the **Sign In** button in the top right corner.
2. Enter your IISc email: e.g., `kmukund@iisc.ac.in`.
3. When prompted for OTP, enter any 6 digits (e.g. `123456`) and click **Verify**.
4. Observe the user avatar in the top app bar updating to display your initials/name.
5. Click on the profile button to view your registered profile: verify that the backend assigned a valid UUID and your IISc email.

### Scenario 3: Create a Live Buy & Sell Listing
1. Click **+ Sell Item** in the category row (or bottom-right FAB on mobile).
2. Fill in:
   - **Title**: e.g. "Reinforcement Learning: An Introduction (Sutton & Barto)"
   - **Category**: Select **Books** (from the live categories dropdown).
   - **Price**: ₹550
   - **Location**: e.g. "Department of CSA / Library"
   - **Description**: "2nd Edition, hardcover, clean pages."
3. Click **Post Listing**.
4. Verify that the listing appears immediately in the live feed.

### Scenario 4: Privacy Gate Verification
1. Click on the newly created item card to open the detail dialog.
2. As the authenticated seller, verify that your email (`kmukund@iisc.ac.in`) is displayed with the copy button.
3. Now open the profile dialog, click **Sign Out**, and view the item again as a Guest.
4. Verify that the contact email is hidden and replaced with the *“Sign in with your IISc account to contact this seller”* banner.

### Scenario 5: Status Update & Moderation
1. Sign back in with `kmukund@iisc.ac.in`.
2. Open your listing's detail modal.
3. Click **Mark Reserved** or **Mark Sold**.
4. Verify that the status badge updates to "Reserved" or "Sold".
5. Click **Delete Listing** and confirm.
6. Verify the card disappears from the live listing feed.
