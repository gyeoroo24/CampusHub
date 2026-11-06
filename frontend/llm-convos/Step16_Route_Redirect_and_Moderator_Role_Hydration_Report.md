# Step 16: Route Redirect & Moderator Role Hydration Report

**Timestamp:** 2026-10-24T23:16:00+05:30  
**Status:** Complete & Verified  
**TestSuite:** 52/52 Tests Passing • 0 Flutter Analyze Issues  

---

## 1. Executive Summary

This update resolves two issues reported from testing:
1. **Root Path & 404 GoException Fix:** Visiting `/` or clicking "Home" from an invalid route threw `GoException: no routes for location: /`. A dedicated redirect route `/` -> `/app` and an `errorBuilder` fallback were implemented.
2. **Moderator Role & Controls Hydration Fix:** When signing in as an appointed moderator (such as `cadithya@iisc.ac.in` for Buy & Sell or `dinkylakhani@iisc.ac.in` for Lost & Found), the user identity was previously instantiated without their active moderator grants. The mock authentication repository now dynamically queries and hydrates active moderator grants and registered profile data upon sign-in and session re-validation. Furthermore, access to the governance screen (`/admin`) has been extended to moderators, providing direct access to the **Content Moderation Reports Queue (FR-10)** while safeguarding single-administrator actions.

---

## 2. Issues & Root Causes

### 2.1 Route Exception on Root Path (`/`)
* **Symptom:** Visiting the web root `http://.../` or clicking GoRouter's default "Home" link caused an unhandled route error: `GoException: no routes for location: /`.
* **Root Cause:** All routes were previously nested under `/app`, `/profile`, and `/admin`. GoRouter had no matching route or redirect defined for `/`, defaulting to an unhandled route exception.
* **Resolution:**
  - Added a root route with redirect in [`appRouter`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/router/app_router.dart#L24-L50):
    ```dart
    GoRoute(
      path: '/',
      redirect: (_, __) => '/app',
    ),
    ```
  - Configured `errorBuilder: (context, state) => const AppShellLayout()` to gracefully redirect any unhandled deep link directly into the primary application shell without rendering error screens.

---

### 2.2 Moderator Permissions & UI Controls Not Visible on Login
* **Symptom:** Logging in with `cadithya@iisc.ac.in` (listed as the Buy & Sell moderator in `MockAdminRepository`) resulted in a basic "Student" badge, `moderatorGrants: []`, no moderator indicators in the header, and no moderation controls on feed postings.
* **Root Cause:**
  - In `MockAuthRepository.verifyOtp()`, signing in constructed a generic `User` object that omitted active grants and registered user metadata.
  - In `MockAuthRepository.getCurrentUser()`, active grants were not refreshed when cached sessions or updated admin assignments changed.
  - In `AdminControlsScreen`, the security gate strictly checked `!currentUser.isAdmin`, completely locking out appointed moderators from accessing the Content Moderation Reports Queue.
* **Resolution:**
  - **Dynamic Grant & Profile Hydration:** Updated [`MockAuthRepository.verifyOtp()`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/data/auth_repository.dart#L192-L215) and [`MockAuthRepository.getCurrentUser()`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/data/auth_repository.dart#L90-L106) to query [`MockAdminRepository.getActiveGrantsForEmail()`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/data/admin_repository.dart#L151-L157) and [`MockAdminRepository.findRegisteredUser()`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/data/admin_repository.dart#L158-L164), properly attaching `moderatorGrants`, setting `isModerator: true`, and assigning `UserRole.moderator`.
  - **Live Auth Stream Notification:** In `getCurrentUser()`, triggered `_controller.add(_currentUser)` and invalidated `authStateProvider` during global refresh so Riverpod listeners instantly reflect permission changes.
  - **Moderator Panel Access:** Updated [`AdminControlsScreen`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/ui/admin_controls_screen.dart#L58-L108) security gate to permit both `currentUser.isAdmin` and `currentUser.isModerator`.
    - When a moderator enters, the view defaults to the **Reports Queue (FR-10)** tab.
    - Moderator Directory tab switches to view-only mode (disabling the promote form and demote buttons).
    - User Management tab displays a clear explanation that account suspension and admin handover require administrator privileges.
    - Responsive layout: Resolved a RenderFlex overflow on report resolution action buttons using responsive `Wrap`.
  - **App Bar & Profile Integration:**
    - App Bar dynamic action in [`app_router.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/router/app_router.dart#L322-L348): Displays `'Admin Panel'` (red badge) for Administrator, and `'Moderator'` (shield badge) for non-admin Moderators.
    - User Profile Screen in [`user_profile_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/profile/ui/user_profile_screen.dart#L140-L155): Added a `'Moderator Panel'` action in the app bar, a `MODERATOR` badge in the header, and an "Active Moderation Duties" card with a direct button to the Reports Queue.
    - Post Detail Dialogs: Moderators in Buy & Sell (`cadithya@iisc.ac.in`) now see the `Moderator: Remove Listing` button on listings by other authors.

---

## 3. Files Modified

| File | Changes |
| :--- | :--- |
| [`app_router.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/core/router/app_router.dart) | Added root route `/` redirect to `/app`, `errorBuilder` fallback, dynamic 'Moderator' action in AppBar, and auth stream invalidation on global refresh. |
| [`admin_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/data/admin_repository.dart) | Added `getActiveGrantsForEmail`, `findRegisteredUser`, `setAdmin`, and `resetMockData` helpers on `MockAdminRepository`. |
| [`auth_repository.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/auth/data/auth_repository.dart) | Hydrated `moderatorGrants` and registered profile in `_init()`, `getCurrentUser()`, and `verifyOtp()`; updated auth stream on session refresh; synchronized admin demotion. |
| [`admin_controls_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/admin/ui/admin_controls_screen.dart) | Allowed moderator access to Reports Queue; initialized tab at Reports Queue for moderators; restricted moderator promotion and account management to admin; fixed action buttons RenderFlex overflow. |
| [`user_profile_screen.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/lib/features/profile/ui/user_profile_screen.dart) | Added `MODERATOR` header badge, 'Moderator Panel' app bar action, and "Active Moderation Duties" card with direct navigation to reports queue. |
| [`admin_and_profile_test.dart`](file:///media/mukund-kukreja/Vol%20M/Academics/MTech/CSA/sem-3/DS252-Cloud-Computing/Project/campus_hub/CampusHub/frontend/test/admin_and_profile_test.dart) | Added automated tests for root route redirect, moderator role hydration on login, moderator access to governance reports queue, and isolated test mock data resets. |

---

## 4. Verification & Testing

### 4.1 Static Analysis
```bash
flutter analyze
# Analyzing frontend...
# No issues found! (ran in 1.1s)
```

### 4.2 Automated Test Execution
```bash
flutter test
# 00:09 +52: All tests passed!
```
- Total test count: 52 tests (all passing).
- Root path `/` redirects to `/app` without `GoException`.
- Logging in as `cadithya@iisc.ac.in` hydrates `isModerator == true`, `canModerateBuySell == true`, `canModerateLostFound == false`, and `UserRole.moderator`.
- Non-admin student accounts still receive the `Access Restricted` gate on `/admin`.
- Appointed moderators can open `/admin` and directly review the Reports Queue.
