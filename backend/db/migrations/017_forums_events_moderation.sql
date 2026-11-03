-- Rev 17: Events moderators, event forums, Reddit-style forums (votes and replies to replies),
-- the placement schedule (online tests and interviews next to pre-placement talks) and event posters.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/017_forums_events_moderation.sql

-- New enum values must be committed before they can be used, so these run outside the transaction.
ALTER TYPE module_name      ADD VALUE IF NOT EXISTS 'events';
ALTER TYPE forum_scope_type ADD VALUE IF NOT EXISTS 'event';

BEGIN;

-- Events have forums.
ALTER TABLE forums ADD COLUMN IF NOT EXISTS event_id UUID UNIQUE REFERENCES events(id) ON DELETE CASCADE;
ALTER TABLE forums DROP CONSTRAINT IF EXISTS forum_scope_shape_chk;
ALTER TABLE forums ADD CONSTRAINT forum_scope_shape_chk CHECK (
    num_nonnulls(course_id, department_id, company_id, event_id) = 1 AND CASE scope_type
        WHEN 'course'     THEN course_id IS NOT NULL
        WHEN 'department' THEN department_id IS NOT NULL
        WHEN 'company'    THEN company_id IS NOT NULL
        WHEN 'event'      THEN event_id IS NOT NULL END);

-- Replies to replies, and votes.
ALTER TABLE comments ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES comments(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id) WHERE parent_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS thread_votes (
    thread_id  UUID NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    value      SMALLINT NOT NULL CHECK (value IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (thread_id, user_id)
);
CREATE TABLE IF NOT EXISTS comment_votes (
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    value      SMALLINT NOT NULL CHECK (value IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, user_id)
);

-- Events moderators moderate event forums.
CREATE OR REPLACE FUNCTION can_moderate_forum(p_user UUID, p_forum UUID) RETURNS BOOLEAN
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

-- Reports about posts in event forums go to the events queue.
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_module_chk;
ALTER TABLE reports ADD CONSTRAINT reports_module_chk CHECK (
    (target_type IN ('listing', 'wanted_post')            AND module = 'buy_sell') OR
    (target_type IN ('lost_report', 'found_report')       AND module = 'lost_found') OR
    (target_type IN ('course_material', 'course_feedback') AND module = 'academic_help') OR
    (target_type = 'interview_experience'                 AND module = 'placement_hub') OR
    (target_type IN ('thread', 'comment')                 AND module IN ('academic_help', 'placement_hub', 'events')));

-- The placement schedule: what kind of date each entry is.
ALTER TABLE ppt_info ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'ppt'
    CHECK (kind IN ('ppt', 'oa', 'interview', 'other'));

-- Event posters.
ALTER TABLE events ADD COLUMN IF NOT EXISTS poster_s3_key TEXT;

COMMIT;
