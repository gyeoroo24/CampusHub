-- ============================================================================
-- CampusHub — PostgreSQL schema (AWS RDS, PostgreSQL 15+) — Revision 23
-- DS252 Introduction to Cloud Computing — Team "Order of Phoenix"
--
-- Permission modules (FR-2, NFR-6): buy_sell, lost_found, academic_help,
-- placement_hub, events (rev 17: Community Events moderators).
--
-- Changes from rev. 21 (course repository, 3 Nov 2026):
--   1. Course materials are a shared repository: anyone signed in uploads (up to 100 MB). New columns
--      tags, description, file_name, size_bytes, content_type, and held_for_review_at (a file that
--      looks wrong is hidden until a course moderator decides; app/material_check.py).
--   2. course_follows and notification type course_update: following a course alerts you to new
--      materials, feedback and forum posts.
--   Upgrade: db/migrations/022_course_repository_and_follows.sql.
--
-- Changes from rev. 20 (role compensation, 3 Nov 2026):
--   1. job_descriptions.placement_year, job_type, ctc_min / ctc_max (rupees a year, read from the
--      compensation text), base_text / base_annual, skills: a company's roles per season with what they
--      pay, imported from "roles and compensation" files (app/placement_roles.py) or typed in.
--   Upgrade: db/migrations/021_role_compensation.sql.
--
-- Changes from rev. 19 (mess cards and schedule times, 3 Nov 2026):
--   1. messes.event_id: every mess has a Food/Mess event card (its meal times and dishes), created
--      and updated with its menus.
--   2. ppt_info.time_tbd: a date imported without a time shows "time to be announced".
--   Upgrade: db/migrations/020_mess_event_cards_and_tba_times.sql.
--
-- Changes from rev. 18 (chat and placement follow-ups, 2 Nov 2026):
--   1. chat_conversations.user_a_cleared_seq / user_b_cleared_seq: "delete chat" hides a chat from
--      one person only; chat_message_hides: "delete for me" on one message.
--   2. placement_records.student_email takes any email address (counted in the hiring numbers;
--      only IISc addresses are listed as seniors to contact).
--   Upgrade: db/migrations/019_chat_hiding_and_any_email.sql.
--
-- Changes from rev. 17 (senior contacts and mess menus, 2 Nov 2026):
--   1. company_seniors: people to contact about a company (off-campus offers and others moderators
--      add); placement_records.contact_hidden takes a sheet student off a company's contact list.
--   2. Mess menus: messes (with meal times), mess_menus (a month's menu, optionally with the
--      PDF/image), mess_menu_items (what each meal has on each weekday), mess_follows (meal alerts)
--      and mess_alerts_sent; notification type mess_menu.
--   3. Forum posts start at 0 votes: the author's automatic upvote from rev 17 is gone.
--   Upgrade: db/migrations/018_seniors_and_mess_menus.sql.
--
-- Changes from rev. 16 (Placement Hub and Events follow-ups, 2 Nov 2026):
--   1. module_name 'events': Community Events moderators remove any event and moderate event forums.
--   2. Events have forums: forum_scope_type 'event', forums.event_id.
--   3. Reddit-style forums: thread_votes and comment_votes (+1 / -1 per person), and
--      comments.parent_id for replies to a reply (NULL = top-level reply).
--   4. ppt_info.kind: the placement schedule holds pre-placement talks, online tests (OA),
--      interviews and other dates, not only talks.
--   5. events.poster_s3_key: an optional poster image (upload kind event_poster).
--   Upgrade: db/migrations/017_forums_events_moderation.sql.
--
-- Changes from rev. 15 (Placement Hub and Community Events APIs, 1-2 Nov 2026; built in
--   parallel with revs 13-15 and first numbered rev 13):
--   1. companies.website / industry; job_descriptions.description / compensation (the JD as text,
--      the file stays optional); ppt_info.venue.
--   2. interview_experiences.is_anonymous and placement_year (which season the interview was for).
--   Upgrade: db/migrations/016_placement_and_events.sql.
--
-- Changes from rev. 14 (automatic flagging and price watch, 2 Nov 2026):
--   1. reports.source ('user' or 'system') and reporter_id nullable for system flags (future
--      plan §1.6); one open system flag per item (uq_reports_one_open_system).
--   2. listings.held_for_review_at: an automatically flagged listing held back until a moderator
--      decides; listings.negotiable (future plan §2.3).
--   3. listing_watches and notification type listing_watch: price changes / marked negotiable.
--   Upgrade: db/migrations/015_auto_flags_and_price_watch.sql.
--
-- Changes from rev. 13 (reversible listing hide + appeal review, 1 Nov 2026):
--   1. listings.hidden_by_strike_id: a report-driven removal (future plan §1.5) now hides the
--      listing instead of soft-deleting it — visible only to the seller and a Buy & Sell
--      moderator/admin until the strike is overturned (restores it) or the appeal is rejected
--      (stays hidden). A direct DELETE /listings/{id} is unaffected and still permanent.
--   2. seller_strikes.appeal_resolved_at/by: lets a moderator explicitly reject an appeal
--      (distinct from overturning it), so it drops out of the "needs review" queue either way.
--   Upgrade: db/migrations/014_reversible_listing_hide.sql.
--
-- Changes from rev. 12 (seller trust score, 1 Nov 2026):
--   1. seller_strikes: one row per moderator-confirmed listing removal (future plan §1.5) —
--      never from a raw report. severity (severe/non_severe) sets the "Negative Seller" /
--      "Blocked Seller" thresholds (app/seller_trust.py). A seller may appeal a strike
--      (appeal_message); a moderator may overturn one (excluded), which drops it from the count.
--   2. users.listing_suspended_at / listing_suspended_reason: set once a seller crosses the
--      "Blocked Seller" threshold, enforced on listing creation; cleared by a moderator or by
--      overturning the strike that caused it.
--   Upgrade: db/migrations/013_seller_trust.sql.
--
-- Changes from rev. 5 ("Taking it further" features, 24 Oct 2026):
--   1. saved_searches: a saved Buy & Sell or Lost & Found search; new
--      matching listings / found reports send a saved_search_match alert.
--   2. wanted_posts: buyers post what they need; new matching listings send
--      a wanted_post_match alert. Reportable (reports.wanted_post_id).
--   3. campus_services: Health Centre, Wellness Centre and grievance links
--      for the landing page, managed by the admin.
--   4. No table for the course survival guide: it is computed from
--      course_feedback when requested.
--   An existing database is upgraded with db/migrations/006_taking_it_further.sql.
--
-- Changes from rev. 11 (Lost & Found matching by description and photo, 1 Nov 2026):
--   1. lost_reports / found_reports: match_rev (bumped when the description, category, time or
--      photos change, or the report reopens) and matched_rev (the rev the matcher last finished).
--   2. lf_embeddings: one vector per report description / photo and model (app/matching).
--   3. lf_matches: scored lost-found pairs above the "possible match" bar.
--   Upgrade: db/migrations/012_lf_matching.sql.
--
-- Changes from rev. 7 (in-app messaging, 31 Oct 2026):
--   1. End-to-end encrypted buyer–seller chat per listing: chat_keys,
--      chat_conversations, chat_messages (replaces the unused plaintext
--      placeholder chat_messages table), chat_blocks. New notification type
--      chat_message. Upgrade: db/migrations/008_encrypted_chat.sql.
--
-- Changes from rev. 6 (frontend review, 25 Oct 2026):
--   1. course_feedback.is_anonymous, and at most one active review per person per course
--      (uq_feedback_one_per_author). Upgrade: db/migrations/007_feedback_rules.sql.
--
-- Changes from rev. 4 (team review, 23 Oct 2026):
--   1. Multiple photos: listing_photos, lost_report_photos and
--      found_report_photos replace the single photo columns (up to 10 each).
--   2. File metadata columns (content type, size, SHA-256) removed from all
--      tables; S3 already stores them for every object. Rows keep the S3 key.
--   3. placement_records.status removed (being in the sheet = selected).
--   4. placement_import_errors removed; rejected rows are returned to the
--      moderator in the import response, and only the count is stored.
--   5. Lost & Found categories and item tags merged: item_tags removed;
--      lf_categories now names what the item is (ID card, Water bottle, ...)
--      and FR-9 matching compares category_id.
--
-- Changes from rev. 3 (team review, 22 Oct 2026):
--   1. Deleting a course (or department/company) now deletes EVERYTHING
--      under it: materials, feedback, moderator grants, its forum, the
--      forum's threads and comments, and any user reports about them.
--      forums.scope_id replaced by real course_id/department_id/company_id
--      foreign keys so the cascade can work.
--   2. Thread order: comments.seq (auto-increment) replaces timestamp
--      ordering, so order never depends on clock ties or random UUIDs.
--   3. comments.forum_id removed — a comment's forum is always its thread's
--      forum, so the two can no longer disagree.
--   4. threads.author_id + threads.title: ownership is stored on the thread
--      and never shifts. can_moderate_forum() tells the API which
--      moderators/admins may remove a thread or comment.
--   5. Removing a thread removes its comments (soft delete propagates via
--      trigger; hard delete cascades).
--   6. reports: status workflow (open/actioned/dismissed), handled_by,
--      module, one open report per user per item, real foreign keys to the
--      reported item (deleted with it); course materials, course feedback
--      and interview experiences can now be reported.
--   7. Timestamps: created_at on every table that lacked one; updated_at
--      (kept current by trigger) on every table whose rows get edited.
--   8. module_name has 4 values (community_events removed).
--   9. push_devices table for delivering push notifications (FR-9/20/22).
--
-- Timestamp convention:
--   created_at  — every table (append-only tables use their own event name:
--                 granted_at/revoked_at, imported_at, sent_at/read_at)
--   updated_at  — every table whose rows are edited; set by set_updated_at()
--   deleted_at/deleted_by — soft delete on user-generated content
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid() (built in on PG13+, harmless)
CREATE EXTENSION IF NOT EXISTS citext;    -- case-insensitive text for emails (supported on RDS)

