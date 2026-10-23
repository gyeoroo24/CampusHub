# CampusHub: Project Context, Architecture & Session Handoff Guide

**Document Version:** 2.0  
**Last Updated:** 23 October 2026  
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
* **Guest Access:** Endpoints use `optional_user`. If a guest makes a request, the backend strips contact fields (`seller_contact` or `reporter_contact` are returned as `null`). The UI must protect student privacy by prompting guests to authenticate before showing contact info.

### 2.2 S3 Direct Binary Upload Flow
Direct 3-step client-to-S3 upload (no heavy binary transfer through FastAPI):
1. **Hash:** Frontend calculates SHA-256 Base64 checksum of file bytes.
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
│   │   └── sort_option.dart           # newest, oldest, priceLowHigh, priceHighLow
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
│       └── super_search_bar.dart      # Global cross-module search
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
│   │   ├── providers/buy_sell_providers.dart
│   │   └── ui/
│   │       ├── buy_sell_feed_screen.dart
│   │       └── widgets/
│   │           ├── buy_sell_grid_card.dart
│   │           ├── buy_sell_list_card.dart
│   │           ├── buy_sell_detail_dialog.dart   # Photo gallery, owner controls, privacy gate
│   │           └── create_listing_dialog.dart    # Dynamic categories, single price
│   │
│   └── lost_found/
│       ├── domain/lost_found_item.dart# LostFoundItem, PostType (lost/found), ReportStatus
│       ├── data/lost_found_dto.dart   # LostFoundReportDto
│       ├── data/lost_found_repository.dart # ILostFoundRepository, ApiLostFoundRepository, Mock...
│       ├── providers/lost_found_providers.dart # lostReportsProvider, foundReportsProvider, categories
│       └── ui/
│           ├── lost_found_feed_screen.dart
│           └── widgets/
│               ├── lost_found_column.dart
│               ├── lost_found_card.dart
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
* **Static Analysis:** `flutter analyze` runs with **0 errors, 0 warnings, 0 hints**.
* **Automated Tests:** `flutter test` executes **13 tests with 100% pass rate** (`data_layer_test.dart`, `ui_components_test.dart`, `widget_test.dart`).

---

## 5. Instructions for Running & Testing

To run Flutter commands in this Linux environment:
```bash
# Path to Flutter SDK on host:
export PATH="/media/mukund-kukreja/Installations/Programming/for-ubuntu/flutter/flutter/bin:$PATH"

# Analyze
cd CampusHub/frontend
flutter analyze

# Run all tests
flutter test

# Run app (Chrome / Desktop)
flutter run -d chrome
```

---

## 6. Roadmap & Recommended Next Steps

### Subsequent UI/UX Enhancements (Next Turn)
1. **Infinite Scrolling:** Wire `PaginatedResponse<T>` offset/limit queries to `ScrollController` in `BuySellFeedScreen` and `LostFoundColumn`.
2. **Native File/Camera Uploads:** Connect `UploadService` to `file_selector` or `image_picker` so users can attach real photos from disk.
3. **Search Input Debounce:** Add a 250–300ms debounce stream transformer to `SuperSearchBar`.
4. **Toast Feedback:** Replace snackbars with sleek floating toast notifications.

### Upcoming Backend Modules (Phases 2 & 3)
* **Module 3:** Academic Help (`/api/v1/academic/courses`, past papers, lecture notes).
* **Module 4:** Discussion Forums & Placement Hub (`/api/v1/forums`, `/api/v1/placement`).
* **Module 5:** In-App Notifications & Direct Chat (`/api/v1/me/notifications`, WebSocket / chat routes).
