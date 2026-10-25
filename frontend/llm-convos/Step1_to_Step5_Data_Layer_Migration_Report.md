# CampusHub Frontend: Backend Data Layer Migration Report (Steps 1 to 5)

**Date:** 23 October 2026  
**Author:** Pair Programming Assistant (Antigravity) & Mukund Kukreja  
**Scope:** Data Layer Alignment with Backend Branch `origin/add-backend-and-docs` (Phase 1)  
**Status:** Completed & Verified (`flutter analyze`: 0 issues, `flutter test`: 10/10 passing)

---

## 1. Executive Summary & Objectives

The backend engineering team completed Phase 1 of the FastAPI backend in `origin/add-backend-and-docs` (69 endpoints, PostgreSQL Revision 5 schema, AWS Cognito auth, S3 direct presigned uploads). 

Our goal was to pause frontend UI development and refactor the **data layer** across **Auth**, **File Uploads**, **Categories**, **Buy & Sell**, and **Lost & Found** to strictly adhere to the real backend contracts without introducing compilation errors or breaking existing UI screens.

All non-UI files (models, DTOs, repositories, services, endpoints, network client) have been upgraded to match the backend specification while preserving backward-compatible getters and constructors for existing UI widgets until Step 6.

---

## 2. Architectural & Code Quality Refinements (SOLID Principles)

1. **Separation of Concerns (Single Responsibility):**
   * Upload mechanics (computing base64 SHA-256 digest, requesting presigned S3 tickets, direct HTTP binary PUT) were extracted into a dedicated `UploadService`, removing upload logic from domain repositories.
   * Distinct DTOs handle serialization/deserialization with resilience against missing or legacy fields.
2. **Open-Closed Principle (OCP):**
   * Domain models (`ListingItem`, `LostFoundItem`) encapsulate both backend-canonical properties (`price`, `categoryRef`, `seller`, `photos`, `occurredAt`, `kind`) and legacy computed accessors (`sellingPrice`, `costPrice`, `category`, `imageUrls`, `title`, `eventTime`) so existing UI continues to function without changes.
   * Standardized pagination is decoupled into `PaginatedResponse<T>` (`items`, `limit`, `offset`, `hasMore`).
3. **Interface Segregation & Dependency Inversion:**
   * `IBuySellRepository` and `ILostFoundRepository` abstract data operations with clear contracts implemented by `Api...` and `Mock...` classes, wired via Riverpod providers.
   * `ApiClient` avoids adding `Authorization` headers when PUTting raw binary streams to external presigned S3 URLs, preventing S3 signature mismatch errors.

---

## 3. Step-by-Step Migration Breakdown

### Step 1: Core Networking & Shared Models
* **Shared Models Created (`lib/core/models/`):**
  * `category_ref.dart`: Minimal representation of a category (`id: int`, `name: String`).
  * `user_ref.dart`: Minimal representation of a user in summaries (`id: String`, `name: String`).
  * `contact.dart`: Contact information (`email: String`, `phone: String?`) exposed only to signed-in IISc users.
  * `photo.dart`: Attached photo metadata (`s3Key: String`, `url: String`, `sortOrder: int`).
  * `page.dart`: `PaginatedResponse<T>` matching FastAPI `Page[T]` (`items`, `limit`, `offset`, `hasMore`). Renamed to avoid colliding with Flutter's Navigator `Page<T>`.
* **Endpoints Updated (`lib/core/api/api_endpoints.dart`):**
  * Profile: `/api/v1/me`, `/api/v1/users/{id}`
  * Uploads: `/api/v1/uploads`
  * Categories: `/api/v1/buy-sell/categories`, `/api/v1/lost-found/categories`
  * Buy & Sell: `/api/v1/listings`, `/api/v1/listings/{id}`, `/api/v1/listings/{id}/status`, `/api/v1/listings/{id}/photos`
  * Lost & Found: Symmetrically split into `/api/v1/lost-reports` and `/api/v1/found-reports`
  * Moderation & Reports: `/api/v1/reports`, `/api/v1/me/reports`, `/api/v1/reports/{id}/resolve`, `/api/v1/moderators`
  * Notifications: `/api/v1/me/notifications`, `/api/v1/me/devices`
* **ApiClient Updated (`lib/core/api/api_client.dart`):**
  * Added `put<T>()` method.
  * Added support for `X-Dev-User` and `X-Dev-Name` headers for local dev testing without AWS Cognito setup.
  * Guarded against injecting `Bearer` tokens into external S3 presigned URLs.

---

### Step 2: S3 Direct Upload Utility & Service
* **Created `lib/core/services/upload_service.dart`:**
  * Implemented `UploadTicket` model.
  * Added `UploadService.computeSha256Base64(Uint8List bytes)` using `crypto` package.
  * Implemented `getUploadTicket()` calling `POST /api/v1/uploads`.
  * Implemented `uploadToS3()` for direct binary streaming to S3.
  * Provided high-level workflows: `uploadPhoto()` and `uploadMultiplePhotos()`.
  * Registered `uploadServiceProvider` in Riverpod.

---

