-- Upgrade an existing rev 5 database to rev 6 (saved searches, Wanted posts, campus services).
-- A new database doesn't need this: schema.sql already has everything.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/006_taking_it_further.sql
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/reference-data.sql
--
-- The new enum values have to be committed before a constraint can use them, so they are added
-- first, outside the transaction below.

ALTER TYPE notification_type  ADD VALUE IF NOT EXISTS 'saved_search_match';
ALTER TYPE notification_type  ADD VALUE IF NOT EXISTS 'wanted_post_match';
ALTER TYPE report_target_type ADD VALUE IF NOT EXISTS 'wanted_post';

BEGIN;

CREATE TYPE wanted_status AS ENUM ('open', 'fulfilled', 'closed');
CREATE TYPE campus_service_category AS ENUM ('health', 'wellbeing', 'grievance', 'safety', 'other');

CREATE TABLE wanted_posts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id     UUID NOT NULL REFERENCES users(id),
    title         TEXT NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
    description   TEXT,
    category_id   INT NOT NULL REFERENCES bs_categories(id),
    max_price     NUMERIC(10,2) CHECK (max_price >= 0),
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

CREATE TABLE saved_searches (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module         module_name NOT NULL CHECK (module IN ('buy_sell', 'lost_found')),
    name           TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    query          TEXT CHECK (char_length(query) <= 200),
    bs_category_id INT REFERENCES bs_categories(id),
    lf_category_id INT REFERENCES lf_categories(id),
    min_price      NUMERIC(10,2) CHECK (min_price >= 0),
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

CREATE TABLE campus_services (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    description TEXT,
    category    campus_service_category NOT NULL,
    url         TEXT CHECK (url ~ '^https?://'),
    phone       TEXT CHECK (phone ~ '^\+?[0-9 -]{3,20}$'),
    sort_order  SMALLINT NOT NULL DEFAULT 100,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT campus_service_contact_chk CHECK (url IS NOT NULL OR phone IS NOT NULL)
);

-- Reports can point at a Wanted post. target_id is a generated column, so it is rebuilt to
-- include the new column; its two indexes go with it and are recreated.
ALTER TABLE reports ADD COLUMN wanted_post_id UUID REFERENCES wanted_posts(id) ON DELETE CASCADE;
ALTER TABLE reports DROP COLUMN target_id;
ALTER TABLE reports ADD COLUMN target_id UUID GENERATED ALWAYS AS (coalesce(
    listing_id, lost_report_id, found_report_id, course_material_id,
    course_feedback_id, thread_id, comment_id, interview_experience_id, wanted_post_id)) STORED;
CREATE UNIQUE INDEX uq_reports_one_open ON reports(reporter_id, target_type, target_id) WHERE status = 'open';
CREATE INDEX idx_reports_target ON reports(target_type, target_id);
ALTER TABLE reports DROP CONSTRAINT reports_one_target_chk, ADD CONSTRAINT reports_one_target_chk CHECK (num_nonnulls(
    listing_id, lost_report_id, found_report_id, course_material_id,
    course_feedback_id, thread_id, comment_id, interview_experience_id, wanted_post_id) = 1);
ALTER TABLE reports DROP CONSTRAINT reports_target_type_chk, ADD CONSTRAINT reports_target_type_chk CHECK (CASE target_type
    WHEN 'listing'              THEN listing_id IS NOT NULL
    WHEN 'lost_report'          THEN lost_report_id IS NOT NULL
    WHEN 'found_report'         THEN found_report_id IS NOT NULL
    WHEN 'course_material'      THEN course_material_id IS NOT NULL
    WHEN 'course_feedback'      THEN course_feedback_id IS NOT NULL
    WHEN 'thread'               THEN thread_id IS NOT NULL
    WHEN 'comment'              THEN comment_id IS NOT NULL
    WHEN 'interview_experience' THEN interview_experience_id IS NOT NULL
    WHEN 'wanted_post'          THEN wanted_post_id IS NOT NULL END);
ALTER TABLE reports DROP CONSTRAINT reports_module_chk, ADD CONSTRAINT reports_module_chk CHECK (
    (target_type IN ('listing', 'wanted_post')            AND module = 'buy_sell') OR
    (target_type IN ('lost_report', 'found_report')       AND module = 'lost_found') OR
    (target_type IN ('course_material', 'course_feedback') AND module = 'academic_help') OR
    (target_type = 'interview_experience'                 AND module = 'placement_hub') OR
    (target_type IN ('thread', 'comment')                 AND module IN ('academic_help', 'placement_hub')));

CREATE TRIGGER trg_wanted_posts_updated_at    BEFORE UPDATE ON wanted_posts    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_saved_searches_updated_at  BEFORE UPDATE ON saved_searches  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_campus_services_updated_at BEFORE UPDATE ON campus_services FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
