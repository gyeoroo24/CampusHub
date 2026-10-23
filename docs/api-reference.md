# CampusHub API Reference

Last updated 23 Oct 2026. For the exact JSON of every request and response, run the backend and open Swagger at `http://localhost:8000/docs`.

## Overview

The CampusHub backend exposes 69 endpoints under `/api/v1`. This page lists each one, who may call it, and the fields it takes and returns, so screens can be designed around real data.

- **Base URL (local):** `http://localhost:8000/api/v1`. The cloud host isn't set up yet; only the host part will change.
- **Try it live:** `http://localhost:8000/docs` (Swagger) shows the exact JSON for every request and response, and lets you send real calls.
- **Built so far (Phase 1):** sign-in and profiles, Buy & Sell, Lost & Found, Academic Help, forums, reports and moderation, notifications. Placement Hub and Events come later (last section).

The **Who** column in every table below uses these roles:

| Who | Meaning |
| --- | --- |
| guest | Not signed in. Can read every public feed. |
| user | Any signed-in IISc user |
| owner | The user who created the item: seller, reporter or author |
| moderator | A user with an active moderator role for that module, department or course |
| admin | Full access everywhere |

## Sign-in and roles

Guests send nothing. Signed-in users send their token on every call, and the API checks their roles fresh each time.

| Situation | What the app sends |
| --- | --- |
| Guest | No auth header. Every GET feed works. |
| Signed in (cloud) | `Authorization: Bearer <Cognito ID token>` (the ID token, not the access token) |
| Local testing | `X-Dev-User: name@iisc.ac.in`, and optionally `X-Dev-Name: Asha` |

- **No sign-up endpoint.** The user's account is created on their first signed-in call.
- **IISc emails only.** Addresses ending in `iisc.ac.in` (including subdomains such as `alum.iisc.ac.in`) are accepted. Others get **403** with a readable message to show the user.
- **Expired or invalid token:** **401**. Send the user back to sign-in.
- **Role-based screens:** call `GET /me` after sign-in. `is_admin` and `moderator_grants` say which moderator tools to show. Thread detail also returns `viewer_can_moderate`.
- **Roles can change at any time.** A revoked moderator gets **403** on their next call, so handle 403 even on buttons you chose to show.
- **Contact details** (`seller_contact`, `reporter_contact`, `contact`) are `null` for guests. Design a "Sign in to see contact" state.

Moderator roles come in these shapes:

| Module | A moderator covers |
| --- | --- |
| `buy_sell` | All listings |
| `lost_found` | All lost and found reports |
| `academic_help` | One department (all its courses) or one course |
| `placement_hub` | All of Placement Hub (API not built yet) |

## Conventions

Every request and response body is JSON, and every list endpoint pages the same way.

- **IDs** are UUID strings, except category IDs, which are integers.
- **Times** are ISO 8601 with a timezone, e.g. `2026-10-23T12:18:55Z`. Show them in IST.
- **Prices** come back as strings in rupees, e.g. `"1500.00"`. Format them as ₹1,500.
- **Removed content** stays in lists where order matters: a removed comment has `removed: true` and `content: null`. Show "This comment was removed".
- **Pages:** list endpoints take `limit` (default 20, max 50) and `offset`, and return `{items, limit, offset, has_more}`. Use `has_more` for "Load more" or infinite scroll; there's no total count.

Errors return a status code and a `detail` you can show to the user:

| Status | Meaning | Design for |
| --- | --- | --- |
| 200 / 201 | OK / created; the body is the item | Success state |
| 204 | Done, no body (deletes, mark read) | Remove the item from the screen |
| 401 | Not signed in, or the token expired | Sign-in prompt |
| 403 | Signed in but not allowed, or not an IISc email | "You can't do this" message |
| 404 | Item doesn't exist or was removed | Empty or "not found" state |
| 409 | Duplicate (e.g. reporting the same item twice) | Inline message |
| 422 | A field is invalid; `detail` names it | Inline field error |

