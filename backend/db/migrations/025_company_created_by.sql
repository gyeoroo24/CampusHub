-- Upgrade an existing rev 24 database to rev 25: who added each company, and titles on Lost & Found reports.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/025_company_created_by.sql
--
-- A moderator's profile lists the companies they added. Companies added before this revision have no
-- creator recorded, so they stay NULL and aren't listed for anyone.
-- Lost and found reports get a short title ("Black JBL earbuds"), like Buy & Sell listings. Older
-- reports have none (NULL); the app shows their description instead.

BEGIN;

ALTER TABLE companies ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_companies_created_by ON companies(created_by) WHERE created_by IS NOT NULL;
ALTER TABLE lost_reports ADD COLUMN IF NOT EXISTS title TEXT CHECK (char_length(btrim(title)) BETWEEN 1 AND 120);
ALTER TABLE found_reports ADD COLUMN IF NOT EXISTS title TEXT CHECK (char_length(btrim(title)) BETWEEN 1 AND 120);

COMMIT;
