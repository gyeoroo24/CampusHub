-- Upgrade an existing rev 12 database to rev 13 (Placement Hub and Community Events APIs).
-- A new database doesn't need this: schema.sql already has everything.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/013_placement_and_events.sql
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub < db/reference-data.sql
--
-- reference-data.sql adds the default event tags (Sports, Food/Mess, Nature, ...); running it twice adds nothing.
--
-- The Placement Hub and Events tables already exist since rev 3; this only adds the columns the
-- company page and interview experiences show.

BEGIN;

ALTER TABLE companies        ADD COLUMN IF NOT EXISTS website  TEXT;
ALTER TABLE companies        ADD COLUMN IF NOT EXISTS industry TEXT;
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS description  TEXT;
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS compensation TEXT;
ALTER TABLE ppt_info         ADD COLUMN IF NOT EXISTS venue TEXT;
ALTER TABLE interview_experiences ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE interview_experiences ADD COLUMN IF NOT EXISTS placement_year SMALLINT
    CHECK (placement_year BETWEEN 2000 AND 2100);

COMMIT;
