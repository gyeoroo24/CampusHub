# Step 17: Router Overhaul, Moderator Privacy, Scoped Category Governance & Clean UI

**Date:** 25 October 2026  
**Status:** Completed & Fully Verified (52/52 tests passing, 0 analyzer issues)

---

## 1. Problem Statement & User Requirements

The user requested 6 critical architectural and UI fixes:
1. **Broken Router & URL Behavior:**
   - Typing anything after `/app/` and pressing enter did nothing (screen stayed frozen or hit an unhandled route).
   - Typing `http://localhost:<port>/buy` caused a hard reload appending `#/app` (`/buy#/app`) and reverted to the default homepage.
   - Opening `/` threw `GoException: no routes for location: /` with a dead `Home` link.
2. **Moderator Visibility Restriction (Confidentiality Policy):**
   - Non-admin moderators must **not** see other moderators in the app (neither their assignments nor their contact cards).
   - Non-admin moderators should **only** see who the active Campus Administrator is (name, email, phone, contact action) in case they need to escalate issues.
3. **Category Governance & Module Scope Restrictions:**
   - Moderators must not add, edit, or delete categories for modules they do not moderate (e.g. Buy & Sell moderators cannot modify Lost & Found categories, and vice versa).
   - Authorized moderators of a module must be empowered to **add**, **edit (rename)**, and **delete** categories, not just add them.
4. **Category Emojis Consistency:**
   - Categories must display emojis on module feed pages (`Buy & Sell` feed, `Lost & Found` feed), but **not** in the admin/moderator panel.
   - Clean category names without emoji in admin/moderator panel.
5. **Remove PRD Citations from UI:**
   - Clean all user-visible strings, headers, tabs, dialogs, and notifications by removing explicit citations like `PRD §3.1`, `(FR-3)`, `(FR-10)`, `(NFR-4)`.
6. **LnF Status Filter Chips & "Matched" State Clarification:**
   - Add `Open`, `Matched`, and `Resolved` quick filter presets in Lost & Found similar to `Available`, `Reserved`, `Sold Out` in Buy & Sell.
   - Clarified and preserved `matched` state in accordance with the backend schema (`ReportStatus = Literal["open", "matched", "closed"]`).

---

## 2. Root Cause Analysis

### 2.1 URL Hash & Routing Flaws
- **Default Flutter Web URL Strategy:** Flutter web defaults to hash-based routing (`HashUrlStrategy`), where client routes live after `#/`. Direct browser navigations to `/buy` caused the local web server to deliver `index.html`, and Flutter web, finding no hash, appended `#/app` and rendered the default route.
- **GoRouter Configuration:** `appRouter` was previously defined with a single monolithic `/app` path using in-memory state switching. Path changes in the browser address bar for `/buy`, `/lost-found`, or `/app/<anything>` were unrecognized, throwing `GoException` or matching a fallback that left the UI out of sync.

### 2.2 Moderator Roles & Permissions
- When logging in as `cadithya@iisc.ac.in` (the designated Buy & Sell moderator in `MockAdminRepository`), `_buildInitialUsers()` did not assign initial `moderatorGrants` on the user object, and `ApiAuthRepository` dev fallback did not hydrate mock grants for known moderators.
- Non-admin moderators navigating to Admin Controls were previously presented with the full list of all active moderator grants in the campus, violating the confidentiality policy.

---

## 3. Implementation Details

### 3.1 Clean HTML5 History & Direct Route Definitions
- **`pubspec.yaml` & `main.dart`:**
  - Added `flutter_web_plugins: sdk: flutter` dependency.
  - Initialized `usePathUrlStrategy()` in `main.dart` before `runApp`.
- **`lib/core/router/app_router.dart`:**
  - Defined explicit top-level routes:
    - `/buy` -> `AppShellLayout(initialTab: 0)`
    - `/lost-found` -> `AppShellLayout(initialTab: 1)`
    - `/profile` -> `UserProfileScreen()`
    - `/admin` -> `AdminControlsScreen()`
  - Configured intelligent redirects:
    - `/` -> `/buy`
    - `/app` -> `/buy`
    - `/app/:subpath` -> redirects to `/lost-found` if `subpath` contains `'lost'`, `'lnf'`, or `'found'`; otherwise `/buy`
    - `/buy-sell` -> `/buy`
    - `/lost_found` and `/lnf` -> `/lost-found`
    - `errorBuilder` -> `AppShellLayout(initialTab: 0)`
  - Updated `AppShellLayout` to accept `initialTab` and keep URL synchronization bidirectionally intact:
    - When user selects a tab, `context.go(newIndex == 0 ? '/buy' : '/lost-found')` updates the URL cleanly without hashes.
    - When user navigates directly via URL or browser history, `AppShellLayout` synchronizes `tabIndexProvider` with `widget.initialTab`.

### 3.2 Category Emoji Helper (`CategoryEmojiHelper`)
- Created `lib/core/utils/category_emoji_helper.dart` providing:
  - `cleanName(String raw)`: Strips any leading emojis, symbols, and extra whitespace.
  - `getEmoji(String categoryName)`: Returns a contextual, deterministic emoji based on the category's semantics (e.g., `Books` -> 📚, `Cycles` -> 🚲, `Electronics` -> 💻, `ID Cards` -> 🪪, etc.).
  - `withEmoji(String categoryName)`: Returns the formatted display name (`Emoji CleanTitle`) for feed pills.
- Updated feed screens (`buy_sell_feed_screen.dart`, `lost_found_filter_bar.dart`) to show `withEmoji(name)` for all preset and dynamic user-created categories.
- Updated admin/moderator panel (`admin_controls_screen.dart`) to display clean names without emojis (`cleanName(name)`).

