# CampusHub: Project Context, Architecture & Session Handoff Guide

**Document Version:** 3.1  
**Last Updated:** 24 October 2026  
**Project:** CampusHub — Cloud Computing Course Project (DS252), MTech CSA, Indian Institute of Science (IISc), Bangalore.  
**Repository Branch Context:**
* `origin/frontend` (Current local branch: `frontend`): Flutter client codebase.
* `origin/add-backend-and-docs`: Complete FastAPI backend, PostgreSQL schema (Revision 5), OpenAPI specs, and system diagrams.

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
│   │   └── date_time_formatter.dart   # Relative & absolute date formatting
│   └── widgets/
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
* **Static Analysis:** `flutter analyze` runs with **0 errors, 0 warnings, 0 hints**.
* **Automated Tests:** `flutter test` executes **21 tests with 100% pass rate** (`data_layer_test.dart`, `ui_components_test.dart`, `widget_test.dart`).

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