For 422 from form validation, `detail` is a list of `{loc, msg}`. `loc` ends with the field name, so the error can sit under that field.

## File uploads

Photos and course files go straight from the app to storage, not through the API, so attaching a file takes three calls.

![Upload flow: the app gets a ticket from the API, PUTs the file to storage, then attaches the s3_key to the post](images/upload-flow.png)

Only step 3 moves the file itself, so that's the step to show progress on.

1. **Ask for an upload ticket:** `POST /uploads` with `kind`, `content_type`, `size_bytes` and `checksum_sha256` (the base64 SHA-256 of the file). Course materials also need `course_id`. The reply has `upload_url`, `headers`, `s3_key` and `expires_in` (900 seconds).
2. **Upload the file:** `PUT` the raw file to `upload_url` with exactly those `headers`. Storage rejects a different file type or a corrupted file. Show the progress bar on this step.
3. **Attach it:** send the `s3_key` when creating or editing the post: `photo_keys` for listings and lost/found reports, `s3_key` for course materials. The API refuses a key that wasn't uploaded or belongs to someone else.

| `kind` | Allowed types | Max size | Max per post |
| --- | --- | --- | --- |
| `listing_photo`, `lost_report_photo`, `found_report_photo` | JPEG, PNG, WebP, HEIC | 10 MB | 10 photos |
| `course_material` | PDF, PPTX, DOCX, ZIP, TXT, images | 50 MB | 1 file per material |

- **Photo order:** `photo_keys` are kept in the order sent. The first is the cover (`cover_photo_url` in lists).
- **Editing photos later:** `PUT .../photos` with the full new list adds, removes and reorders in one call.
- **Image links** (`url`, `cover_photo_url`, `download_url`) can be temporary and expire after about an hour. Don't save them; fetch the item again.

## Users, profiles and moderators

Eight endpoints cover the signed-in user's profile, other people's public profiles, moderator roles and upload tickets.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| GET | `/health` | guest | Health check; returns `{"status": "ok"}` |
| GET | `/me` | user | My profile, `is_admin` and my active `moderator_grants` |
| PATCH | `/me` | user | Edit my `name`, `phone`, `department_id`, `programme`, `graduation_year` |
| GET | `/users/{user_id}` | guest | Someone's public profile; `contact` only for signed-in viewers |
| POST | `/moderators` | admin; department moderator (for their courses) | Make someone a moderator: `email`, `module`, `scope_type`, `department_id` or `course_id` |
| GET | `/moderators` | admin, department moderator | List roles. Filters: `module`, `department_id`, `course_id`, `include_revoked` |
| DELETE | `/moderators/{grant_id}` | same as POST | Revoke a role |
| POST | `/uploads` | user | Get an upload ticket (see File uploads) |

**Fields to design with:**

| Object | Fields |
| --- | --- |
| My profile | `id`, `email`, `name`, `phone` (optional), `department_id`, `programme`, `graduation_year`, `is_admin`, `moderator_grants` (each: `module`, `scope_type`, `department_id`, `course_id`, `granted_at`), `created_at` |
| Public profile | `id`, `name`, `department_id`, `programme`, `graduation_year`, `contact` (`email`, `phone`; signed-in viewers only) |
| Moderator role | `id`, `user_email`, `user_name`, `module`, `scope_type`, `department_id`, `course_id`, `granted_at`, `revoked_at` |

- **Limits:** name 1–100 characters, programme up to 100, graduation year 1950–2100. Send `phone: null` to remove a phone number.
- **Granting a role** only works for someone who has signed in at least once; otherwise it returns 404 with a message saying so.

## Buy & Sell

