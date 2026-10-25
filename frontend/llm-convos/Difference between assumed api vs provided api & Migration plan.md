
 Backend architecture utilizes FastAPI, asyncpg, PostgreSQL, and AWS Cognito/S3 for authentication, data storage, and file uploads. The initial phase features 69
  endpoints, encompassing user authentication/profile management, secure file uploads via presigned S3 URLs, and fundamental buy/sell functionalities.
  
  
  Examining the API structure, several modules emerge: Buy & Sell, Lost & Found, Academic Help, Forums, Reports & Moderation, and Notifications & Devices,
  indicating a feature-rich platform. Considering the schema, I note that a total of 33 tables and 12 enums support the data model, along with a view.
  
  The API follows specific conventions including UUIDs for most IDs, integer category IDs, and pagination using `limit` and `offset`. Rupee prices are handled as
  strings/Decimals, and timestamps adhere to ISO-8601 format. Authentication relies on Cognito ID tokens, with local development using specific headers for user
  context.
  
  
  Buy/Sell and Lost/Found categories are managed separately, reflected in distinct API endpoints for each resource type. Data models for Buy/Sell listings show a
  clear separation between summarized card views and detailed listing views, supporting efficient data retrieval and display. The Lost & Found functionality is
  implemented using two separate endpoints for reports.
  
  
  Analyzing the frontend codebase requirements, the `ApiEndpoints` need updating to reflect the backend's resource paths, and the `ApiClient` necessitates a
  `put<T>()` method for PUT requests. An authentication header interceptor must support both Cognito tokens and a dev header for local testing. A reusable
  pagination model and an S3 upload service, computing checksums and interacting with the `/uploads` endpoint, are also required.
  
  
  The `User` domain model should be expanded to align with the `MyProfile` data, and the legacy authentication endpoints deprecated due to backend reliance on
  Cognito. Permission evaluation needs refinement, moving from a flat list of roles to module-specific checks.
  
  Buy/Sell model adjustments are needed to remove the `costPrice`, separate listing views (or unify with proper photo handling), adapt the category data, and
  accommodate nullable `sellerContact`. The repository query parameters require changes to match the backend convention, with adjustments to the photo upload
  process, category management, and photo replacement endpoints.
  
  For Lost & Found, the `title` field in the report model appears redundant and can likely be removed or auto-generated, and the status enum needs to be changed
  to reflect "open" values.

  I have thoroughly reviewed the PRD (Cloud_Computing_Project-updated_PRD.pdf) and inspected the backend code, OpenAPI contracts, and documentation uploaded by 
  the backend team in the origin/add-backend-and-docs branch (specifically docs/api-reference.md, backend/db/schema.sql, and FastAPI router implementations).   
                                                                                                                                                                
  Here is the complete report covering what the backend team has exposed, how it differs from our initial frontend assumptions, and the roadmap of changes      
  needed in our frontend codebase before making any code modifications.                                                                                         
  ──────                                                                                                                                                        
  ## 1. Summary of Backend Architecture & Design Decisions                                                                                                      
                                                                                                                                                                
  ### A. Authentication & User Model                                                                                                                            
                                                                                                                                                                
  • No Custom Backend Auth Endpoints: The backend does not expose /auth/login, /auth/send-otp, or /auth/refresh. Authentication is handled directly by AWS      
  Cognito.                                                                                                                                                      
  • Token Standard: The backend requires the Cognito ID Token (not the access token) in the Authorization: Bearer <ID_TOKEN> header.                            
  • Auto-Provisioning: Users are automatically provisioned in PostgreSQL on their first signed-in call (validated against IISc domains *@iisc.ac.in).           
  • Local Dev Authentication: The backend accepts X-Dev-User: name@iisc.ac.in and optionally X-Dev-Name: Asha headers, allowing testing without live Cognito    
  credentials.                                                                                                                                                  
  • Role Management:                                                                                                                                            
      • Base roles: Guest (no token), Signed-in User, Admin (is_admin: true).                                                                                   
      • Moderator roles are stored dynamically in moderator_assignments and returned under moderator_grants in GET /me. Revocations take effect immediately on  
      the next call.                                                                                                                                            
  • Privacy: Contact details (seller_contact, reporter_contact, user contact) return null for unauthenticated guests (scenario 1 in PRD).                       
                                                                                                                                                                
  ### B. Standard Conventions Across Endpoints                                                                                                                  
                                                                                                                                                                
  • Base URL: http://localhost:8000/api/v1                                                                                                                      
  • Pagination: Standardized Page<T> structure:                                                                                                                 
    {                                                                                                                                                           
      "items": [...],                                                                                                                                           
      "limit": 20,                                                                                                                                              
      "offset": 0,                                                                                                                                              
      "has_more": true                                                                                                                                          
    }                                                                                                                                                           
  (Query parameters: limit [default 20, max 50] and offset [default 0]. There is no page or total count).                                                       
  • Identifiers: Standard UUID strings, except category IDs which are integers (int).                                                                           
  • Timestamps: ISO-8601 strings with timezone (e.g., 2026-10-23T12:18:55Z).                                                                                    
  • Prices: Decimal string representation in INR (e.g., "1500.00").                                                                                             
                                                                                                                                                                
  ### C. Direct S3 File Upload Flow (3-Step Pattern)                                                                                                            
                                                                                                                                                                
  Photo uploads do not pass file bytes through FastAPI:                                                                                                         
                                                                                                                                                                
  1. Request Ticket: POST /api/v1/uploads with kind (listing_photo, lost_report_photo, found_report_photo, course_material), content_type, size_bytes, and      
  checksum_sha256 (Base64 of SHA-256 digest).                                                                                                                   
  2. Direct S3 Upload: App directly performs HTTP PUT of raw binary bytes to upload_url with the exact headers returned (Content-Type, x-amz-checksum-sha256).  
  3. Attach S3 Keys: App sends photo_keys: [s3_key1, s3_key2, ...] when creating or editing the post (max 10 photos, first photo acts as cover photo).          
  ──────                                                                                                                                                        
  ## 2. API Endpoints & Exposed Data Models                                                                                                                     
                                                                                                                                                                
  ### A. Categories (Buy & Sell and Lost & Found)                                                                                                               
                                                                                                                                                                
  Categories are separated per module. Users can dynamically add a category (matching is case-insensitive, trimmed).                                            
                                                                                                                                                                
  • Endpoints:                                                                                                                                                  
      • GET /api/v1/buy-sell/categories & POST /api/v1/buy-sell/categories                                                                                      
      • GET /api/v1/lost-found/categories & POST /api/v1/lost-found/categories                                                                                  
  • Data Model (CategoryRef):                                                                                                                                   
    {                                                                                                                                                           
      "id": 1,                                                                                                                                                  
      "name": "Cycles"                                                                                                                                          
    }                                                                                                                                                           
                                                                                                                                                                
  ──────                                                                                                                                                        
  ### B. Buy & Sell Module                                                                                                                                      
                                                                                                                                                                
  #### Endpoints                                                                                                                                                
                                                                                                                                                                
   Method │ Path                         │ Auth                │ Description
  ────────┼──────────────────────────────┼─────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────
   GET    │ /api/v1/listings             │ Guest / User        │ Browse listings. Query params: q, category_id, min_price, max_price, status (repeatable),
          │                              │                     │ seller_id, limit, offset
   POST   │ /api/v1/listings             │ User                │ Create a listing with pre-uploaded photo_keys
   GET    │ /api/v1/listings/{id}        │ Guest / User        │ Retrieve full listing details (with seller_contact if signed in)
   PATCH  │ /api/v1/listings/{id}        │ Owner               │ Update title, description, price, category_id, location
   PATCH  │ /api/v1/listings/{id}/status │ Owner               │ Update status: "available" | "reserved" | "sold"
   PUT    │ /api/v1/listings/{id}/photos │ Owner               │ Replace photo list with ordered photo_keys
   DELETE │ /api/v1/listings/{id}        │ Owner / Mod / Admin │ Soft-delete listing (moderators can provide ?reason=...)
                                                                                                                                                                
  #### Schemas                                                                                                                                                  
                                                                                                                                                                
  • ListingSummary (Returned in lists / feed cards):                                                                                                            
    {                                                                                                                                                           
      "id": "uuid",                                                                                                                                             
      "title": "Bicycle Helmet",                                                                                                                                
      "price": "500.00",                                                                                                                                        
      "status": "available",                                                                                                                                    
      "location": "E-Block",                                                                                                                                    
      "category": { "id": 1, "name": "Cycles" },                                                                                                                
      "seller": { "id": "uuid", "name": "Asha" },                                                                                                               
      "cover_photo_url": "https://... presigned GET url",                                                                                                       
      "created_at": "2026-10-23T12:00:00Z"                                                                                                                      
    }                                                                                                                                                           
                                                                                                                                                                
  • ListingDetail (Extends ListingSummary):                                                                                                                     
    {                                                                                                                                                           
      "description": "Red and black helmet, size L",                                                                                                            
      "photos": [                                                                                                                                               
        { "s3_key": "...", "url": "https://...", "sort_order": 0 }                                                                                              
      ],                                                                                                                                                        
      "seller_contact": {                                                                                                                                       
        "email": "asha@iisc.ac.in",                                                                                                                             
        "phone": "+919876543210"                                                                                                                                
      },                                                                                                                                                        
      "updated_at": "2026-10-23T12:30:00Z"                                                                                                                      
    }                                                                                                                                                           
  (Note: seller_contact is null when requested by a guest).                                                                                                     
  ──────                                                                                                                                                        
  ### C. Lost & Found Module                                                                                                                                    
                                                                                                                                                                
  #### Endpoints                                                                                                                                                
                                                                                                                                                                
  The backend splits Lost and Found reports into two symmetrical routers rather than a single route with a type query parameter:                                
                                                                                                                                                                
   Method │ Path                                                             │ Auth                │ Description
  ────────┼──────────────────────────────────────────────────────────────────┼─────────────────────┼────────────────────────────────────────────────────────────
   GET    │ /api/v1/lost-reports/api/v1/found-reports                        │ Guest / User        │ Browse reports. Query params: q, category_id, status
          │                                                                  │                     │ (open, matched, closed), reporter_id, limit, offset
   POST   │ /api/v1/lost-reports/api/v1/found-reports                        │ User                │ Submit report (description, category_id, occurred_at,
          │                                                                  │                     │ location, photo_keys). Response includes possible_matches
   GET    │ /api/v1/lost-reports/{id}/api/v1/found-reports/{id}              │ Guest / User        │ Get report details
   PATCH  │ /api/v1/lost-reports/{id}/api/v1/found-reports/{id}              │ Owner               │ Update description, category_id, occurred_at, location
   PATCH  │ /api/v1/lost-reports/{id}/status/api/v1/found-                   │ Owner               │ Change status: "open" | "matched" | "closed"
          │ reports/{id}/status                                              │                     │
   PUT    │ /api/v1/lost-reports/{id}/photos/api/v1/found-                   │ Owner               │ Replace photo list
          │ reports/{id}/photos                                              │                     │
   DELETE │ /api/v1/lost-reports/{id}/api/v1/found-reports/{id}              │ Owner / Mod / Admin │ Delete report
                                                                                                                                                                
  #### Schemas                                                                                                                                                  
                                                                                                                                                                
  • ReportSummary (In feed lists):                                                                                                                              
    {                                                                                                                                                           
      "id": "uuid",                                                                                                                                             
      "kind": "lost",                                                                                                                                           
      "description": "Blue steel water bottle left on LH-1 2nd row",                                                                                            
      "category": { "id": 3, "name": "Water bottle" },                                                                                                          
      "occurred_at": "2026-10-23T09:30:00Z",                                                                                                                    
      "location": "Lecture Hall 1",                                                                                                                             
      "status": "open",                                                                                                                                         
      "reporter": { "id": "uuid", "name": "Mukund" },                                                                                                           
      "cover_photo_url": "https://...",                                                                                                                         
      "created_at": "2026-10-23T10:00:00Z"                                                                                                                      
    }                                                                                                                                                           
  (Note: There is no separate title field. The category represents the item type and description details the item).                                             
  • ReportDetail (Extends ReportSummary):                                                                                                                       
    {                                                                                                                                                           
      "photos": [{ "s3_key": "...", "url": "https://...", "sort_order": 0 }],                                                                                   
      "reporter_contact": { "email": "kmukund@iisc.ac.in", "phone": null },                                                                                     
      "updated_at": "2026-10-23T10:00:00Z",                                                                                                                     
      "possible_matches": [ /* List of opposite kind ReportSummary matches (on POST only) */ ]                                                                  
    }                                                                                                                                                           
                                                                                                                                                                
  ──────                                                                                                                                                        
  ### D. Other Exposed Modules (Phase 1)                                                                                                                        
                                                                                                                                                                
  The backend has also already implemented:                                                                                                                     
                                                                                                                                                                
  • Academic Help: /departments, /departments/{id}/courses, /courses/{id}/materials, /courses/{id}/feedback.                                                    
  • Forums: /courses/{id}/forum, /departments/{id}/forum, /forums/{id}/threads, /threads/{id}/comments.                                                         
  • Moderation & Reports: /reports, /me/reports, /reports/{id}/resolve, /moderators.                                                                            
  • Notifications: /me/notifications, /me/notifications/{id}/read, /me/notifications/read-all, /me/devices.                                                     
  ──────                                                                                                                                                        
  ## 3. Gap Analysis: Frontend vs Backend                                                                                                                       
                                                                                                                                                                
   Area                 │ Current Frontend Implementation  │ Backend Specification                           │ Changes Needed in Frontend
  ────────────────────────┼────────────────────────────────┼─────────────────────────────────────────────────┼──────────────────────────────────────────────────
   Auth & Profile         │ Assumed /api/v1/auth/login,    │ No auth endpoints in FastAPI; direct Cognito ID │ Remove OTP/login API calls from
                          │ /send-otp, /verify-otp,        │ token; /api/v1/me for profile                   │ ApiAuthRepository. Support Cognito ID token and
                          │ /auth/me                       │                                                 │ X-Dev-User dev header in ApiClient. Update user
                          │                                │                                                 │ model with moderator_grants.
   Pagination             │ page (1-indexed), limit,       │ offset (0-indexed), limit (max 50), returns     │ Introduce reusable Page<T> model in core. Change
                          │ expects List or {items, total} │ {items, limit, offset, has_more}                │ query params from page to offset and handle
                          │                                │                                                 │ has_more for infinite scrolling.
   Photo Uploads          │ Mock URLs or direct image URLs │ 3-step presigned S3 upload (POST /uploads ->    │ Add UploadService in core to compute SHA-256
                          │                                │ client PUT to S3 -> send photo_keys)            │ base64 digest, obtain ticket, upload to S3, and
                          │                                │                                                 │ pass photo_keys.
   Buy & Sell: Route      │ /buy-sell/listings             │ /listings                                       │ Update api_endpoints.dart.
   Buy & Sell: Pricing    │ Has both costPrice and         │ Only price (Decimal string, Rupees)             │ Remove costPrice from ListingItem,
                          │ sellingPrice                   │                                                 │ BuySellListingDto, and UI dialogs.
   Buy & Sell: Category   │ Plain String category          │ CategoryRef {id: int, name: String}             │ Fetch categories from /buy-sell/categories.
                          │                                │                                                 │ Store category_id: int when posting.
   Buy & Sell: Photos     │ List<String> imageUrls         │ cover_photo_url on summary; List<Photo> on      │ Map cover_photo_url for cards and full photos
                          │                                │ detail                                          │ list for detail modal. Support PUT
                          │                                │                                                 │ /listings/{id}/photos.
   Lost & Found: Routes   │ Single route /lost-            │ Two separate routes: /lost-reports and /found-  │ Update endpoint constants and repository to call
                          │ found/reports?type=...         │ reports                                         │ /lost-reports or /found-reports based on
                          │                                │                                                 │ PostType.
   Lost & Found: Title    │ Required title field           │ No title field; uses category_id (item name) +  │ Update domain model/DTO. In UI, display
                          │                                │ description                                     │ category.name as header or allow category +
                          │                                │                                                 │ location to serve as card title.
   Lost & Found: Status   │ open, resolved                 │ open, matched, closed                           │ Update ReportStatus enum to open, matched,
                          │                                │                                                 │ closed.
   Lost & Found: Time     │ Free-text string eventTime     │ ISO-8601 occurred_at (past time with timezone)  │ Use DateTime with timezone formatting instead of
                          │ (e.g., "10:30 AM")             │                                                 │ arbitrary strings.
   Lost & Found: Matching │ Not handled                    │ possible_matches returned on POST               │ Surface match suggestions dialog if
                          │                                │                                                 │ possible_matches is non-empty upon report
                          │                                │                                                 │ submission.
  ──────                                                                                                                                                        
  ## 4. Proposed Migration Plan (Step-by-Step)                                                                                                                  
                                                                                                                                                                
  When we are ready to proceed with the execution phase, we will execute the plan in the following sequence:                                                    
                                                                                                                                                                
  ### Step 1: Core Networking & Utilities                                                                                                                       
                                                                                                                                                                
  4. Update ApiEndpoints:                                                                                                                                       
      • Adjust Buy & Sell path: /listings                                                                                                                       
      • Split Lost & Found paths: /lost-reports, /found-reports, /lost-found/categories                                                                         
      • Add Category paths: /buy-sell/categories, /lost-found/categories                                                                                        
      • Update Profile path: /me, /users/{id}                                                                                                                   
      • Add Uploads path: /uploads                                                                                                                              
  5. Update ApiClient:                                                                                                                                          
      • Add Future<Response<T>> put<T>(...) method for photo updates and S3 uploads.                                                                            
      • Add dev header injection support (X-Dev-User, X-Dev-Name) for local testing alongside Authorization: Bearer <ID_TOKEN>.                                 
  6. Core Generic Models:                                                                                                                                       
      • Create Page<T> (items, limit, offset, has_more).                                                                                                        
      • Create CategoryRef (id, name).                                                                                                                          
      • Create Photo (s3Key, url, sortOrder).                                                                                                                   
      • Create Contact (email, phone).                                                                                                                          
                                                                                                                                                                
                                                                                                                                                                
  ### Step 2: S3 Upload Utility                                                                                                                                 
                                                                                                                                                                
  7. Create UploadRepository / UploadService:                                                                                                                   
      • Computes SHA-256 base64 digest from file bytes (crypto package).                                                                                        
      • Requests upload ticket from POST /api/v1/uploads.                                                                                                       
      • Directly PUTs raw bytes to S3 presigned URL with required headers.                                                                                      
      • Returns list of s3_keys.                                                                                                                                
                                                                                                                                                                
                                                                                                                                                                
  ### Step 3: Auth Data Layer Refactoring                                                                                                                       
                                                                                                                                                                
  8. Update User domain model:                                                                                                                                  
      • Add name, phone, departmentId, programme, graduationYear, isAdmin, moderatorGrants.                                                                     
      • Add scoped permission helpers: canModerateBuySell(), canModerateLostFound().                                                                            
  9. Update ApiAuthRepository:                                                                                                                                  
      • Direct profile fetching from GET /me.                                                                                                                   
      • Remove dummy OTP network calls.                                                                                                                         
                                                                                                                                                                
                                                                                                                                                                
  ### Step 4: Buy & Sell Data Layer Refactoring                                                                                                                 
                                                                                                                                                                
  10. Models:                                                                                                                                                    
      • Update ListingItem & BuySellListingDto:                                                                                                                 
          • Remove costPrice, keep single price.                                                                                                                
          • Switch category to CategoryRef.                                                                                                                     
          • Handle seller: UserRef and sellerContact: Contact?.                                                                                                 
          • Handle coverPhotoUrl (summary) and photos (detail).                                                                                                 
                                                                                                                                                                
  11. Repository:                                                                                                                                                
      • Update IBuySellRepository & ApiBuySellRepository:                                                                                                       
          • Support pagination via offset & limit.                                                                                                              
          • Implement fetchCategories() and createCategory().                                                                                                   
          • Update addListing to upload photos via UploadService and pass photo_keys.                                                                           
          • Implement replacePhotos(id, photoKeys).
  
  12. Update MockBuySellRepository to mirror the updated schemas.
  
  ### Step 5: Lost & Found Data Layer Refactoring
  
  13. Models:
      • Update LostFoundItem & LostFoundReportDto:
          • Remove title, use description and category.
          • Update status enum to open, matched, closed.
          • Change eventTime to occurredAt: DateTime.
          • Add possibleMatches: List<LostFoundItem>?.
  
  14. Repository:
      • Update ILostFoundRepository & ApiLostFoundRepository:
          • Route calls to /lost-reports or /found-reports depending on PostType.
          • Support pagination via offset & limit.
          • Implement fetchCategories() and createCategory().
          • Update submitReport with S3 upload integration.
  
  15. Update MockLostFoundRepository to align with the new structure.
  
  ### Step 6: UI & Test Alignment
  
  • Adapt dialogs (create_listing_dialog.dart, report_item_dialog.dart, detail dialogs) to match the streamlined fields (e.g. single price, date-time pickers,  
  category dropdown from backend).
  • Update data_layer_test.dart to verify serialization and mock contracts.
  ──────
  No code changes or git commits have been made. Please review this analysis and plan, and let me know if you would like to proceed with Step 1 or make any     
  adjustments to the approach!