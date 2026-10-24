# CampusHub: Project Context, Architecture & Session Handoff Guide

**Document Version:** 3.7  
**Last Updated:** 24 October 2026  
**Project:** CampusHub — Cloud Computing Course Project (DS252), MTech CSA, Indian Institute of Science (IISc), Bangalore.  
**Repository Branch Context:**
* `origin/frontend` (Current local branch: `frontend`): Flutter client codebase.
* `origin/add-backend-and-docs`: Complete FastAPI backend, PostgreSQL schema (Revision 5 + Review Fixes commit `bc8e7e7`), OpenAPI specs, and system diagrams.

---

## 1. Project Overview & Team Roles

CampusHub is a unified campus portal built for IISc students and faculty.
* **Team Division (4 members):**
  * **Frontend (User / Author):** Mukund Kukreja — Flutter client (Web, Desktop, Mobile).
  * **Backend (2 members):** FastAPI, asyncpg, PostgreSQL, AWS Cognito, Amazon S3.
  * **Cloud Infrastructure (1 member):** AWS deployments, Docker, Terraform/CloudFormation, CI/CD.

### Strict Project Constraints
> [!CAUTION]
> **No Remote Pushes:** Under no circumstances should automated git pushes (`git push`) be performed to the remote repository. All local work stays unstaged or in local commits until explicitly directed by the user.

---

## 2. Backend Architecture & API Contracts

The backend implementation was inspected from `origin/add-backend-and-docs`. Key backend mechanisms:

### 2.1 Authentication & Dev Mode
* **Production Auth:** AWS Cognito User Pool with IISc domain whitelist (`@iisc.ac.in`). The frontend passes the **Cognito ID Token** (not Access Token) as `Authorization: Bearer <id_token>`.
* **Local Dev Mode:** When testing locally against the FastAPI backend, it accepts `X-Dev-User: email@iisc.ac.in` and `X-Dev-Name: Full Name` headers to bypass Cognito.
* **Guest Access:** Endpoints use `optional_user`. If a guest makes a request, the backend strips contact fields (`seller_contact` or `reporter_contact` are returned as `null`). The UI protects student privacy by prompting guests to authenticate with an `@iisc.ac.in` account before revealing contact info.

### 2.2 S3 Direct Binary Upload Flow
Direct 3-step client-to-S3 upload (no heavy binary transfer through FastAPI):
1. **Hash:** Frontend calculates SHA-256 Base64 checksum of file bytes (`UploadService.computeSha256Base64`).
2. **Ticket:** Calls `POST /api/v1/uploads` with `{ "content_type": "image/jpeg", "content_length": <bytes>, "checksum_sha256": "<base64>", "kind": "listing_photo" | "lost_report_photo" | "found_report_photo" }`. Receives `{ "s3_key": "...", "upload_url": "https://s3...presigned..." }`.
3. **Upload:** Client makes direct HTTP `PUT` of the raw binary stream to `upload_url` with header `x-amz-checksum-sha256: <base64>` and `Content-Type`. **Crucial:** `ApiClient` strips any `Authorization: Bearer` header for S3 URLs to prevent AWS signature mismatch.
4. **Link:** Pass `photo_keys: [s3_key]` in listing or report creation payloads.

### 2.3 Domain Schemas & Rules

#### Buy & Sell Module (FR-4, FR-5, FR-6, FR-10)
* **Routes:** `/api/v1/listings`, `/api/v1/listings/{id}`, `/api/v1/listings/{id}/status`, `/api/v1/listings/{id}/photos`, `/api/v1/buy-sell/categories`.
* **Pricing:** Single canonical `price: double` (rupees Decimal). There is **no cost price** in the backend.
* **Status:** `available`, `reserved`, `sold`.
* **Categories:** `CategoryRef(id: int, name: String)`.
* **Photos:** `Photo(s3_key: String, url: String, sort_order: int)`.
* **Moderation:** Moderators with `canModerateBuySell` can delete listings with a reason audit log.

#### Lost & Found Module (FR-7, FR-8, FR-9, FR-10)
* **Routes:** Symmetrically divided into `/api/v1/lost-reports` and `/api/v1/found-reports`.
* **No Title Field:** In the backend schema, reports have **no title**. An item is identified by what it is (`category: CategoryRef`) and distinguishing details (`description: String`).
* **Incident Time (`occurred_at`):** Must be an ISO 8601 timestamp with timezone in the past (`occurred_at <= now() + 5 min`). Future dates are rejected with HTTP 422.
* **Status:** `open`, `matched`, `closed`.
* **Automatic Matching (FR-9):** On report creation, the backend inspects open reports of the opposite kind in the same category. It returns `possible_matches: list[ReportSummary]`. The frontend displays this immediately in an interactive modal.

