-- Rev 22: courses get a shared materials repository (anyone signed in uploads; files are checked and
-- suspicious ones held for the course's moderators), and people can follow a course for updates.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/022_course_repository_and_follows.sql

-- New enum values must be committed before they can be used, so this runs outside the transaction.
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'course_update';

BEGIN;
ALTER TABLE course_materials ADD COLUMN IF NOT EXISTS tags TEXT[] NOT NULL DEFAULT '{}'
    CHECK (cardinality(tags) <= 5);
ALTER TABLE course_materials ADD COLUMN IF NOT EXISTS description TEXT CHECK (char_length(description) <= 2000);
ALTER TABLE course_materials ADD COLUMN IF NOT EXISTS file_name TEXT;
ALTER TABLE course_materials ADD COLUMN IF NOT EXISTS size_bytes BIGINT;
ALTER TABLE course_materials ADD COLUMN IF NOT EXISTS content_type TEXT;
ALTER TABLE course_materials ADD COLUMN IF NOT EXISTS held_for_review_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS course_follows (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id  UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, course_id)
);
CREATE INDEX IF NOT EXISTS idx_course_follows_course ON course_follows(course_id);
COMMIT;