-- ============================================================================
-- ENUM TYPES
-- ============================================================================
CREATE TYPE user_role            AS ENUM ('signed_in', 'admin');   -- "moderator" is derived from moderator_assignments
CREATE TYPE module_name          AS ENUM ('buy_sell', 'lost_found', 'academic_help', 'placement_hub', 'events');
CREATE TYPE mod_scope_type       AS ENUM ('module', 'department', 'course');
CREATE TYPE listing_status       AS ENUM ('available', 'reserved', 'sold');
CREATE TYPE lost_found_status    AS ENUM ('open', 'matched', 'closed');  -- 'matched' unused since rev 11
CREATE TYPE material_type        AS ENUM ('notes', 'slides', 'past_assignment', 'exam_material', 'other');
CREATE TYPE forum_scope_type     AS ENUM ('course', 'department', 'company', 'event');
CREATE TYPE bookmark_target_type AS ENUM ('listing', 'event');
CREATE TYPE notification_type    AS ENUM ('lost_found_match', 'forum_reply', 'listing_status_change',
                                          'bookmarked_event_update', 'followed_tag_event', 'moderation_action',
                                          'saved_search_match', 'wanted_post_match', 'chat_message',
                                          'listing_watch', 'mess_menu', 'course_update');
CREATE TYPE report_target_type   AS ENUM ('listing', 'lost_report', 'found_report', 'course_material',
                                          'course_feedback', 'thread', 'comment', 'interview_experience',
                                          'wanted_post');
CREATE TYPE wanted_status        AS ENUM ('open', 'fulfilled', 'closed');
CREATE TYPE campus_service_category AS ENUM ('health', 'wellbeing', 'grievance', 'safety', 'other');
CREATE TYPE report_status        AS ENUM ('open', 'actioned', 'dismissed');
CREATE TYPE report_source        AS ENUM ('user', 'system');   -- system: automatic flag (§1.6)
CREATE TYPE device_platform      AS ENUM ('android', 'ios', 'web', 'desktop');
CREATE TYPE chat_message_kind    AS ENUM ('text', 'offer');
CREATE TYPE seller_strike_severity AS ENUM ('severe', 'non_severe');  -- future plan §1.5
CREATE TYPE chat_offer_status    AS ENUM ('pending', 'accepted', 'declined', 'withdrawn', 'superseded');
CREATE TYPE chat_topic_kind      AS ENUM ('listing', 'lost_report', 'found_report');

-- ============================================================================
-- SHARED HELPERS
-- ============================================================================
-- Postgres applies DEFAULT now() only on INSERT. This keeps updated_at
-- current on every UPDATE (triggers attached at the bottom of the file).
CREATE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- IISc email rule (FR-1), used for users and placement-sheet student emails:
-- local part, "@", then iisc.ac.in or any subdomain of it. Case-insensitive.
--   accepted: a@iisc.ac.in, A@IISC.AC.IN, x@alum.iisc.ac.in, y@vendor.iisc.ac.in
--   rejected: z@gmail.com, z@fakeiisc.ac.in, @iisc.ac.in, z@iisc.ac.in.evil.com
-- Cognito's pre-sign-up Lambda must apply the same rule.
CREATE DOMAIN iisc_email AS citext
    CHECK (VALUE ~ '^[^@\s]+@([a-z0-9-]+\.)*iisc\.ac\.in$');

-- ============================================================================
-- PHASE 1 — ACADEMIC STRUCTURE (first: users.department_id references it)
-- Deleting a department deletes its courses; deleting a course deletes
-- everything attached to it (team decision).
-- ============================================================================
CREATE TABLE departments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE courses (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    code          TEXT NOT NULL,
    name          TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (department_id, code)            -- also serves "courses of a department" (FR-11)
);

-- ============================================================================
-- PHASE 1 — IDENTITY, PROFILE & ACCESS  (FR-1, FR-2, FR-3, §3.1, NFR-6)
-- ============================================================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cognito_sub     TEXT UNIQUE NOT NULL,                   -- Cognito JWT `sub` claim
    email           iisc_email UNIQUE NOT NULL,             -- always available as a contact option
    name            TEXT NOT NULL,
    base_role       user_role NOT NULL DEFAULT 'signed_in',
    -- profile (§3.1 "CRUD on own profile"; WBS week 2)
    phone           TEXT CHECK (phone ~ '^\+?[0-9]{10,15}$'),  -- optional second contact option
    department_id   UUID REFERENCES departments(id) ON DELETE SET NULL,
    programme       TEXT,                                    -- e.g. 'M.Tech CSA'
    graduation_year SMALLINT CHECK (graduation_year BETWEEN 1950 AND 2100),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    -- Seller trust score (future plan §1.5): set once seller_strikes crosses the "Blocked Seller"
    -- threshold (app/seller_trust.py). Checked on listing creation; cleared by a moderator/admin
    -- or automatically when overturning the strike that caused it.
    listing_suspended_at     TIMESTAMPTZ,
    listing_suspended_reason TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Guests are not rows here: FR-1 gives them read-only access with no account.
-- Exactly one admin at a time (team decision): the admin hands the role over with
-- POST /users/{id}/make-admin, which demotes them in the same transaction.
CREATE UNIQUE INDEX uq_users_single_admin ON users ((true)) WHERE base_role = 'admin';

-- Moderator grants. "Is this user a moderator for this action?" is answered
-- ONLY from active rows here, on every privileged request. JWT group claims
-- stay valid until the token expires (~1 h), so trusting them would let a
-- revoked moderator keep acting (FR-3: "next privileged call rejected").
--
-- Scope shapes (enforced by mod_scope_shape_chk):
--   buy_sell / lost_found / placement_hub -> scope 'module', no ids
--   academic_help, department-level       -> department_id set
--   academic_help, course-level           -> course_id set
-- Course moderators create/read/update/delete materials of their assigned
-- course only; department moderators do so for every course in their
-- department and may grant/revoke course moderators there (§3.1, scenario 4).
-- Those rules live in the FastAPI authorization dependency.
CREATE TABLE moderator_assignments (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module        module_name NOT NULL,
    scope_type    mod_scope_type NOT NULL DEFAULT 'module',
    department_id UUID REFERENCES departments(id) ON DELETE CASCADE,
    course_id     UUID REFERENCES courses(id) ON DELETE CASCADE,
    granted_by    UUID NOT NULL REFERENCES users(id),
    granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_by    UUID REFERENCES users(id),
    revoked_at    TIMESTAMPTZ,
    CONSTRAINT mod_scope_shape_chk CHECK (
        (scope_type = 'module'     AND module <> 'academic_help' AND department_id IS NULL     AND course_id IS NULL) OR
        (scope_type = 'department' AND module =  'academic_help' AND department_id IS NOT NULL AND course_id IS NULL) OR
        (scope_type = 'course'     AND module =  'academic_help' AND course_id IS NOT NULL     AND department_id IS NULL)),
    CONSTRAINT mod_revoke_pair_chk CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);
-- At most one ACTIVE grant per user per scope. Revoked rows are ignored, so
-- revoke -> re-grant works and the old row stays as history. NULLS NOT
-- DISTINCT makes two module-wide grants (both ids NULL) count as duplicates.
CREATE UNIQUE INDEX uq_mod_active_grant ON moderator_assignments
    (user_id, module, scope_type, department_id, course_id) NULLS NOT DISTINCT
    WHERE revoked_at IS NULL;