---

## 3. Frontend Architecture Map

```
CampusHub/frontend/lib/
├── core/
│   ├── api/
│   │   ├── api_client.dart            # Dio/HTTP client supporting Bearer & X-Dev headers
│   │   └── api_endpoints.dart         # Canonical FastAPI route paths
│   ├── constants/
│   │   └── app_config.dart            # useMockData toggle, dev user configs
│   ├── enums/
│   │   ├── date_preset.dart           # all, today, yesterday, last3Days, thisWeek, thisMonth
│   │   ├── sort_option.dart           # newest, oldest, priceLowHigh, priceHighLow
│   │   └── view_mode.dart             # grid, list
│   ├── models/
│   │   ├── category_ref.dart          # CategoryRef(id, name)
│   │   ├── user_ref.dart              # UserRef(id, name)
│   │   ├── contact.dart               # Contact(email, phone)
│   │   ├── photo.dart                 # Photo(s3Key, url, sortOrder)
│   │   └── page.dart                  # PaginatedResponse<T>(items, limit, offset, hasMore)
│   ├── services/
│   │   └── upload_service.dart        # 3-step S3 presigned PUT service
│   ├── utils/
│   │   ├── date_time_formatter.dart   # Relative & absolute date formatting
│   │   ├── web_history_support.dart   # Browser back-button modal interception
│   │   ├── web_history_web.dart       # Web implementation (pushState/popstate)
│   │   └── web_history_stub.dart      # Non-web no-op stub
│   └── widgets/
│       ├── compact_date_range_picker_dialog.dart # Custom date range dialog
│       ├── compact_price_range_picker_dialog.dart# Custom min/max price dialog
│       ├── no_photo_placeholder.dart  # Responsive intentional no-photo placeholder
│       ├── photo_carousel.dart        # Interactive gallery with Hero animation
│       ├── skeleton_loader.dart       # ShimmerLoadingCard, SkeletonGrid, SkeletonList
│       └── super_search_bar.dart      # Global search with 300ms debounce & clear button
│
├── features/
│   ├── auth/
│   │   ├── domain/user.dart           # User entity, ModeratorGrant, role helpers
│   │   ├── data/auth_repository.dart  # IAuthRepository, ApiAuthRepository, MockAuthRepository
│   │   ├── providers/auth_providers.dart
│   │   └── ui/auth_dialog.dart        # OTP login modal & guest sign-in gate
│   │
│   ├── buy_sell/
│   │   ├── domain/buy_sell_item.dart  # ListingItem, ListingStatus
│   │   ├── data/buy_sell_dto.dart     # BuySellListingDto (JSON serializers)
│   │   ├── data/buy_sell_repository.dart # IBuySellRepository, ApiBuySellRepository, Mock...
│   │   ├── providers/buy_sell_providers.dart # PaginatedFeedState, BuySellPaginationNotifier
│   │   └── ui/
│   │       ├── buy_sell_feed_screen.dart # Infinite scroll, spotlight banner, category pills
│   │       └── widgets/
│   │           ├── buy_sell_grid_card.dart     # Hero thumbnail, verified badge, INR chip
│   │           ├── buy_sell_list_card.dart     # Modern list card with owner controls
│   │           ├── buy_sell_detail_dialog.dart # Photo gallery, owner controls, privacy gate
│   │           └── create_listing_dialog.dart  # Dynamic categories, single price
│   │
│   └── lost_found/
│       ├── domain/lost_found_item.dart# LostFoundItem, PostType (lost/found), ReportStatus
│       ├── data/lost_found_dto.dart   # LostFoundReportDto
│       ├── data/lost_found_repository.dart # ILostFoundRepository, ApiLostFoundRepository, Mock...
│       ├── providers/lost_found_providers.dart # LostFoundPaginationNotifier (lost & found feeds)
│       └── ui/
│           ├── lost_found_feed_screen.dart
│           └── widgets/
│               ├── lost_found_column.dart      # Infinite scroll, skeleton loaders, mobile ListView
│               ├── lost_found_card.dart        # Grid card with Hero thumbnail, incident time, status pills
│               ├── lost_found_list_card.dart   # List card with 120x100 thumbnail, status, metadata wrap
│               ├── lost_found_filter_bar.dart
│               ├── lost_found_detail_dialog.dart # Status controls, privacy gate, mod actions
│               └── report_item_dialog.dart       # Titleless, past datetime picker, FR-9 match modal
```