Guests can browse and search listings. Sellers create, edit and mark their own listings, and moderators can remove any listing.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| GET | `/buy-sell/categories` | guest | All categories (`id`, `name`), A–Z |
| POST | `/buy-sell/categories` | user | Add a category by `name` (the "Others" option). If the name already exists, ignoring case and spaces, the existing one comes back |
| GET | `/listings` | guest | Browse, newest first. Filters: `q` (title and description), `category_id`, `min_price`, `max_price`, `status` (repeatable), `seller_id` |
| POST | `/listings` | user | Create: `title`, `price`, `category_id`, `description`, `location`, `photo_keys` (up to 10) |
| GET | `/listings/{id}` | guest | One listing with all photos; `seller_contact` for signed-in users |
| PATCH | `/listings/{id}` | owner | Edit `title`, `description`, `price`, `category_id`, `location` |
| PATCH | `/listings/{id}/status` | owner | Set `status`: `available`, `reserved` or `sold` |
| PUT | `/listings/{id}/photos` | owner | Replace the photo list: `photo_keys` in the new order |
| DELETE | `/listings/{id}` | owner, Buy & Sell moderator, admin | Remove. Moderators can add `?reason=` |

**Fields to design with:**

| Object | Fields |
| --- | --- |
| Listing card (in lists) | `id`, `title`, `price`, `status`, `location`, `category` (`id`, `name`), `seller` (`id`, `name`), `cover_photo_url`, `created_at` |
| Listing detail | Everything on the card, plus `description`, `photos` (each: `url`, `sort_order`), `seller_contact` (`email`, `phone`; `null` for guests), `updated_at` |

- **Limits:** title 1–120 characters, description up to 5,000, location up to 200, price ≥ 0, category name 1–50.
- **Sold items:** browse returns every status unless you filter. To hide sold items, send `status=available&status=reserved`.
- **My listings:** browse with `seller_id` set to my own `id` from `GET /me`.

## Lost & Found

Lost reports and found reports have identical endpoints. Swap `/lost-reports` for `/found-reports` in every row below.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| GET | `/lost-found/categories` | guest | All categories, A–Z. A category names the item: ID card, Water bottle, Earbuds |
| POST | `/lost-found/categories` | user | Add a category by `name`, or get the existing one with that name |
| GET | `/lost-reports` | guest | Browse, newest first. Filters: `q` (description), `category_id`, `status` (repeatable), `reporter_id` |
| POST | `/lost-reports` | user | File a report: `description`, `category_id`, `occurred_at`, `location`, `photo_keys` (up to 10). The reply includes `possible_matches` |
| GET | `/lost-reports/{id}` | guest | One report with photos; `reporter_contact` for signed-in users |
| PATCH | `/lost-reports/{id}` | owner | Edit `description`, `category_id`, `occurred_at`, `location` |
| PATCH | `/lost-reports/{id}/status` | owner | Set `status`: `open`, `matched` or `closed` |
| PUT | `/lost-reports/{id}/photos` | owner | Replace the photo list |
| DELETE | `/lost-reports/{id}` | owner, Lost & Found moderator, admin | Remove. Moderators can add `?reason=` |

**Fields to design with:**

| Object | Fields |
| --- | --- |
| Report card (in lists) | `id`, `kind` (`lost` or `found`), `description`, `category`, `occurred_at`, `location`, `status`, `reporter` (`id`, `name`), `cover_photo_url`, `created_at` |
| Report detail | Everything on the card, plus `photos`, `reporter_contact` (`null` for guests), `updated_at` |
| Create reply only | `possible_matches`: up to 10 open reports of the other kind, same category, by other people, with compatible times |

- **`occurred_at`** is when the item was lost or found, as entered by the user. It's separate from `created_at`, so the form needs a date-and-time picker.
- **Matching:** filing a found report notifies everyone with an open lost report in that category, lost on or before that time. They get a `lost_found_match` notification.
- **`matched`** is never set automatically; the reporter chooses it.
- **Limits:** description 1–2,000 characters, location up to 200, up to 10 photos.

## Academic Help