CREATE INDEX idx_mod_assignments_active ON moderator_assignments(user_id, module) WHERE revoked_at IS NULL;
CREATE INDEX idx_mod_by_course     ON moderator_assignments(course_id)     WHERE revoked_at IS NULL AND course_id IS NOT NULL;
CREATE INDEX idx_mod_by_department ON moderator_assignments(department_id) WHERE revoked_at IS NULL AND department_id IS NOT NULL;

-- ============================================================================
-- USER-EXTENSIBLE CATEGORY TABLES
-- A user who can't find a fitting entry picks "Others" and types a new name.
-- name_key normalises it (trim, collapse spaces, lowercase) so "Earbuds",
-- " earbuds " and "EARBUDS" are the same entry. Get-or-create:
--   WITH ins AS (
--     INSERT INTO lf_categories (name, created_by) VALUES (:name, :user)
--     ON CONFLICT (name_key) DO NOTHING RETURNING id)
--   SELECT id FROM ins
--   UNION ALL
--   SELECT id FROM lf_categories
--   WHERE name_key = lower(regexp_replace(btrim(:name), '\s+', ' ', 'g'))
--   LIMIT 1;
-- Spelling variants ("Earbud" vs "Earbuds") are not caught; a moderator can
-- merge them if needed.
-- ============================================================================
CREATE TABLE bs_categories (
    id         SERIAL PRIMARY KEY,
    name       TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 50),
    name_key   TEXT GENERATED ALWAYS AS (lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))) STORED UNIQUE,
    created_by UUID REFERENCES users(id),          -- NULL = seeded by admins
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lost & Found category = WHAT the item is: ID card, Water bottle, Earbuds,
-- Umbrella, ... It is both the category FR-7/FR-8 ask for and the key FR-9
-- matching compares. Chosen (or added via "Others") by the user for now;
-- may later be auto-extracted from the photo/description.
CREATE TABLE lf_categories (
    id         SERIAL PRIMARY KEY,
    name       TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 50),
    name_key   TEXT GENERATED ALWAYS AS (lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))) STORED UNIQUE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- UPLOADED FILES
-- The S3 bucket is private behind CloudFront (§6.1), so rows store only the
-- S3 OBJECT KEY, never a URL; the API builds a short-lived URL when serving.
-- S3 itself keeps each object's content type, size and checksum, so they are
-- not copied here. The API issues a presigned PUT that signs the file's
-- Content-Type and x-amz-checksum-sha256, so S3 rejects a different type or a
-- corrupted upload (NFR-8), and checks size/type with HeadObject before a key
-- is saved to a row.
-- ============================================================================

-- ============================================================================
-- PHASE 1 — BUY & SELL  (FR-4, FR-5, FR-6, FR-10)
-- ============================================================================
CREATE TABLE listings (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id          UUID NOT NULL REFERENCES users(id),
    title              TEXT NOT NULL,
    description        TEXT,
    price              NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    category_id        INT NOT NULL REFERENCES bs_categories(id),
    location           TEXT,
    status             listing_status NOT NULL DEFAULT 'available',
    search_vector      TSVECTOR GENERATED ALWAYS AS (
                           to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,''))
                       ) STORED,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ,                        -- soft delete, FR-10
    deleted_by         UUID REFERENCES users(id),          -- owner or moderator who removed it
    held_for_review_at TIMESTAMPTZ,                         -- auto-flagged as prohibited: hidden until a moderator decides
    negotiable         BOOLEAN NOT NULL DEFAULT FALSE,      -- "Negotiable" badge (future plan §2.3)
    -- hidden_by_strike_id (reversible, report-driven removal) is added below, near
    -- seller_strikes, to avoid a circular forward reference.
    CONSTRAINT listings_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_listings_filter ON listings(category_id, price) WHERE deleted_at IS NULL;   -- FR-6
CREATE INDEX idx_listings_search ON listings USING GIN(search_vector);                        -- FR-6 keyword
CREATE INDEX idx_listings_feed   ON listings(created_at DESC) WHERE deleted_at IS NULL;       -- latest listings, FR-21
CREATE INDEX idx_listings_seller ON listings(seller_id, created_at DESC);                     -- "my listings"

-- Photos of a listing, up to 10. The one with the smallest sort_order is the
-- cover photo shown in the feed. Reordering photos inside one transaction
-- works because the (listing_id, sort_order) uniqueness is checked at commit.
-- Hard-deleting a listing deletes its photo rows (delete the S3 objects too).
CREATE TABLE listing_photos (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    s3_key     TEXT NOT NULL UNIQUE,
    sort_order SMALLINT NOT NULL CHECK (sort_order BETWEEN 1 AND 10),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT listing_photos_order_uq UNIQUE (listing_id, sort_order) DEFERRABLE INITIALLY DEFERRED
);