---

## 4. Current State & Verification

* **Data Layer (Steps 1–5):** Completely aligned with FastAPI backend. Clean DTOs, proper error handling, mock and API implementations.
* **UI Layer & Cleanup (Step 6):**
  * All backward compatibility shims (`sellingPrice`, `costPrice`, `imageUrls`, `title` on reports, `eventTime`) have been **completely deleted**.
  * Domain models are canonical and type-safe.
  * UI widgets fully support single price, titleless reports, past datetime picker, dynamic categories, contact privacy gating, and owner status controls.
* **UI/UX Modern Overhaul & Pagination (Step 7):**
  * Generic `PaginatedFeedState<T>` and `StateNotifier` infinite scroll feeds for Buy & Sell (page size 8) and Lost & Found (page size 6).
  * 300ms search debouncing with inline activity spinner and instant clear button.
  * Hero animations connecting cards to `PhotoCarousel` in detail dialogs.
  * Responsive shimmering skeleton loaders (`ShimmerLoadingCard`, `SkeletonGrid`, `SkeletonList`).
  * Modern marketplace layout: spotlight hero banner, emoji category chips, quick price filters, responsive mobile-friendly layouts (no RenderFlex overflow down to 375px width).
  * Iteration 7.1 visual polish: BnS tiles include description snippet & seller row (no wasted whitespace), unified `displayTitle` for LnF cards and dialogs, and upgraded type-safe user account dialog with role pills.
  * Iteration 7.2 manual UI alignment & mobile parity:
    * Integrated commit `5ecead0` manual UI changes (removed redundant banners, merged Sell Item button into category pills row). Wrapped category chips in `Expanded` and adjusted mobile label (`'Sell'`) and padding to ensure 0 overflows.
    * Added dismissible "x" button to "Trusted Campus Exchange" info bar; banner now only appears when user manually logs in via OTP during the session (`showTrustedExchangeBannerProvider`) and stays dismissed until the next manual login.
    * Added full LnF filter parity: `DatePresetFilter` chips ("All", "Today", "Yesterday", "Last 3 Days", "This Week", "This Month"), unified sort dropdown matching BnS, and implemented responsive `LostFoundListCard` with list view toggle.
    * Mobile and desktop split-column layout hardened with `Wrap` and `ConstrainedBox` across both modules to prevent any `RenderFlex` overflows on narrow widths down to 375px.
  * Iteration 7.3 button relocation & custom price range:
    * Relocated "+ Report Lost" and "+ Report Found" action buttons into the category pills row with spaceBetween in `LostFoundFilterBar`.
    * Removed redundant boxed column header bars from `LostFoundColumn`.
    * Added custom rupee icon (`Icons.currency_rupee_rounded`) in `BuySellFeedScreen` toolbar opening `CompactPriceRangePickerDialog` with quick presets and min/max inputs, matching the LnF custom date range picker.
  * Iteration 7.4 / Step 8 UI card refinements, mobile enhancements & back-button support:
    * Removed green ticks and "Verified" text across cards and user modals (authentication is ubiquitous).
    * Restructured BnS (`BuySellGridCard`) & LnF (`LostFoundCard`) tiles: status badge on top-left of photo, time on top-right, category chip above title, description expands into available whitespace, seller/location row, and pinned full-width contact copy button at card bottom.
    * Disambiguated LnF title from description by adding an optional `title` field to `LostFoundItem` and `LostFoundReportDto`, updating mock reports with distinct titles and descriptions.
    * Clean dialog aesthetics: pure white background (`Colors.white`, `surfaceTintColor: Colors.transparent`) across detail dialogs, creation/report dialogs, and custom price/date pickers on both mobile and desktop.
    * Replaced grid/list icons with Large View (`Icons.view_agenda_outlined`) and Compact View (`Icons.density_medium_rounded`).
    * Redesigned compact list cards (`BuySellListCard`, `LostFoundListCard`): thumbnail status badge (top-left), space-between price/category row, bottom metadata row (Location - User - Time) with responsive `Flexible` wrapping.
    * Mobile Layout Revamp:
      * Embedded `SuperSearchBar` directly into mobile `AppBar`'s `title`, freeing vertical screen space by removing redundant header text and separate body search container.
      * Replaced inline creation buttons on mobile with Floating Action Buttons: BnS has bottom-right FAB ("Sell"), LnF has dual bottom-left ("Lost") and bottom-right ("Found") FABs with responsive compact labels.
      * Horizontal left/right tab transition animations matching bottom navigation bar navigation.
      * Compact TabBar for mobile Lost & Found items (height 36px, horizontal icon + text).
      * Web history navigation: Implemented `ModalHistoryWrapper` via `dart:html` `window.history.pushState` / `popstate` to intercept browser back-button presses and dismiss active modals without exiting the web application.
  * Iteration 7.5 / Step 9 Modal Refinements, Multi-Photo Dummy Data & Placeholders:
    * Backend Phone Number Verification: Confirmed backend stores optional phone numbers in `users` table (`phone TEXT`), exposed in `Contact(email, phone)` for authenticated users. Maintained `phone` in models and detail dialogs.
    * Multi-Photo Support: Added multiple photos (2–4 photos) across mock listings and reports, enabling dot and arrow navigation in `PhotoCarousel`. Designated items with zero photos to test placeholder logic.
    * BnS Detail Modal Restructuring: Small category badge above title (matching LnF modal), removed "Description" heading, inserted price and seller-location row between title and description with `spaceBetween`, and relocated listed timestamp to the bottom of the modal.
    * Responsive `NoPhotoPlaceholder`: Designed adaptive placeholder that distinguishes deliberate absence of photos from image load failures across grid cards, compact list cards, and modal carousels.
    * Responsive Module Page Transitions: Vertical slide transitions for desktop (`Offset(0, ±0.08)`); horizontal slide transitions for mobile (`Offset(±0.12, 0)`).
    * Restored Dark Mode Modal Backgrounds: Set modal backgrounds to `isDark ? const Color(0xFF1E293B) : Colors.white` with `surfaceTintColor: Colors.transparent` across all custom dialogs and modals.
  * Iteration 7.6 / Step 10 Backend Review Fixes Sync (Commit `3a7aa05`) & Data Layer Realignment:
    * Synchronized with backend changes in `origin/add-backend-and-docs`:
      1. Admin User Management: Added `AccountStatus` model (`id`, `email`, `name`, `isActive`, `isAdmin`) and implemented `updateAccountStatus(userId, {isActive, isAdmin})` in `IAuthRepository`, `ApiAuthRepository` (`PATCH /api/v1/users/{user_id}`), and `MockAuthRepository`.
      2. User Active State: Extended `User` model with `isActive: bool` flag (default `true`, `false` for guest) and JSON serialization.
      3. S3 Binary Upload Compliance: Hardened `UploadService` to include explicit `Content-Length` header in presigned `PUT` upload requests, while supporting new backend-supplied `x-amz-tagging: status=pending` headers.
      4. AWS Cognito Outage Handling: Added `ServiceUnavailableException` (HTTP 503) to `ApiException` hierarchy to support frontend retries when backend Cognito public key fetching temporarily fails.
      5. Deactivated Member Contact Privacy: Verified backend behavior masking contacts (`null`) for deactivated users; frontend models gracefully handle `null` contact info without crashes.
      6. Extended Admin Edit Permissions: Backend now authorizes admins to edit listings/reports and update listing status across modules.
  * Iteration 7.7 / Step 11 Live FastAPI Backend Integration & LAN Dev Auth:
    * Verified live connectivity to teammate server at `http://10.217.103.203:8000`.
    * Implemented team LAN authentication: injected `X-Dev-Key` (`kSH3AyYRCzXn8Czy8xXCZbC9`) and session `X-Dev-User` / `X-Dev-Name` in `ApiClient` interceptors.
    * Added comprehensive automated live integration test (`live_backend_integration_test.dart`) verifying categories, guest browsing, user auth, listing lifecycle (create, query, status update, delete), and lost/found feeds directly against the live backend server.
  * Iteration 7.8 / Step 12 Single-Admin Handover, Global Refresh & Full UI Synchronization (Commit `bc8e7e7`):
    * Switched `AppConfig.useMockData` default back to `true` (mock mode), with `apiBaseUrl` set to `http://localhost:8000`.
    * Synchronized with backend single-admin architecture (`POST /api/v1/users/{id}/make-admin` and `PATCH /api/v1/users/{id}` with `is_active` only): implemented in `IAuthRepository`, `ApiAuthRepository`, and `MockAuthRepository`.
    * Added animated `AppRefreshButton` on left of Theme toggle in `AppBar`, refetching `/me` and reloading all feeds and user authority.
    * Added administrative controls inside user profile dialog (deactivate/activate account and transfer single admin role).
    * Updated `BuySellDetailDialog` and `LostFoundDetailDialog` to display deactivated poster notices for inactive accounts, and enabled status change/moderation actions for administrators.
    * Added friendly retry handling for transient AWS Cognito 503 errors in `AuthDialog`.
  * **Step 13 (Filter Overhaul, Dynamic Categories, Seller Edit/Delete, Phone Contacts):**
    * Overhauled Buy & Sell toolbar: "All" chip, vertical dividers, toggle price presets (`Under ₹500`, `₹500 - ₹2,000`, `₹2,000+`), custom price range active chip, and multi-select toggle status chips (`Available`, `Reserved`, `Sold Out`).
    * Refactored category scrollbars across both modules to dynamically watch backend categories (`buySellCategoriesProvider` and `lostFoundCategoriesProvider`) with immediate reflection upon creation via "+ Add New Category...".
    * Added Seller & Moderator Edit and Delete flows: created `EditListingDialog` and `EditReportDialog` with feed refreshes; wired deletion confirmation dialogs.
    * Integrated dual contact buttons (Email and Phone copy/call) across `BuySellGridCard`, `LostFoundCard`, and detail dialogs whenever a phone number is provided.
  * **Step 14 (AlertDialog Viewport Intrinsic Dimension Fix & Test Suite Expansion):**
    * Diagnosed and fixed `RenderShrinkWrappingViewport does not support returning intrinsic dimensions` in `report_item_dialog.dart:459` by replacing loose `ConstrainedBox` with responsive, bounded `SizedBox(width: dialogWidth, height: dialogHeight)` and disabling `shrinkWrap` on the `ListView`.
    * Enforced author-only permissions in `BuySellDetailDialog` and `LostFoundDetailDialog`, masking contact buttons on cards ("Email"/"Call") for student privacy.
  * **Step 15 (Admin Controls Page, Rich User Profile, Email-Based Governance & Possible Matches Navigation):**
    * Built full `AdminControlsScreen` (`/admin`): 5 tabs covering Moderator promotion/demotion by IISc Email ID (FR-3), single-admin handover and account activation/deactivation by email, content moderation reports queue (FR-10), campus categories governance, and system telemetry health canary.
    * Built rich `UserProfileScreen` (`/profile`): user details header with role badges, profile update form (`PATCH /api/v1/me`: name, phone, programme, graduation year), and personal postings activity hub across Buy & Sell, Lost reports, and Found reports with quick Edit, Status toggle, and Delete actions.
    * Wired Possible Matches section into `LostFoundDetailDialog` for both Lost posts and Found posts with 1-click tap-to-inspect navigation.
