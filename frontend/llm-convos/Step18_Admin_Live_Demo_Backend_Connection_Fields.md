# Step 18: Admin Live Demo Backend & Database Connection Fields

**Date:** 25 October 2026  
**Status:** Completed & Fully Verified (54/54 tests passing, 0 analyzer issues)

---

## 1. Problem Statement & User Requirements

The user requested:
> "for admin user add temporary input fields to take in input the base url and whatever other info like secret key and all is required to connect a database. this is to get the frontend to connect to backend for a demo while the backend is hosted on a teammates laptop."

### Key Objectives:
1. **Dynamic Runtime Backend Switching:**
   - Allow an Admin user to easily toggle between **Mock In-Memory Data** and a **Live FastAPI Backend Server** running on a teammate's laptop or local machine, with zero app reloads or code recompilation required.
2. **Comprehensive Connection Configuration Form:**
   - **FastAPI Server Base URL:** With quick presets for common demo targets:
     - Teammate Laptop: `http://10.217.103.203:8000`
     - Localhost: `http://localhost:8000`
     - Loopback IP: `http://127.0.0.1:8000`
   - **Developer Secret Key (`X-Dev-Key`):** Allows entering the dev bypass key (e.g. `kSH3AyYRCzXn8Czy8xXCZbC9`) with show/hide password visibility toggle.
   - **Test User Email Identity (`X-Dev-User`):** Injected into requests to allow testing as specific identities (e.g. `kmukund@iisc.ac.in` [Admin], `mukund@iisc.ac.in`, `cadithya@iisc.ac.in` [Moderator]).
   - **Database Connection URI Reference:** For referencing the live PostgreSQL database (e.g. `postgresql://postgres:password@10.217.103.203:5432/campushub`).
3. **Interactive Live Health & Connectivity Verification:**
   - A dedicated button that pings `<baseUrl>/health` (which verifies both the FastAPI HTTP server and the live PostgreSQL database via `SELECT 1`) and `<baseUrl>/api/v1/buy-sell/categories`.
   - Real-time diagnostic output showing roundtrip latency, HTTP status codes, and endpoint statuses.
4. **Immediate Reactivity across Repositories & Feeds:**
   - When connection settings are saved, Riverpod providers (`serverConfigProvider`, `apiClientProvider`, `authRepositoryProvider`, `buySellRepositoryProvider`, `lostFoundRepositoryProvider`, `adminRepositoryProvider`) dynamically invalidate and rebind to the active backend.
5. **Admin-Only Visibility & AppBar Status Badge:**
   - Non-admins and guests cannot see connection controls or backend details.
   - For Admins, a prominent status badge in the top AppBar displays `[Mock Mode]` (in neutral grey/slate with amber indicator) or `[Live: 10.217.103.203:8000]` (in emerald green with green indicator). Tapping the badge opens the Backend Settings tab directly (`/admin?tab=4`).

---

## 2. Architecture & Implementation

### 2.1 State Management: `ServerConfig` & `serverConfigProvider`
- **Location:** [`CampusHub/frontend/lib/core/config/server_config.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/config/server_config.dart)
- Created an immutable `ServerConfig` data class:
  ```dart
  class ServerConfig {
    final bool useMockData;
    final String apiBaseUrl;
    final String devKey;
    final String devUserEmail;
    final String? databaseUrl;
    String get baseUrl => apiBaseUrl;
    ...
  }
  ```
- Backed by `ServerConfigNotifier` with `SharedPreferences` persistence:
  - Settings survive browser reloads during presentations and live demos.
  - Automatically updates `AppConfig.useMockData`, `AppConfig.apiBaseUrl`, and `AppConfig.devKey` static variables for backwards compatibility with legacy non-Riverpod calls.

### 2.2 Dynamic Riverpod Provider Invalidation
Each feature repository provider now observes `serverConfigProvider`:
- **[`auth_providers.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/providers/auth_providers.dart):** Reconstructs `ApiClient` with the new base URL and dev credentials, switching between `MockAuthRepository` and `ApiAuthRepository`.
- **[`buy_sell_providers.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/buy_sell/providers/buy_sell_providers.dart):** Switches between `MockBuySellRepository` and `ApiBuySellRepository`.
- **[`lost_found_providers.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/lost_found/providers/lost_found_providers.dart):** Switches between `MockLostFoundRepository` and `ApiLostFoundRepository`.
- **[`admin_providers.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/providers/admin_providers.dart):** Switches between `MockAdminRepository` and `ApiAdminRepository`.

### 2.3 Live Demo Connection Card & Health Tester in Admin Controls
- **Location:** [`CampusHub/frontend/lib/features/admin/ui/admin_controls_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/ui/admin_controls_screen.dart)
- Under the `Backend & Health` tab (Tab 5), a new card `Live Demo Backend & Database Connection` is rendered if `currentUser.isAdmin`:
  - Mode SegmentedButton: `Mock In-Memory` vs `Live Backend Server`.
  - Input field for Base URL with quick-select chips (`Teammate Laptop`, `Localhost`, `127.0.0.1`).
  - Secret key field with visibility toggle and quick paste capability.
  - Test identity selector with chips (`kmukund@iisc.ac.in`, `mukund@iisc.ac.in`, `cadithya@iisc.ac.in`).
  - Database URI field (verifiable via `/health` database query `SELECT 1`).
  - Connectivity tester that calculates real roundtrip latency and displays verified endpoint metrics in a color-coded status banner.
  - `Save & Apply Backend` and `Reset to Default Mock` action buttons.

### 2.4 Top AppBar Status Pill & Direct Deep Linking
- **Location:** [`CampusHub/frontend/lib/core/router/app_router.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/router/app_router.dart)
- Rendered in the top AppBar for Administrators:
  - If Mock: Amber circle with `Mock Mode`.
  - If Live: Emerald green circle with `Live: 10.217.103.203:8000`.
  - Clicking this badge navigates straight to `/admin?tab=4` (`Backend & Health`).
  - `AdminControlsScreen` updated with optional `initialTab` parameter to facilitate direct deep linking from any route.

---

## 3. Verification & Test Results

### 3.1 Static Analysis
Executed `flutter analyze CampusHub/frontend`:
```
Analyzing frontend...
No issues found! (ran in 1.0s)
```

### 3.2 Automated Test Execution
Executed full test suite (`cd CampusHub/frontend && flutter test`):
```
00:10 +54: All tests passed!
```
- **Total Tests Passed:** 54 / 54 tests (100% pass rate).
- **Key Test Suites Verified:**
  - [`test/admin_and_profile_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/admin_and_profile_test.dart): Verified email-based moderator operations, user account management, single admin handover, role hydration, `ServerConfig` entity updates, and `AdminControlsScreen(initialTab: 4)` rendering of all connection input fields and buttons.
  - [`test/widget_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/widget_test.dart): Desktop smoke test, mobile responsive layout (375x667), account dialog, filter interactions.
  - [`test/data_layer_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/data_layer_test.dart): Filter combinations, status filtering, category handling.
  - [`test/ui_components_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/ui_components_test.dart): Pagination and dialog rendering.
  - [`test/live_backend_integration_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/live_backend_integration_test.dart): End-to-end integration and connectivity scenarios.