-- "Wanted" posts (rev 6): a buyer says what they need instead of waiting for
-- it to be listed. When a new listing is in the same category, within budget
-- and shares a word with the title, the author gets a wanted_post_match alert.
CREATE TABLE wanted_posts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id     UUID NOT NULL REFERENCES users(id),
    title         TEXT NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
    description   TEXT,
    category_id   INT NOT NULL REFERENCES bs_categories(id),
    max_price     NUMERIC(10,2) CHECK (max_price >= 0),        -- budget; NULL = open to offers
    status        wanted_status NOT NULL DEFAULT 'open',
    search_vector TSVECTOR GENERATED ALWAYS AS (
                      to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,''))
                  ) STORED,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ,
    deleted_by    UUID REFERENCES users(id),
    CONSTRAINT wanted_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_wanted_feed   ON wanted_posts(created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_wanted_match  ON wanted_posts(category_id) WHERE deleted_at IS NULL AND status = 'open';
CREATE INDEX idx_wanted_search ON wanted_posts USING GIN(search_vector);
CREATE INDEX idx_wanted_author ON wanted_posts(author_id, created_at DESC);

-- ============================================================================
-- PHASE 1 — LOST & FOUND  (FR-7, FR-8, FR-9, FR-10)
-- FR-9 matching: when a found report is created, notify every open lost
-- report in the same category (e.g. "ID card"), lost before it was found,
-- by someone else:
--   SELECT l.id, l.reporter_id FROM lost_reports l
--   WHERE l.category_id = :category_id AND l.status = 'open' AND l.deleted_at IS NULL
--     AND l.lost_at <= :found_at AND l.reporter_id <> :finder_id;
-- idx_lost_match serves this; idx_found_match serves the reverse lookup
-- ("show already-found items like mine" when someone files a lost report).
-- ============================================================================
CREATE TABLE lost_reports (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id        UUID NOT NULL REFERENCES users(id),
    description        TEXT NOT NULL,
    category_id        INT NOT NULL REFERENCES lf_categories(id),   -- what the item is; matched on
    lost_at            TIMESTAMPTZ NOT NULL,                -- when the item was lost (user-entered)
    location           TEXT,
    status             lost_found_status NOT NULL DEFAULT 'open',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),   -- when the report was filed
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ,
    deleted_by         UUID REFERENCES users(id),
    match_rev          INT NOT NULL DEFAULT 1,   -- bumped when what matching looks at changes
    matched_rev        INT,                      -- match_rev the matcher last finished; NULL = never
    CONSTRAINT lost_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_lost_feed     ON lost_reports(created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_lost_reporter ON lost_reports(reporter_id, created_at DESC);
CREATE INDEX idx_lost_match    ON lost_reports(category_id, lost_at) WHERE deleted_at IS NULL AND status = 'open';

CREATE TABLE lost_report_photos (           -- same rules as listing_photos
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lost_report_id UUID NOT NULL REFERENCES lost_reports(id) ON DELETE CASCADE,
    s3_key         TEXT NOT NULL UNIQUE,
    sort_order     SMALLINT NOT NULL CHECK (sort_order BETWEEN 1 AND 10),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT lost_report_photos_order_uq UNIQUE (lost_report_id, sort_order) DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE found_reports (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id        UUID NOT NULL REFERENCES users(id),
    description        TEXT NOT NULL,
    category_id        INT NOT NULL REFERENCES lf_categories(id),   -- what the item is; matched on
    found_at           TIMESTAMPTZ NOT NULL,                -- when the item was found (user-entered)
    location           TEXT,
    status             lost_found_status NOT NULL DEFAULT 'open',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ,
    deleted_by         UUID REFERENCES users(id),
    match_rev          INT NOT NULL DEFAULT 1,   -- bumped when what matching looks at changes
    matched_rev        INT,                      -- match_rev the matcher last finished; NULL = never
    CONSTRAINT found_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_found_feed     ON found_reports(created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_found_reporter ON found_reports(reporter_id, created_at DESC);
CREATE INDEX idx_found_match    ON found_reports(category_id, found_at) WHERE deleted_at IS NULL AND status = 'open';

CREATE TABLE found_report_photos (          -- same rules as listing_photos
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    found_report_id UUID NOT NULL REFERENCES found_reports(id) ON DELETE CASCADE,
    s3_key          TEXT NOT NULL UNIQUE,
    sort_order      SMALLINT NOT NULL CHECK (sort_order BETWEEN 1 AND 10),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT found_report_photos_order_uq UNIQUE (found_report_id, sort_order) DEFERRABLE INITIALLY DEFERRED
);

-- Lost & Found matching (app/matching). One vector per (report, model, description or photo).
-- Vectors are plain REAL[] and compared in Python: open reports number in the hundreds, so
-- pgvector isn't needed.
CREATE TABLE lf_embeddings (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lost_report_id  UUID REFERENCES lost_reports(id) ON DELETE CASCADE,
    found_report_id UUID REFERENCES found_reports(id) ON DELETE CASCADE,
    model           TEXT NOT NULL,         -- e.g. minilm-l6-v2, mobileclip-s0-image
    s3_key          TEXT,                  -- the photo; NULL = the description
    source_hash     TEXT NOT NULL,         -- SHA-256 of the description (or the photo key)
    vec             REAL[] NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT lf_embeddings_one_report_chk CHECK ((lost_report_id IS NULL) <> (found_report_id IS NULL))
);
CREATE UNIQUE INDEX uq_lf_embeddings ON lf_embeddings
    (COALESCE(lost_report_id, found_report_id), model, COALESCE(s3_key, ''));

-- A lost and a found report that may be the same item; only pairs at or above the "possible" bar.
CREATE TABLE lf_matches (
    lost_report_id  UUID NOT NULL REFERENCES lost_reports(id) ON DELETE CASCADE,
    found_report_id UUID NOT NULL REFERENCES found_reports(id) ON DELETE CASCADE,
    score           REAL NOT NULL CHECK (score BETWEEN 0 AND 1),
    text_sim        REAL,                  -- raw cosine similarities, kept for tuning
    photo_sim       REAL,
    cross_sim       REAL,
    reasons         TEXT[] NOT NULL DEFAULT '{}',
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    notified_at     TIMESTAMPTZ,           -- when the lost report's owner was alerted
    PRIMARY KEY (lost_report_id, found_report_id)
);
CREATE INDEX idx_lf_matches_found ON lf_matches(found_report_id);

-- ============================================================================
-- SAVED SEARCHES AND ALERTS (rev 6)
-- "Tell me when a cycle under ₹3,000 appears" (buy_sell: watches new
-- listings) or "when someone finds an ID card" (lost_found: watches new found
-- reports). Filters mirror GET /listings and GET /found-reports. A matching
-- item sends one saved_search_match notification per user per item; the
-- notification payload (listing_id / found_report_id) is the dedupe key, as
-- with FR-9. last_seen_at drives the "N new" badge.
-- ============================================================================
CREATE TABLE saved_searches (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module         module_name NOT NULL CHECK (module IN ('buy_sell', 'lost_found')),
    name           TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    query          TEXT CHECK (char_length(query) <= 200),     -- keywords; NULL = any
    bs_category_id INT REFERENCES bs_categories(id),           -- buy_sell only
    lf_category_id INT REFERENCES lf_categories(id),           -- lost_found only
    min_price      NUMERIC(10,2) CHECK (min_price >= 0),       -- buy_sell only
    max_price      NUMERIC(10,2) CHECK (max_price >= 0),
    alerts_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT saved_search_shape_chk CHECK (
        (module = 'buy_sell'   AND lf_category_id IS NULL) OR
        (module = 'lost_found' AND bs_category_id IS NULL AND min_price IS NULL AND max_price IS NULL)),
    CONSTRAINT saved_search_price_chk CHECK (min_price IS NULL OR max_price IS NULL OR min_price <= max_price)
);
CREATE INDEX idx_saved_searches_user   ON saved_searches(user_id, created_at);
CREATE INDEX idx_saved_searches_alerts ON saved_searches(module) WHERE alerts_enabled;

-- ============================================================================
-- PHASE 1 — ACADEMIC HELP CONTENT  (FR-11, FR-12, FR-13)
-- ============================================================================
CREATE TABLE course_materials (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id         UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    uploaded_by       UUID NOT NULL REFERENCES users(id),
    title             TEXT NOT NULL,
    material_type     material_type NOT NULL DEFAULT 'other',
    file_s3_key       TEXT NOT NULL,
    -- rev 22: the shared repository. Tags say what it is (pyq, quiz, notes, ...); held_for_review_at hides
    -- a file the upload check found suspicious until a course moderator decides.
    tags              TEXT[] NOT NULL DEFAULT '{}' CHECK (cardinality(tags) <= 5),
    description       TEXT CHECK (char_length(description) <= 2000),
    file_name         TEXT,
    size_bytes        BIGINT,
    content_type      TEXT,
    held_for_review_at TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ,
    deleted_by        UUID REFERENCES users(id),
    CONSTRAINT materials_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_materials_course ON course_materials(course_id) WHERE deleted_at IS NULL;   -- FR-11

-- rev 22: following a course: new materials, feedback and forum posts there notify you.
CREATE TABLE course_follows (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id  UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, course_id)
);
CREATE INDEX idx_course_follows_course ON course_follows(course_id);

CREATE TABLE course_feedback (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id    UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    author_id    UUID NOT NULL REFERENCES users(id),
    content      TEXT NOT NULL,
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,     -- rev 7: name hidden from everyone but the author
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES users(id),
    CONSTRAINT feedback_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_feedback_course ON course_feedback(course_id, created_at DESC) WHERE deleted_at IS NULL;  -- FR-11/12
-- rev 7: one review per person per course, so repeat posts can't skew the survival guide.
CREATE UNIQUE INDEX uq_feedback_one_per_author ON course_feedback(course_id, author_id) WHERE deleted_at IS NULL;

-- ============================================================================
-- PHASE 2 — PLACEMENT HUB  (FR-15, FR-16, FR-17)
-- (defined before forums because company forums reference companies)
-- ============================================================================
CREATE TABLE companies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL CHECK (char_length(btrim(name)) >= 1),
    name_key    TEXT GENERATED ALWAYS AS (lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))) STORED UNIQUE,
    description TEXT,
    website     TEXT,                          -- rev 16
    industry    TEXT,                          -- rev 16, e.g. 'Software', 'Finance', 'Semiconductors'
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- name_key lets the importer match "Walmart", "walmart " and "WALMART" to one company.

CREATE TABLE job_descriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role_title      TEXT NOT NULL,
    description     TEXT,                      -- rev 16: the JD as text
    compensation    TEXT,                      -- rev 16: as announced, e.g. '₹32 LPA'
    jd_s3_key       TEXT,                      -- optional JD file
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- rev 21: the season and what the role pays. ctc_min/ctc_max are rupees a year read from
    -- `compensation` (equal unless it's a range); NULL when it says "refer JD" and the like.
    placement_year  SMALLINT CHECK (placement_year BETWEEN 2000 AND 2100),
    job_type        TEXT NOT NULL DEFAULT 'full_time' CHECK (job_type IN ('full_time', 'internship', 'ppo', 'other')),
    ctc_min         BIGINT CHECK (ctc_min > 0),
    ctc_max         BIGINT CHECK (ctc_max >= ctc_min),
    base_text       TEXT,
    base_annual     BIGINT CHECK (base_annual > 0),
    skills          TEXT
);
-- One role per company, title, season and type: re-importing a file updates instead of duplicating.
CREATE UNIQUE INDEX uq_job_role_season
    ON job_descriptions (company_id, lower(role_title), coalesce(placement_year, 0), job_type);
CREATE INDEX idx_jd_company ON job_descriptions(company_id);

CREATE TABLE ppt_info (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id   UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    kind         TEXT NOT NULL DEFAULT 'ppt'   -- rev 17: ppt, oa (online test), interview, other
                 CHECK (kind IN ('ppt', 'oa', 'interview', 'other')),
    details      TEXT,
    venue        TEXT,                         -- rev 16
    scheduled_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    time_tbd     BOOLEAN NOT NULL DEFAULT FALSE  -- rev 20: imported without a time (shown as TBA)
);
CREATE INDEX idx_ppt_company ON ppt_info(company_id);

CREATE TABLE interview_experiences (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    author_id  UUID NOT NULL REFERENCES users(id),
    role_title TEXT,
    content    TEXT NOT NULL,
    is_anonymous   BOOLEAN NOT NULL DEFAULT FALSE,   -- rev 16: name hidden from everyone but the author
    placement_year SMALLINT CHECK (placement_year BETWEEN 2000 AND 2100),   -- rev 16
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES users(id),
    CONSTRAINT interview_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_interviews_company ON interview_experiences(company_id, created_at DESC) WHERE deleted_at IS NULL;

-- FR-17 bulk import. The moderator picks the placement year when uploading;
-- the sheet itself has no year column. Malformed rows are rejected and
-- listed (row number + reason) in the import API's response to the
-- moderator, which is how FR-17's "rejected and reported" is met; only the
-- counts are stored here.
CREATE TABLE placement_bulk_imports (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    moderator_id   UUID NOT NULL REFERENCES users(id),
    placement_year SMALLINT NOT NULL CHECK (placement_year BETWEEN 2000 AND 2100),
    source_s3_key  TEXT NOT NULL,
    rows_total     INT NOT NULL,
    rows_created   INT NOT NULL,
    rows_updated   INT NOT NULL,
    rows_rejected  INT NOT NULL,
    imported_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- FR-17 acceptance criterion: every row is created, updated or rejected — none silently dropped
    CONSTRAINT import_counts_chk CHECK (
        rows_total = rows_created + rows_updated + rows_rejected
        AND rows_created >= 0 AND rows_updated >= 0 AND rows_rejected >= 0)
);

-- One row per selected student, mirroring the placement sheet. Being in the
-- sheet means the student was selected (blocked) for that company, so the
-- sheet's status column is not stored:
--   Slot | Company | Student email | Role
--   Slot 2 | Walmart | chandus@iisc.ac.in | Software Engineer
-- A student's email appears once per placement year, so (placement_year,
-- student_email) is the FR-17 upsert key: re-importing an edited sheet
-- updates rows instead of duplicating them.
--   INSERT INTO placement_records (...) VALUES (...)
--   ON CONFLICT (placement_year, student_email) DO UPDATE
--     SET slot = EXCLUDED.slot, company_id = EXCLUDED.company_id,
--         role_title = EXCLUDED.role_title, import_id = EXCLUDED.import_id
--   RETURNING (xmax = 0) AS was_created;   -- true = created, false = updated
-- student_email is plain data, not a users FK: most placed students never
-- sign up. Guests only see the hiring_stats aggregates below. Since rev 18,
-- signed-in students also see the last two seasons' rows as "seniors to
-- contact" on the company's page (name, role, season and how to reach them),
-- unless a moderator hid the row (contact_hidden).
CREATE TABLE placement_records (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id      UUID REFERENCES placement_bulk_imports(id) ON DELETE SET NULL,
    placement_year SMALLINT NOT NULL CHECK (placement_year BETWEEN 2000 AND 2100),
    slot           TEXT,                                  -- e.g. 'Slot 2'
    company_id     UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    role_title     TEXT NOT NULL CHECK (char_length(btrim(role_title)) >= 1),
    student_email  citext NOT NULL                        -- rev 19: any email; malformed ones rejected (FR-17)
                   CONSTRAINT placement_records_email_chk
                   CHECK (student_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    contact_hidden BOOLEAN NOT NULL DEFAULT FALSE,        -- rev 18: not listed as a senior to contact
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (placement_year, student_email)
);
CREATE INDEX idx_placement_company_year ON placement_records(company_id, placement_year);

-- FR-15 "aggregated hiring statistics" and scenario 3 "last three years",
-- always computed from the records so they match the data exactly.
CREATE VIEW hiring_stats AS
SELECT company_id,
       placement_year,
       role_title,
       count(*) AS students_selected
FROM placement_records
GROUP BY company_id, placement_year, role_title;

-- rev 18: seniors to contact about a company who aren't on a placement sheet: off-campus offers,
-- PPOs, alumni. Added and edited by Placement Hub moderators; shown to signed-in students.
CREATE TABLE company_seniors (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name           TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
    email          TEXT NOT NULL CHECK (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    phone          TEXT CHECK (phone ~ '^\+?[0-9]{10,15}$'),
    role_title     TEXT CHECK (char_length(role_title) <= 200),
    placement_year SMALLINT NOT NULL CHECK (placement_year BETWEEN 2000 AND 2100),
    offer_type     TEXT NOT NULL DEFAULT 'off_campus'
                   CHECK (offer_type IN ('on_campus', 'off_campus', 'ppo', 'internship')),
    note           TEXT CHECK (char_length(note) <= 500),
    added_by       UUID NOT NULL REFERENCES users(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, email, placement_year)
);

-- ============================================================================
-- SHARED — FORUMS  (FR-14; course/department forums for Academic Help,
-- company forums for Placement Hub)
--
--   Forum   — one per course / department / company (the board)
--   Thread  — one topic inside a forum; has its own title and author
--   Comment — one message in a thread; the first by seq is the opening post
--
-- Deleting a course/department/company deletes its forum, which deletes the
-- forum's threads, which deletes their comments (and reports about them).
-- ============================================================================
CREATE TABLE forums (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_type    forum_scope_type NOT NULL,
    course_id     UUID UNIQUE REFERENCES courses(id)     ON DELETE CASCADE,
    department_id UUID UNIQUE REFERENCES departments(id) ON DELETE CASCADE,
    company_id    UUID UNIQUE REFERENCES companies(id)   ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    -- event_id and forum_scope_shape_chk (exactly one owner, matching scope_type) are added after
    -- the events table below; UNIQUE on each id = one forum per course/department/company/event
);

CREATE TABLE threads (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    forum_id   UUID NOT NULL REFERENCES forums(id) ON DELETE CASCADE,
    author_id  UUID NOT NULL REFERENCES users(id),     -- owner: may edit title / delete (§3.1)
    title      TEXT NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES users(id),             -- author, moderator or admin
    CONSTRAINT threads_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_threads_forum  ON threads(forum_id, created_at DESC) WHERE deleted_at IS NULL;  -- thread list
CREATE INDEX idx_threads_author ON threads(author_id);                                          -- "my threads"

-- Order within a thread is by seq, an auto-increment assigned at insert, so
-- it never depends on timestamps or random UUIDs (FR-14 "preserving thread
-- order"). The opening post is the comment with the smallest seq; create the
-- thread and its opening comment in the same transaction.
--   SELECT * FROM comments WHERE thread_id = :tid ORDER BY seq;
-- A comment's forum is always its thread's forum (no separate forum_id).
CREATE TABLE comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seq        BIGINT GENERATED ALWAYS AS IDENTITY,
    thread_id  UUID NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id),
    parent_id  UUID REFERENCES comments(id) ON DELETE CASCADE,  -- rev 17: reply to a reply; NULL = top level
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES users(id),
    CONSTRAINT comments_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX idx_comments_thread_seq ON comments(thread_id, seq);   -- not partial: show removed ones as "[removed]"
CREATE INDEX idx_comments_user       ON comments(user_id);          -- "my comments"; reply-notification recipients
CREATE INDEX idx_comments_parent     ON comments(parent_id) WHERE parent_id IS NOT NULL;

-- rev 17: Reddit-style votes. One vote per person per thread / comment: +1 up, -1 down;
-- taking a vote back deletes the row. A thread's score is the sum of its thread_votes.
CREATE TABLE thread_votes (
    thread_id  UUID NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    value      SMALLINT NOT NULL CHECK (value IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (thread_id, user_id)
);
CREATE TABLE comment_votes (
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    value      SMALLINT NOT NULL CHECK (value IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, user_id)
);

-- Removing a thread removes its comments: when a thread is soft-deleted,
-- its still-visible comments are soft-deleted with the same time and actor.
-- (A hard delete already cascades through the thread_id foreign key.)
CREATE FUNCTION cascade_thread_soft_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE comments
        SET deleted_at = NEW.deleted_at, deleted_by = NEW.deleted_by
        WHERE thread_id = NEW.id AND deleted_at IS NULL;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_threads_cascade_soft_delete
    AFTER UPDATE OF deleted_at ON threads
    FOR EACH ROW EXECUTE FUNCTION cascade_thread_soft_delete();

-- Who may remove a thread or comment other than its author (§3.1):
--   any active admin;
--   course forum      -> that course's course moderator, or a department
--                        moderator of the course's department;
--   department forum  -> that department's department moderator;
--   company forum     -> a placement_hub moderator;
--   event forum       -> an events moderator (rev 17).
-- The API checks: author_id = :user OR can_moderate_forum(:user, forum_id)
--   UPDATE threads SET deleted_at = now(), deleted_by = :user
--   WHERE id = :tid AND deleted_at IS NULL
--     AND (author_id = :user OR can_moderate_forum(:user, forum_id));
CREATE FUNCTION can_moderate_forum(p_user UUID, p_forum UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM users u
                   WHERE u.id = p_user AND u.is_active AND u.base_role = 'admin')
        OR EXISTS (
            SELECT 1
            FROM forums f
            LEFT JOIN courses c ON c.id = f.course_id
            JOIN users u ON u.id = p_user AND u.is_active
            JOIN moderator_assignments m ON m.user_id = p_user AND m.revoked_at IS NULL
            WHERE f.id = p_forum
              AND (   (f.scope_type = 'course'     AND m.module = 'academic_help'
                       AND (m.course_id = f.course_id OR m.department_id = c.department_id))
                   OR (f.scope_type = 'department' AND m.module = 'academic_help'
                       AND m.department_id = f.department_id)
                   OR (f.scope_type = 'company'    AND m.module = 'placement_hub')
                   OR (f.scope_type = 'event'      AND m.module = 'events')));
$$;

-- ============================================================================
-- SHARED — USER REPORTS (flags raised against content: a listing selling
-- drugs/weapons, an abusive comment, ...)
--
-- Exactly one target column is set, matching target_type. They are real
-- foreign keys, so a report can only point at an item that exists and is
-- deleted together with it (e.g. when a course is deleted). target_id is a
-- convenience copy of whichever one is set.
--
-- Workflow: open -> actioned (content removed) or dismissed (flag was wrong).
-- Handling one item closes every open report on it:
--   UPDATE reports SET status = 'actioned', handled_by = :mod, handled_at = now()
--   WHERE target_type = 'listing' AND target_id = :listing_id AND status = 'open';
-- Moderator queue for a module:
--   SELECT * FROM reports WHERE module = :module AND status = 'open' ORDER BY created_at;
-- ============================================================================
CREATE TABLE reports (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id             UUID REFERENCES users(id),                -- NULL for automatic flags
    source                  report_source NOT NULL DEFAULT 'user',
    module                  module_name NOT NULL,
    target_type             report_target_type NOT NULL,
    listing_id              UUID REFERENCES listings(id)              ON DELETE CASCADE,
    lost_report_id          UUID REFERENCES lost_reports(id)          ON DELETE CASCADE,
    found_report_id         UUID REFERENCES found_reports(id)         ON DELETE CASCADE,
    course_material_id      UUID REFERENCES course_materials(id)      ON DELETE CASCADE,
    course_feedback_id      UUID REFERENCES course_feedback(id)       ON DELETE CASCADE,
    thread_id               UUID REFERENCES threads(id)               ON DELETE CASCADE,
    comment_id              UUID REFERENCES comments(id)              ON DELETE CASCADE,
    interview_experience_id UUID REFERENCES interview_experiences(id) ON DELETE CASCADE,
    wanted_post_id          UUID REFERENCES wanted_posts(id)          ON DELETE CASCADE,
    target_id               UUID GENERATED ALWAYS AS (coalesce(
                                listing_id, lost_report_id, found_report_id, course_material_id,
                                course_feedback_id, thread_id, comment_id, interview_experience_id,
                                wanted_post_id)) STORED,
    reason                  TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 1000),
    status                  report_status NOT NULL DEFAULT 'open',
    handled_by              UUID REFERENCES users(id),
    handled_at              TIMESTAMPTZ,
    resolution_note         TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reports_one_target_chk CHECK (num_nonnulls(
        listing_id, lost_report_id, found_report_id, course_material_id,
        course_feedback_id, thread_id, comment_id, interview_experience_id, wanted_post_id) = 1),
    CONSTRAINT reports_target_type_chk CHECK (CASE target_type
        WHEN 'listing'              THEN listing_id IS NOT NULL
        WHEN 'lost_report'          THEN lost_report_id IS NOT NULL
        WHEN 'found_report'         THEN found_report_id IS NOT NULL
        WHEN 'course_material'      THEN course_material_id IS NOT NULL
        WHEN 'course_feedback'      THEN course_feedback_id IS NOT NULL
        WHEN 'thread'               THEN thread_id IS NOT NULL
        WHEN 'comment'              THEN comment_id IS NOT NULL
        WHEN 'interview_experience' THEN interview_experience_id IS NOT NULL
        WHEN 'wanted_post'          THEN wanted_post_id IS NOT NULL END),
    -- module must fit the target (thread/comment: academic_help for course/department
    -- forums, placement_hub for company forums, events for event forums — the API sets it from the forum)
    CONSTRAINT reports_module_chk CHECK (
        (target_type IN ('listing', 'wanted_post')            AND module = 'buy_sell') OR
        (target_type IN ('lost_report', 'found_report')       AND module = 'lost_found') OR
        (target_type IN ('course_material', 'course_feedback') AND module = 'academic_help') OR
        (target_type = 'interview_experience'                 AND module = 'placement_hub') OR
        (target_type IN ('thread', 'comment')                 AND module IN ('academic_help', 'placement_hub', 'events'))),
    CONSTRAINT reports_source_chk CHECK ((source = 'user') = (reporter_id IS NOT NULL)),
    -- open reports have no handler; handled ones always record who and when
    CONSTRAINT reports_handled_chk CHECK (
        (status = 'open' AND handled_by IS NULL AND handled_at IS NULL) OR
        (status <> 'open' AND handled_by IS NOT NULL AND handled_at IS NOT NULL))
);
-- One open report per user per item (stops one person flagging a post 50 times);
-- the same user may report again after an earlier report was handled.
CREATE UNIQUE INDEX uq_reports_one_open ON reports(reporter_id, target_type, target_id) WHERE status = 'open';
CREATE UNIQUE INDEX uq_reports_one_open_system ON reports(target_type, target_id)
    WHERE status = 'open' AND source = 'system';
CREATE INDEX idx_reports_queue  ON reports(module, created_at) WHERE status = 'open';
CREATE INDEX idx_reports_target ON reports(target_type, target_id);

-- ============================================================================
-- SHARED — MODERATION AUDIT LOG (actions moderators TAKE)
-- Deliberately has no foreign key to the target, so the history survives
-- even after the item (or its course) is deleted.
-- ============================================================================
CREATE TABLE moderation_log (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    moderator_id UUID NOT NULL REFERENCES users(id),
    action       TEXT NOT NULL,             -- e.g. 'remove_listing', 'grant_moderator', 'delete_course'
    target_type  TEXT NOT NULL,
    target_id    UUID NOT NULL,
    reason       TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- BUY & SELL — SELLER TRUST SCORE (future plan §1.5)
-- One row per moderator-confirmed listing removal against a seller. Never created from a raw
-- report — only from POST /reports/{id}/resolve with remove_content=true on a listing. Rows are
-- never deleted (tamper-proof history); a moderator who overturns one sets excluded=true instead,
-- which drops it from the seller's "Negative Seller" / "Blocked Seller" tag (app/seller_trust.py).
-- ============================================================================
CREATE TABLE seller_strikes (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id      UUID NOT NULL REFERENCES users(id),
    -- Both null once the seller deletes the listing (deletes are permanent, rev 23); the title stays.
    listing_id     UUID REFERENCES listings(id) ON DELETE SET NULL,
    listing_title  TEXT,
    report_id      UUID UNIQUE REFERENCES reports(id) ON DELETE SET NULL,  -- one strike per resolved report
    severity       seller_strike_severity NOT NULL,
    moderator_id   UUID NOT NULL REFERENCES users(id),
    moderator_note TEXT,
    -- The seller's one-shot appeal (future plan §1.5.2's "lightweight appeal"); a moderator
    -- resolves it by overturning the strike (restores the listing) or rejecting the appeal
    -- (appeal_resolved_at/by set, excluded stays false, listing stays hidden).
    appeal_message     TEXT,
    appeal_created_at  TIMESTAMPTZ,
    appeal_resolved_at TIMESTAMPTZ,
    appeal_resolved_by UUID REFERENCES users(id),
    excluded          BOOLEAN NOT NULL DEFAULT FALSE,
    excluded_by       UUID REFERENCES users(id),
    excluded_at       TIMESTAMPTZ,
    excluded_note     TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_seller_strikes_seller ON seller_strikes(seller_id);
-- The moderator queue: strikes with an appeal nobody has resolved yet.
CREATE INDEX idx_seller_strikes_pending_appeal ON seller_strikes(appeal_created_at)
    WHERE appeal_message IS NOT NULL AND appeal_resolved_at IS NULL;

-- listings.hidden_by_strike_id forward-references this table, so it's added here (not in
-- CREATE TABLE listings above) to avoid a circular definition - listings referencing a strike
-- that itself references the listing it strikes.
ALTER TABLE listings ADD COLUMN hidden_by_strike_id UUID REFERENCES seller_strikes(id);
CREATE INDEX idx_listings_hidden ON listings(hidden_by_strike_id) WHERE hidden_by_strike_id IS NOT NULL;
CREATE INDEX idx_listings_held ON listings(held_for_review_at) WHERE held_for_review_at IS NOT NULL;

-- Price watch (future plan §2.3): told when the price changes or the listing is marked negotiable.
CREATE TABLE listing_watches (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, listing_id)
);
CREATE INDEX idx_listing_watches_listing ON listing_watches(listing_id);

-- ============================================================================
-- PHASE 2 — COMMUNITY / CULTURE EVENTS  (FR-18, FR-19, FR-20, FR-21, FR-22)
-- The creator edits/deletes their event; admins can edit/delete any event, and
-- events moderators (rev 17) can remove any event.
-- ============================================================================
CREATE TABLE event_tags (
    id         SERIAL PRIMARY KEY,
    name       TEXT UNIQUE NOT NULL,        -- Sports, Food/Mess, Nature, Photography, Culture, ...
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by  UUID NOT NULL REFERENCES users(id),
    title       TEXT NOT NULL,
    description TEXT,
    location    TEXT,
    start_time  TIMESTAMPTZ NOT NULL,
    end_time    TIMESTAMPTZ NOT NULL,
    poster_s3_key TEXT,                                 -- rev 17: optional poster image
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),     -- FR-20: detect "event updated"
    deleted_at  TIMESTAMPTZ,
    deleted_by  UUID REFERENCES users(id),
    CHECK (end_time > start_time),
    CONSTRAINT events_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
-- Past/Present/Upcoming (FR-19) is derived, never stored:
--   CASE WHEN now() < start_time THEN 'upcoming'
--        WHEN now() <= end_time  THEN 'present'
--        ELSE 'past' END
CREATE INDEX idx_events_time ON events(start_time, end_time) WHERE deleted_at IS NULL;

-- rev 17: every event has a discussion forum too (forums is defined before events).
ALTER TABLE forums ADD COLUMN event_id UUID UNIQUE REFERENCES events(id) ON DELETE CASCADE;
ALTER TABLE forums ADD CONSTRAINT forum_scope_shape_chk CHECK (
    num_nonnulls(course_id, department_id, company_id, event_id) = 1 AND CASE scope_type
        WHEN 'course'     THEN course_id IS NOT NULL
        WHEN 'department' THEN department_id IS NOT NULL
        WHEN 'company'    THEN company_id IS NOT NULL
        WHEN 'event'      THEN event_id IS NOT NULL END);

CREATE TABLE event_tag_map (
    event_id   UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    tag_id     INT NOT NULL REFERENCES event_tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, tag_id)
);
CREATE INDEX idx_event_tag_map_tag ON event_tag_map(tag_id, event_id);   -- FR-18 filter by tag

-- FR-20 "followed-tag": a user follows a tag (e.g. Photography) and is
-- notified about new or updated events carrying it. Separate from bookmarks,
-- which point at one specific event.
CREATE TABLE tag_follows (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tag_id     INT NOT NULL REFERENCES event_tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, tag_id)
);
CREATE INDEX idx_tag_follows_tag ON tag_follows(tag_id);   -- "who follows this tag?" for notification fan-out

-- rev 18: mess menus. A mess posts its menu for a month (or so): what each meal has on each
-- weekday, repeating every week, plus the PDF/image it came from. People who follow a mess get an
-- alert shortly before each meal they chose, with that day's dishes (app/mess_alerts.py, run every
-- few minutes; mess_alerts_sent makes it send each meal once). Events moderators and admins manage menus.
CREATE TABLE messes (
    id           SERIAL PRIMARY KEY,
    name         TEXT UNIQUE NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 60),   -- 'C Mess'
    breakfast_at TIME NOT NULL DEFAULT '07:30',      -- India time
    lunch_at     TIME NOT NULL DEFAULT '12:30',
    snacks_at    TIME NOT NULL DEFAULT '16:45',
    dinner_at    TIME NOT NULL DEFAULT '19:30',
    event_id     UUID REFERENCES events(id) ON DELETE SET NULL,   -- rev 20: its Food/Mess event card
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE mess_menus (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mess_id     INT NOT NULL REFERENCES messes(id) ON DELETE CASCADE,
    valid_from  DATE NOT NULL,
    valid_to    DATE NOT NULL,                       -- menus of one mess don't overlap (checked by the API)
    file_s3_key TEXT,                                -- upload kind mess_menu: the menu as a PDF or image
    notes       TEXT CHECK (char_length(notes) <= 2000),
    created_by  UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (valid_to >= valid_from AND valid_to - valid_from <= 92)
);
CREATE INDEX idx_mess_menus_mess ON mess_menus(mess_id, valid_from);
CREATE TABLE mess_menu_items (
    menu_id UUID NOT NULL REFERENCES mess_menus(id) ON DELETE CASCADE,
    weekday SMALLINT NOT NULL CHECK (weekday BETWEEN 1 AND 7),     -- ISO: 1 = Monday
    meal    TEXT NOT NULL CHECK (meal IN ('breakfast', 'lunch', 'snacks', 'dinner')),
    items   TEXT NOT NULL CHECK (char_length(btrim(items)) BETWEEN 1 AND 1000),
    PRIMARY KEY (menu_id, weekday, meal)
);
CREATE TABLE mess_follows (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mess_id    INT NOT NULL REFERENCES messes(id) ON DELETE CASCADE,
    meals      TEXT[] NOT NULL CHECK (cardinality(meals) >= 1
                   AND meals <@ ARRAY['breakfast', 'lunch', 'snacks', 'dinner']),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, mess_id)
);
CREATE INDEX idx_mess_follows_mess ON mess_follows(mess_id);
CREATE TABLE mess_alerts_sent (
    mess_id    INT NOT NULL REFERENCES messes(id) ON DELETE CASCADE,
    day        DATE NOT NULL,
    meal       TEXT NOT NULL,
    recipients INT NOT NULL,
    sent_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (mess_id, day, meal)
);

-- ============================================================================
-- PHASE 2 — BOOKMARKS  (FR-20; signed-in only — guest bookmarks stay on-device)
-- ============================================================================
CREATE TABLE bookmarks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type bookmark_target_type NOT NULL,
    target_id   UUID NOT NULL,            -- listings.id or events.id
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, target_type, target_id)
);
CREATE INDEX idx_bookmarks_target ON bookmarks(target_type, target_id);   -- "who bookmarked this event?"