### Step 3: Auth & Identity Data Layer Refactoring
* **Domain Model (`lib/features/auth/domain/user.dart`):**
  * Implemented `ModeratorGrant` domain entity (`id`, `module`, `scopeType`, `departmentId`, `courseId`, `grantedAt`).
  * Updated `User` model to reflect `MyProfile`: `id`, `email`, `name`, `phone`, `departmentId`, `programme`, `graduationYear`, `isAdmin`, `moderatorGrants`.
  * Added scoped permission helpers: `canModerateBuySell`, `canModerateLostFound`, `canModerateDepartment(deptId)`, `canModerateCourse(courseId)`.
* **Repository (`lib/features/auth/data/auth_repository.dart`):**
  * Added `updateProfile(...)` calling `PATCH /api/v1/me`.
  * In `ApiAuthRepository`, streamlined session restoration via `GET /api/v1/me`.
  * Updated `MockAuthRepository` with realistic mock IISc credentials and grants.

---

### Step 4: Buy & Sell Data Layer Refactoring
* **Domain Model (`lib/features/buy_sell/domain/buy_sell_item.dart`):**
  * Replaced split pricing with single `price: double`.
  * Converted plain string category to `categoryRef: CategoryRef`.
  * Converted seller to `seller: UserRef` and `sellerContact: Contact?`.
  * Added `coverPhotoUrl: String?` and `photos: List<Photo>`.
  * Dual constructor supporting new canonical fields and legacy fields (`costPrice`, `sellingPrice`, `imageUrls`, `category`).
* **DTO (`lib/features/buy_sell/data/buy_sell_dto.dart`):**
  * Maps `ListingSummary` and `ListingDetail`.
  * Generates `toCreateJson(photoKeys: ...)` matching backend `ListingCreate`.
  * Generates `toUpdateJson()` matching backend `ListingUpdate`.
* **Repository (`lib/features/buy_sell/data/buy_sell_repository.dart`):**
  * Added `fetchListingsPage(...)` returning `PaginatedResponse<ListingItem>`.
  * Added `updateListing(...)`, `replacePhotos(...)`, `deleteListing(reason: ...)`.
  * Added category management: `fetchCategories()`, `createCategory()`.
  * Updated both `ApiBuySellRepository` and `MockBuySellRepository`.

---

### Step 5: Lost & Found Data Layer Refactoring
* **Domain Model (`lib/features/lost_found/domain/lost_found_item.dart`):**
  * Replaced status with `ReportStatus` (`open`, `matched`, `closed`).
  * Removed backend title requirement, using `categoryRef: CategoryRef` (what item is) and `description` (distinguishing marks).
  * Converted time to `occurredAt: DateTime`.
  * Added `possibleMatches: List<LostFoundItem>?` for match notifications on filing.
  * Dual constructor supporting legacy `type`, `title`, `eventTime`, `dateReported`, `reporterContact`.
* **DTO (`lib/features/lost_found/data/lost_found_dto.dart`):**
  * Maps `ReportSummary` and `ReportDetail`.
  * Serializes `toCreateJson()` matching `ReportCreate`.
  * Parses `possible_matches` returned on creation.
* **Repository (`lib/features/lost_found/data/lost_found_repository.dart`):**
  * Symmetrically routes calls to `/lost-reports` or `/found-reports` based on `PostType`.
  * Added `fetchReportsPage(...)` returning `PaginatedResponse<LostFoundItem>`.
  * Added `updateReport(...)`, `replacePhotos(...)`, `updateStatus(...)`, `deleteReport(reason: ...)`.
  * Added category management: `fetchCategories()`, `createCategory()`.
  * Updated both `ApiLostFoundRepository` and `MockLostFoundRepository`.

---

## 4. Verification & Test Execution Results

1. **Static Analysis (`flutter analyze`):**
   ```
   Analyzing frontend...
   No issues found! (ran in 1.1s)
   ```
2. **Unit & Data Layer Tests (`flutter test`):**
   ```
   00:02 +10: All tests passed!
   - Auth Data Layer: Roles and scoped permissions
   - Auth Data Layer: Session persistence and OTP
   - Upload Service: Base64 SHA-256 digest validation
   - Buy & Sell: FastAPI schema parsing and pagination
   - Buy & Sell: Filters, pricing, and status updates
   - Lost & Found: FastAPI schema parsing and category refs
   - Lost & Found: Symmetrical feeds and match simulation
   - DateTimeFormatter: ISO formatting and relative times
   - UI Smoke Tests: Desktop and mobile responsiveness
   ```

---

## 5. Next Steps for Step 6 (UI Alignment)

When ready to proceed with Step 6, the following UI adjustments can be executed:
1. **`create_listing_dialog.dart`:**
   * Remove "Cost Price" field (PRD and backend only use selling price).
   * Load categories dynamically from `fetchCategories()` dropdown with an "Other (Add new)" option.
   * Integrate `UploadService` to show progress bars during S3 photo upload before publishing.
2. **`report_item_dialog.dart`:**
   * Remove "Title" text field; present the Category selector as the item name (e.g. "Water Bottle", "Earbuds", "ID Card").
   * Replace freeform time string with a date-time picker setting `occurredAt`.
   * Display a "Possible Matches" dialog if `possibleMatches` is non-empty upon submitting a report.
3. **Detail Dialogs & Cards:**
   * Display "Sign in to view contact details" state when `sellerContact` / `reporterContact` is null (guest view).
   * Update badges to reflect `matched` / `closed` for reports and `reserved` / `sold` for listings.