* **Static Analysis:** `flutter analyze` runs with **0 errors, 0 warnings, 0 hints**.
* **Automated Tests:** `flutter test` executes **49 tests with 100% pass rate** (`data_layer_test.dart`, `ui_components_test.dart`, `widget_test.dart`, `live_backend_integration_test.dart`, `filter_and_seller_actions_test.dart`, `admin_and_profile_test.dart`).

---

## 5. Instructions for Running & Testing

To run Flutter commands in this Linux environment:
```bash
# Path to Flutter SDK on host:
export PATH="/media/mukund-kukreja/Installations/Programming/for-ubuntu/flutter/flutter/bin:$PATH"

# Static code analysis
cd CampusHub/frontend
flutter analyze

# Run all automated tests
flutter test

# Run app (Chrome / Desktop)
flutter run -d chrome
```

---

## 6. Roadmap & Recommended Next Steps

### Subsequent UI/UX Enhancements (Next Iterations)
1. **Native File/Image Picker:** Connect `UploadService` to `file_selector` or `image_picker` so users can pick images from local disk/gallery during listing or report creation.
2. **Toast Feedback:** Introduce sleek, animated floating snackbars / toast banners for creation, update, and deletion feedback.
3. **Filter Drawer / Slide-Over Modal:** Convert the advanced filter popup on mobile into a slide-over bottom sheet.

### Upcoming Backend Modules (Phases 2 & 3)
* **Module 3:** Academic Help (`/api/v1/academic/courses`, past papers, lecture notes).
* **Module 4:** Discussion Forums & Placement Hub (`/api/v1/forums`, `/api/v1/placement`).
* **Module 5:** In-App Notifications & Direct Chat (`/api/v1/me/notifications`, WebSocket / chat routes).