-- ============================================================================
-- PHASE 2 — NOTIFICATIONS  (FR-9, FR-20, FR-22; read in the NFR-2 load mix)
-- In-app inbox. Short-lived rows: purge with a scheduled job, e.g. daily
--   DELETE FROM notifications WHERE created_at < now() - interval '30 days';
-- ============================================================================
CREATE TABLE notifications (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type       notification_type NOT NULL,
    payload    JSONB NOT NULL,
    is_read    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_inbox  ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(user_id) WHERE is_read = FALSE;

-- Push delivery targets (FR-9, FR-20, FR-22). Each phone/browser/desktop app
-- registers the token its push service (FCM / APNs / Web Push) gives it.
-- To push, the backend sends to every device of the user. On login:
--   INSERT INTO push_devices (user_id, platform, push_token) VALUES (...)
--   ON CONFLICT (push_token) DO UPDATE SET user_id = EXCLUDED.user_id;
-- (a shared device that switches user moves to the new user). Delete the row
-- on logout, and when the push service reports the token as invalid.
CREATE TABLE push_devices (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform         device_platform NOT NULL,
    push_token       TEXT NOT NULL UNIQUE,
    sns_endpoint_arn TEXT UNIQUE,            -- set if delivering through Amazon SNS mobile push
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_push_devices_user ON push_devices(user_id);

-- ============================================================================
-- MESSAGES (rev 8) — end-to-end encrypted buyer–seller chat about a listing
--   Every message is encrypted on the sender's device and decrypted on the
--   recipient's. The server stores ciphertext, but (rev 9) it also holds each
--   user's private key, so it is not end-to-end encrypted yet.
--
--   chat_keys           one X25519 public key per user (plus retired ones, so
--                       old messages still say which key they used). Since rev 9
--                       the app stores the private key here in plain form
--                       (backup_kdf 'none') so any browser can open messages
--                       without a passphrase. That means the SERVER CAN READ
--                       MESSAGES for now: true end-to-end encryption is future
--                       work (docs/future-plan-2026-10-31-next-level-features.md).
--                       Old 'pbkdf2-sha256' rows are passphrase-encrypted backups.
--   chat_conversations  one per pair of people (rev 10), like a WhatsApp chat:
--                       user_a < user_b. last_seq numbers every change in it;
--                       clients sync with "changes after N".
--   chat_topics         what part of a chat is about: a listing, a lost report
--                       or a found report. A message has at most one topic (none
--                       for general chat); an offer always has a listing topic.
--   chat_messages       nonce + AES-256-GCM ciphertext; offers carry their
--                       amount inside the ciphertext and a status the server
--                       tracks (only the other person can accept or decline).
--   chat_blocks         a blocked person can't send to (or start chats with)
--                       the person who blocked them.
-- ============================================================================
CREATE TABLE chat_keys (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    public_key        BYTEA NOT NULL CHECK (octet_length(public_key) = 32),   -- X25519
    key_backup        BYTEA NOT NULL,
    backup_salt       BYTEA,
    backup_kdf        TEXT NOT NULL,       -- 'none' (rev 9): key_backup is the plain private key
    backup_iterations INT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    retired_at        TIMESTAMPTZ,                                            -- replaced by a newer key
    CONSTRAINT chat_keys_backup_check CHECK (
        (backup_kdf = 'pbkdf2-sha256'
            AND octet_length(key_backup) BETWEEN 44 AND 512
            AND octet_length(backup_salt) BETWEEN 16 AND 64
            AND backup_iterations BETWEEN 100000 AND 10000000)
        OR (backup_kdf = 'none'
            AND octet_length(key_backup) = 32
            AND backup_salt IS NULL
            AND backup_iterations IS NULL))
);
CREATE UNIQUE INDEX uq_chat_key_active ON chat_keys(user_id) WHERE retired_at IS NULL;

CREATE TABLE chat_conversations (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a               UUID NOT NULL REFERENCES users(id),
    user_b               UUID NOT NULL REFERENCES users(id),
    created_by           UUID NOT NULL REFERENCES users(id),
    last_seq             BIGINT NOT NULL DEFAULT 0,
    user_a_last_read_seq BIGINT NOT NULL DEFAULT 0,
    user_b_last_read_seq BIGINT NOT NULL DEFAULT 0,
    -- rev 19: "delete chat" for one person: their view starts after this seq; nothing is erased
    user_a_cleared_seq   BIGINT NOT NULL DEFAULT 0,
    user_b_cleared_seq   BIGINT NOT NULL DEFAULT 0,
    last_message_at      TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chat_pair_ordered CHECK (user_a < user_b),
    CONSTRAINT chat_pair_unique UNIQUE (user_a, user_b)
);
CREATE INDEX idx_chat_conv_user_b ON chat_conversations(user_b, last_message_at DESC NULLS LAST);

CREATE TABLE chat_topics (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    kind            chat_topic_kind NOT NULL,
    -- No foreign key: a deleted listing is gone (rev 23) but the chat keeps its title and seller.
    listing_id      UUID,
    listing_title   TEXT,
    listing_seller_id UUID REFERENCES users(id),
    lost_report_id  UUID REFERENCES lost_reports(id),
    found_report_id UUID REFERENCES found_reports(id),
    started_by      UUID NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chat_topic_one_ref CHECK (
        (kind = 'listing')      = (listing_id IS NOT NULL) AND
        (kind = 'lost_report')  = (lost_report_id IS NOT NULL) AND
        (kind = 'found_report') = (found_report_id IS NOT NULL)),
    UNIQUE (conversation_id, listing_id),
    UNIQUE (conversation_id, lost_report_id),
    UNIQUE (conversation_id, found_report_id)
);

-- id is chosen by the sender's app: it is part of what the ciphertext is bound to, and
-- resending after a network error can't create a duplicate.
CREATE TABLE chat_messages (
    id               UUID PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    seq              BIGINT NOT NULL,                  -- order within the conversation
    changed_seq      BIGINT NOT NULL,                  -- last change (sent, offer answered, unsent)
    sender_id        UUID NOT NULL REFERENCES users(id),
    kind             chat_message_kind NOT NULL DEFAULT 'text',
    sender_key_id    UUID NOT NULL REFERENCES chat_keys(id),
    recipient_key_id UUID NOT NULL REFERENCES chat_keys(id),
    nonce            BYTEA CHECK (octet_length(nonce) = 12),
    ciphertext       BYTEA CHECK (octet_length(ciphertext) BETWEEN 17 AND 16400),   -- includes the 16-byte tag
    offer_status     chat_offer_status,
    offer_answered_at TIMESTAMPTZ,
    sent_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,                      -- unsent: the ciphertext is erased
    topic_id         UUID REFERENCES chat_topics(id),  -- null: general chat
    -- The id the ciphertext is bound to (key derivation and associated data): the conversation
    -- id, except for messages from before rev 10, which keep their old per-listing chat's id.
    crypto_context_id UUID NOT NULL,
    CONSTRAINT chat_offer_has_status CHECK ((kind = 'offer') = (offer_status IS NOT NULL)),
    CONSTRAINT chat_offer_has_topic CHECK (kind <> 'offer' OR topic_id IS NOT NULL),
    CONSTRAINT chat_content_until_unsent CHECK
        ((deleted_at IS NULL) = (nonce IS NOT NULL AND ciphertext IS NOT NULL)),
    UNIQUE (conversation_id, seq)
);
CREATE INDEX idx_chat_messages_changes ON chat_messages(conversation_id, changed_seq);
CREATE INDEX idx_chat_messages_sender  ON chat_messages(sender_id, sent_at DESC);         -- send rate limit
CREATE UNIQUE INDEX uq_chat_one_pending_offer ON chat_messages(topic_id) WHERE offer_status = 'pending';
CREATE INDEX idx_chat_messages_topic ON chat_messages(topic_id, seq);

-- rev 19: "delete for me" on one message; the other person still sees it.
CREATE TABLE chat_message_hides (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, message_id)
);

CREATE TABLE chat_blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT chat_block_not_self CHECK (blocker_id <> blocked_id)
);
CREATE INDEX idx_chat_blocks_blocked ON chat_blocks(blocked_id);