The screens go department → course → materials and feedback. Each course and department also has a forum (next section).

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| GET | `/departments` | guest | All departments, A–Z, with `course_count` |
| POST | `/departments` | admin | Add a department: `name` |
| PATCH | `/departments/{id}` | admin | Rename it |
| DELETE | `/departments/{id}` | admin | Delete it and everything inside (courses, materials, feedback, forums) |
| GET | `/departments/{id}/courses` | guest | Its courses, sorted by code, with counts and `has_content` |
| POST | `/departments/{id}/courses` | admin, department moderator | Add a course: `code`, `name` |
| GET | `/courses/{id}` | guest | One course |
| PATCH | `/courses/{id}` | admin, department moderator | Edit `code`, `name` |
| DELETE | `/courses/{id}` | admin, department moderator | Delete it and everything under it |
| GET | `/courses/{id}/materials` | guest | Materials, newest first. Filter: `material_type` |
| POST | `/courses/{id}/materials` | course moderator (that course), department moderator, admin | Add one: `title`, `material_type`, `s3_key` |
| PATCH | `/materials/{id}` | same | Edit `title`, `material_type` |
| DELETE | `/materials/{id}` | same | Remove. Optional `?reason=` |
| GET | `/courses/{id}/feedback` | guest | Feedback, newest first |
| POST | `/courses/{id}/feedback` | user | Post feedback: `content` |
| PATCH | `/feedback/{id}` | owner, department moderator, admin | Edit `content` |
| DELETE | `/feedback/{id}` | owner, department moderator, admin | Remove. Optional `?reason=` |

**Fields to design with:**

| Object | Fields |
| --- | --- |
| Department | `id`, `name`, `course_count`, `created_at` |
| Course | `id`, `department_id`, `code`, `name`, `material_count`, `feedback_count`, `has_content`, `created_at` |
| Material | `id`, `course_id`, `title`, `material_type`, `download_url`, `uploaded_by` (`id`, `name`), `created_at` |
| Feedback | `id`, `course_id`, `author` (`id`, `name`), `content`, `created_at`, `updated_at` |

- **Empty courses:** `has_content: false` means show "No data yet".
- **Material types:** `notes`, `slides`, `past_assignment`, `exam_material`, `other` (the default). These suit filter chips.
- **Who sees upload and edit buttons:** check `moderator_grants` from `GET /me` for this course or its department.
- **Limits:** department name 1–120 characters, course code 1–20, course name 1–200, material title 1–200, feedback 1–5,000.

## Forums

Forums go forum → thread → comments. Each course and each department has exactly one forum, created the first time someone opens it.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| GET | `/courses/{id}/forum` | guest | The course's forum, with `thread_count` |
| GET | `/departments/{id}/forum` | guest | The department's forum |
| GET | `/forums/{id}/threads` | guest | Threads, newest first |
| POST | `/forums/{id}/threads` | user | Start a thread: `title` plus `content` (the opening post) |
| GET | `/threads/{id}` | guest | The thread with every comment in order, and `viewer_can_moderate` |
| PATCH | `/threads/{id}` | owner | Rename: `title` |
| DELETE | `/threads/{id}` | owner, forum moderator, admin | Remove the thread and all its comments. Optional `?reason=` |
| POST | `/threads/{id}/comments` | user | Reply: `content` |
| PATCH | `/comments/{id}` | owner | Edit `content` |
| DELETE | `/comments/{id}` | owner, forum moderator, admin | Remove. Optional `?reason=` |

**Fields to design with:**

| Object | Fields |
| --- | --- |
| Thread (in lists) | `id`, `forum_id`, `title`, `author` (`id`, `name`), `comment_count`, `last_comment_at`, `created_at` |
| Thread detail | Everything in the list item, plus `comments` and `viewer_can_moderate` |
| Comment | `id`, `seq`, `author`, `content`, `removed`, `created_at`, `updated_at` |

