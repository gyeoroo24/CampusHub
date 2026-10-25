# CampusHub: Step 12 Single-Admin Hand-Over, Global Refresh Button & UI Synchronization Report

**Date:** 24 October 2026  
**Backend Branch:** `origin/add-backend-and-docs` (Synchronized with commit `bc8e7e7`)  
**Active Mode:** Mock Mode (`useMockData = true` by default in `AppConfig`)  
**Static Analysis:** `flutter analyze` — 0 issues (clean)  
**Automated Tests:** 30 / 30 passing (100%)

---

## 1. Executive Summary

This iteration accomplishes four major goals requested:
1. **Mock Backend Re-activation & Multi-Backend Switch Guide:**
   - Switched `AppConfig.useMockData` default back to `true`, and set `AppConfig.apiBaseUrl` back to `http://localhost:8000`.
   - Provided clear, documented instructions on switching between mock mode, local FastAPI, and teammate LAN servers both via code edits and via command-line `--dart-define` parameters.
2. **Backend Architecture Synchronization (Commit `bc8e7e7`):**
   - Synchronized with the backend's new **single-admin hand-over** mechanism:
     - The database enforces `CREATE UNIQUE INDEX uq_users_single_admin ON users ((true)) WHERE base_role = 'admin'`.
     - `PATCH /api/v1/users/{id}` now strictly handles account deactivation/reactivation (`{"is_active": bool}`). Passing `is_admin` is forbidden (`extra="forbid"`).
     - Added endpoint `POST /api/v1/users/{id}/make-admin` to transfer the single admin role to a successor, demoting the caller in the same transaction.
   - Refactored `IAuthRepository`, `ApiAuthRepository`, and `MockAuthRepository` to implement `updateAccountStatus(userId, {required bool isActive})` and `transferAdminRole(targetUserId)`.
3. **Global Server Data & Permissions Refresh Button:**
   - Added an animated `AppRefreshButton` placed directly to the left of the Light/Dark mode toggle in the `AppBar`.
   - Tapping it smoothly rotates the refresh icon, re-fetches the user profile and permissions from `/api/v1/me`, and refreshes Buy & Sell and Lost & Found feeds and categories.
   - Any updated authority (e.g. admin promotion/demotion) re-evaluates all UI elements across the application in real time.
4. **All Postponed UI Changes Implemented:**
   - **Admin Management in Account Dialog:** Added dedicated administrative management controls in the user profile dialog for administrators to toggle student account activation and execute the single-admin role transfer.
   - **Deactivated Poster Privacy Notice:** If a poster's account has been deactivated, authenticated viewers now see an informative notice (*“Seller/Reporter account is currently deactivated by campus administration. Contact details are unavailable.”*) instead of an inaccurate guest sign-in gate.
   - **Admin Status & Deletion Permissions:** Detail dialogs in Buy & Sell and Lost & Found now grant status management and moderation deletion controls to administrators as well as item owners.
   - **Transient Cognito 503 Outage Handling:** Added graceful error messaging in `AuthDialog` for HTTP 503 Service Unavailable responses during Cognito JWKS sync outages.

---

## 2. How to Switch Backends

### Method A: Via Command-Line Flags (Recommended for testing without editing code)
When running or building Flutter, pass `--dart-define` flags:

- **Run in Mock Mode (Default):**
  ```bash
  flutter run -d chrome
  # Or explicitly:
  flutter run -d chrome --dart-define=USE_MOCK=true
  ```

- **Connect to Teammate's Server on Local Network:**
  ```bash
  flutter run -d chrome \
    --dart-define=USE_MOCK=false \
    --dart-define=API_BASE_URL=http://10.217.103.203:8000 \
    --dart-define=DEV_KEY=kSH3AyYRCzXn8Czy8xXCZbC9
  ```

- **Connect to Local FastAPI on Your Machine (`127.0.0.1:8000`):**
  ```bash
  flutter run -d chrome \
    --dart-define=USE_MOCK=false \
    --dart-define=API_BASE_URL=http://localhost:8000
  ```

### Method B: Directly in Code
Open `frontend/lib/core/constants/app_config.dart` and modify:
```dart
// To use mock data:
static const bool useMockData = true;

// To connect to a live backend:
static const bool useMockData = false;
static const String apiBaseUrl = 'http://10.217.103.203:8000'; // Or http://localhost:8000
static const String devKey = 'kSH3AyYRCzXn8Czy8xXCZbC9';
```

---

## 3. Detailed Changes by Layer

### 3.1 Constants & Endpoints
- `frontend/lib/core/constants/app_config.dart`:
  - Reset `useMockData` to default to `true`.
  - Reset `apiBaseUrl` to default to `'http://localhost:8000'`.
- `frontend/lib/core/api/api_endpoints.dart`:
  - Added `static String userMakeAdmin(String id) => '$version/users/$id/make-admin';`

### 3.2 Authentication & Domain Layer
- `frontend/lib/features/auth/data/auth_repository.dart`:
  - In `IAuthRepository`: Changed signature of `updateAccountStatus(userId, {required bool isActive})` and added `transferAdminRole(targetUserId)`.
  - In `MockAuthRepository`: Added stateful single-admin transfer: demotes current admin and assigns admin role to successor.
  - In `ApiAuthRepository`: Calls `PATCH /api/v1/users/{userId}` with `{"is_active": isActive}` and `POST /api/v1/users/{userId}/make-admin`.

### 3.3 UI Layer
- `frontend/lib/core/router/app_router.dart`:
  - Created `AppRefreshButton` with continuous rotation animation during async reload, placed left of `ThemeToggleButton`.
  - Added `Admin Management Controls` section in `_showAccountDialog` when `currentUser.isAdmin` is true.
  - Added `_showDeactivateUserDialog` allowing admins to toggle active state of any user.
  - Added `_showTransferAdminDialog` with warning prompt and single-admin role handover logic.
- `frontend/lib/features/buy_sell/ui/widgets/buy_sell_detail_dialog.dart`:
  - Enabled status update chips for admins (`isOwner || (currentUser?.isAdmin ?? false)`).
  - Added deactivated seller warning card when `item.sellerContact == null` for authenticated students.
- `frontend/lib/features/lost_found/ui/widgets/lost_found_detail_dialog.dart`:
  - Enabled status update chips for admins (`isOwner || (currentUser?.isAdmin ?? false)`).
  - Added deactivated reporter warning card when `item.reporterContact == null` for authenticated students.
- `frontend/lib/features/auth/ui/auth_dialog.dart`:
  - Catches `ServiceUnavailableException` (HTTP 503) and displays friendly retry messaging.

---

## 4. Test Suite Verification
- `flutter analyze`: **0 issues found!**
- `flutter test`: **30 / 30 tests passing (100%)** across:
  - `data_layer_test.dart` (User permissions, single-admin transfer, DTOs, SHA-256)
  - `ui_components_test.dart` (Dialogs, pagination notifiers)
  - `widget_test.dart` (Smoke tests, responsiveness, refresh button, admin controls)
  - `live_backend_integration_test.dart` (Configured with flexible network timeout)