-- ============================================================================
-- CAMPUS SERVICES (rev 6) — Health Centre, Wellness Centre, grievance portals
-- on the landing page. Managed by the admin, so a changed link or phone number
-- needs no app release. Initial rows: db/reference-data.sql.
-- ============================================================================
CREATE TABLE campus_services (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    description TEXT,
    category    campus_service_category NOT NULL,
    url         TEXT CHECK (url ~ '^https?://'),
    phone       TEXT CHECK (phone ~ '^\+?[0-9 -]{3,20}$'),
    sort_order  SMALLINT NOT NULL DEFAULT 100,               -- lower first, within a category
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT campus_service_contact_chk CHECK (url IS NOT NULL OR phone IS NOT NULL)
);

-- ============================================================================
-- updated_at TRIGGERS — one per table that has an updated_at column
-- ============================================================================
CREATE TRIGGER trg_departments_updated_at           BEFORE UPDATE ON departments           FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_courses_updated_at               BEFORE UPDATE ON courses               FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_users_updated_at                 BEFORE UPDATE ON users                 FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_listings_updated_at              BEFORE UPDATE ON listings              FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_lost_reports_updated_at          BEFORE UPDATE ON lost_reports          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_found_reports_updated_at         BEFORE UPDATE ON found_reports         FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_course_materials_updated_at      BEFORE UPDATE ON course_materials      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_course_feedback_updated_at       BEFORE UPDATE ON course_feedback       FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_companies_updated_at             BEFORE UPDATE ON companies             FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_job_descriptions_updated_at      BEFORE UPDATE ON job_descriptions      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ppt_info_updated_at              BEFORE UPDATE ON ppt_info              FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_interview_experiences_updated_at BEFORE UPDATE ON interview_experiences FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_placement_records_updated_at     BEFORE UPDATE ON placement_records     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_threads_updated_at               BEFORE UPDATE ON threads               FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_comments_updated_at              BEFORE UPDATE ON comments              FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_reports_updated_at               BEFORE UPDATE ON reports               FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_events_updated_at                BEFORE UPDATE ON events                FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_push_devices_updated_at          BEFORE UPDATE ON push_devices          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_wanted_posts_updated_at          BEFORE UPDATE ON wanted_posts          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_saved_searches_updated_at        BEFORE UPDATE ON saved_searches        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_campus_services_updated_at       BEFORE UPDATE ON campus_services       FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_chat_keys_updated_at             BEFORE UPDATE ON chat_keys             FOR EACH ROW EXECUTE FUNCTION set_updated_at();