- **Opening post:** the first comment in `comments`. Edit it like any comment.
- **Removed comments** stay in place with `removed: true` and `content: null`, so replies keep their context.
- **Forum moderators:** for a course forum, that course's moderator or its department's moderator; for a department forum, that department's moderators; admins everywhere. Use `viewer_can_moderate` to show remove buttons.
- **Replies notify** the thread's author and everyone who has commented, except the person replying (`forum_reply`).
- **Limits:** title 1–200 characters, post or comment 1–10,000.

## Reports and moderation

Any signed-in user can flag content. Moderators work through a queue limited to their own scope.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| POST | `/reports` | user | Flag an item: `target_type`, `target_id`, `reason` |
| GET | `/me/reports` | user | Reports I've filed, newest first |
| GET | `/reports` | moderator, admin | The queue for my scope, oldest first. Filters: `status` (default `open`), `module` |
| POST | `/reports/{id}/resolve` | moderator in scope, admin | `action`: `actioned` or `dismissed`, plus an optional `note` and `remove_content` |

**Fields to design with:**

| Object | Fields |
| --- | --- |
| Report | `id`, `module`, `target_type`, `target_id`, `reason`, `status` (`open`, `actioned`, `dismissed`), `reporter` (moderators only), `created_at`, `handled_at`, `resolution_note` |
| Resolve reply | `reports_resolved` (how many reports closed), `content_removed` |

- **What can be flagged** (`target_type`): `listing`, `lost_report`, `found_report`, `course_material`, `course_feedback`, `thread`, `comment`. Put a "Report" action on each of these.
- **One open report per user per item.** A second one returns 409, so show "You've already reported this".
- **The queue has no preview.** Show the item by fetching it with `target_type` and `target_id`, e.g. `GET /listings/{target_id}`.
- **Resolving one report closes every open report on that item.** With `remove_content: true` it also removes the item in the same step. If another moderator resolved it first, you get 409.
- **Limits:** reason 1–1,000 characters, resolution note up to 1,000.

## Notifications and devices

Every notification lands in the user's in-app inbox. Push to phones is registered but not delivered yet, so design the inbox first.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| GET | `/me/notifications` | user | My inbox, newest first. Filter: `unread_only` |
| POST | `/me/notifications/{id}/read` | user | Mark one read |
| POST | `/me/notifications/read-all` | user | Mark all read; returns `{"updated": <count>}` |
| POST | `/me/devices` | user | Register this device for push: `platform` (`android`, `ios`, `web`, `desktop`) and `push_token` |
| DELETE | `/me/devices?push_token=` | user | Unregister this device. Call it on sign-out |

A notification has `id`, `type`, `payload`, `is_read` and `created_at`. Every `payload` has a ready-to-show `message`; the other fields say where tapping should go.

| `type` | When | `payload` besides `message` | Tap opens |
| --- | --- | --- | --- |
| `forum_reply` | Someone replies in a thread you started or commented in | `thread_id`, `comment_id`, `forum_id` | The thread |
| `lost_found_match` | Someone files a found report matching your open lost report | `found_report_id`, `lost_report_ids` | The found report |

- **Unread badge:** call with `unread_only=true` and check whether `items` is empty. There's no unread-count endpoint.
- **Shared devices:** registering a token another account used moves it to the current user.

## Not available yet

These parts of the app have database tables but no endpoints yet (Phase 2). Design them from the PRD; their endpoints will follow the same conventions as above.

| Area | What's planned |
| --- | --- |
| Placement Hub | Company pages, job descriptions, pre-placement talks, hiring stats (totals only, never individual students), interview experiences, a forum per company, bulk import of placement sheets |
| Community Events | Events with tags, shown as Past, Present or Upcoming; following tags for alerts |
| Bookmarks | Saving listings and events. Guests keep bookmarks on the device only |
| Landing page highlights | Featured items across modules (FR-21) |
| Chat | One-to-one messages (stretch goal) |
| Push delivery | Devices register today, but pushes are only logged; the inbox works |
