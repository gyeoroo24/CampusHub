-- Upgrade a rev 6 database to rev 7: anonymous course feedback, and one review per person per course.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/007_feedback_rules.sql
--
-- Where someone already has several active reviews of the same course, the newest stays and the
-- older ones are soft-deleted (by their author), so the unique index can be built.
BEGIN;

ALTER TABLE course_feedback ADD COLUMN is_anonymous BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE course_feedback f SET deleted_at = now(), deleted_by = f.author_id
FROM (
    SELECT id, row_number() OVER (PARTITION BY course_id, author_id ORDER BY created_at DESC, id DESC) AS n
    FROM course_feedback WHERE deleted_at IS NULL
) ranked
WHERE f.id = ranked.id AND ranked.n > 1;

CREATE UNIQUE INDEX uq_feedback_one_per_author ON course_feedback(course_id, author_id) WHERE deleted_at IS NULL;

COMMIT;