### 3.3 Scoped Category Governance (Add, Edit, Delete)
- **Repository Interface & Implementations:**
  - Added `updateCategory(int id, String newName)` and `deleteCategory(int id)` to `BuySellRepository`, `MockBuySellRepository`, `ApiBuySellRepository`, `LostFoundRepository`, `MockLostFoundRepository`, and `ApiLostFoundRepository`.
- **`AdminControlsScreen` Category Tab:**
  - Computed module permissions:
    - `canManageBuySell = currentUser.isAdmin || currentUser.canModerateBuySell`
    - `canManageLostFound = currentUser.isAdmin || currentUser.canModerateLostFound`
  - Restricts the "Add Category" module dropdown to only the modules the current user is authorized to manage.
  - If a user can manage that module:
    - Renders an `InputChip` for each category with an edit icon and delete `✕` icon.
    - Tapping the chip opens `_showEditCategoryDialog` to rename the category.
    - Tapping `✕` opens `_confirmDeleteCategory` with a confirmation dialog before deletion.
  - If a user cannot manage that module:
    - Renders a read-only `Chip` with a lock icon.

### 3.4 Moderator Confidentiality & Admin Contact Card
- In `_buildModeratorsTab` of `AdminControlsScreen`:
  - If the user is an **Administrator** (`isUserAdmin == true`), they have full visibility into the active moderator assignments list, promotion by IISc email, and revocation actions.
  - If the user is a **Moderator** (`isUserAdmin == false`):
    - Hides all other moderators completely.
    - Displays the **Campus Administrator Contact Card** with the active Administrator's name, email, phone number, "Copy Email Address" action, and a governance confidentiality notice.
    - Re-labels the tab to `'Admin Contact'`.

### 3.5 Authentication & Dev Hydration for Moderators
- In `MockAdminRepository`:
  - Hydrated `cadithya@iisc.ac.in` with active `ModeratorGrant` for `buy_sell`.
  - Hydrated `dinkylakhani@iisc.ac.in` with active `ModeratorGrant` for `lost_found`.
  - Hydrated `mohammadazam@iisc.ac.in` with active `ModeratorGrant` for `academic_help`.
  - Synced `_mockUsers` on `grantModerator` and `revokeModerator`.
- In `ApiAuthRepository`:
  - In `verifyOtp` and `getCurrentUser`, added fallback to local mock grants if the live backend does not have assignments seeded in dev mode.
- In `AppShellLayout`:
  - Added "Open Moderator Controls" button in the account popup dialog for appointed moderators.

### 3.6 UI Clean-Up (Removing PRD Citations)
- Removed all citations from tab headers (`Moderators (FR-3)` -> `Moderators`, `Reports Queue (FR-10)` -> `Reports Queue`).
- Cleaned single-admin description and system telemetry canary status cards (`(PRD & backend)` and `(NFR-4)` removed).

---

## 4. Verification & Testing

- **Static Analysis:**
  ```bash
  flutter analyze
  # Output: No issues found! (ran in 1.0s)
  ```
- **Automated Test Suite:**
  ```bash
  flutter test
  # Output: All 52 tests passed!
  ```
  Verified all tests across:
  - `admin_and_profile_test.dart`: Admin email promotion, admin handover, account deactivation, moderator access, admin contact privacy view, category add/edit/delete.
  - `widget_test.dart`: Desktop smoke test, mobile responsive layout, custom price range dialog, Lost & Found date filters, compact/large view toggles, trusted exchange banner.
  - `ui_components_test.dart`: Modals, pagination notifiers, match dialog viewports.
  - `data_layer_test.dart`: Domain entities, permissions, filtering contracts.
  - `live_backend_integration_test.dart`: Connectivity to backend server.

---

## 5. Files Changed

- [`frontend/lib/core/utils/category_emoji_helper.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/utils/category_emoji_helper.dart) *(New)*
- [`frontend/lib/core/router/app_router.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/router/app_router.dart)
- [`frontend/lib/features/admin/data/admin_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/data/admin_repository.dart)
- [`frontend/lib/features/admin/ui/admin_controls_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/ui/admin_controls_screen.dart)
- [`frontend/lib/features/auth/data/auth_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/data/auth_repository.dart)
- [`frontend/lib/features/buy_sell/data/buy_sell_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/buy_sell/data/buy_sell_repository.dart)
- [`frontend/lib/features/buy_sell/data/mock_buy_sell_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/buy_sell/data/mock_buy_sell_repository.dart)
- [`frontend/lib/features/buy_sell/data/api_buy_sell_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/buy_sell/data/api_buy_sell_repository.dart)
- [`frontend/lib/features/buy_sell/ui/buy_sell_feed_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/buy_sell/ui/buy_sell_feed_screen.dart)
- [`frontend/lib/features/lost_found/data/lost_found_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/lost_found/data/lost_found_repository.dart)
- [`frontend/lib/features/lost_found/data/mock_lost_found_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/lost_found/data/mock_lost_found_repository.dart)
- [`frontend/lib/features/lost_found/data/api_lost_found_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/lost_found/data/api_lost_found_repository.dart)
- [`frontend/lib/features/lost_found/providers/lost_found_providers.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/lost_found/providers/lost_found_providers.dart)
- [`frontend/lib/features/lost_found/ui/widgets/lost_found_filter_bar.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/lost_found/ui/widgets/lost_found_filter_bar.dart)
- [`frontend/lib/features/profile/ui/user_profile_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/profile/ui/user_profile_screen.dart)
- [`frontend/lib/main.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/main.dart)
- [`frontend/pubspec.yaml`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/pubspec.yaml)
- [`frontend/test/admin_and_profile_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/admin_and_profile_test.dart)
- [`frontend/test/widget_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/widget_test.dart)
