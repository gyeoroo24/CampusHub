-- Rev 21: roles carry their season, type and compensation (imported from "roles and compensation"
-- files or typed in), so company pages and statistics can show what each company pays.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/021_role_compensation.sql

BEGIN;
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS placement_year SMALLINT
    CHECK (placement_year BETWEEN 2000 AND 2100);
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS job_type TEXT NOT NULL DEFAULT 'full_time'
    CHECK (job_type IN ('full_time', 'internship', 'ppo', 'other'));
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS ctc_min BIGINT CHECK (ctc_min > 0);
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS ctc_max BIGINT CHECK (ctc_max >= ctc_min);
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS base_text TEXT;
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS base_annual BIGINT CHECK (base_annual > 0);
ALTER TABLE job_descriptions ADD COLUMN IF NOT EXISTS skills TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_job_role_season
    ON job_descriptions (company_id, lower(role_title), coalesce(placement_year, 0), job_type);
COMMIT;
