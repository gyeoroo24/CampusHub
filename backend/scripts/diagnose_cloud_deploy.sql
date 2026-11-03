-- CampusHub cloud RDS diagnostic checks (read-only, makes no changes).
--
-- Run against the real deployed database, e.g.:
--   psql "$CAMPUSHUB_DATABASE_URL" -f diagnose_cloud_deploy.sql
-- or through whatever bastion / RDS Proxy connection you normally use to reach it.
--
-- Companion to diagnose_cloud_deploy.sh (which checks the Lambda/engine side). Compare the
-- output below against backend/db/schema.sql (currently "Revision 16") and the migration list
-- in docs/cloud-deployment-checklist.md to see what's actually applied vs. what's missing.

\echo '--- Postgres engine version (schema.sql needs 15+ for NULLS NOT DISTINCT) ---'
SELECT version();

\echo ''
\echo '--- moderator_assignments: does the table AND its unique index exist? ---'
-- If table_exists is set but index_exists is null, schema.sql died partway through applying
-- this table's statements (the CREATE UNIQUE INDEX is a separate statement right after the
-- CREATE TABLE) -- almost always because the engine above is older than Postgres 15.
SELECT to_regclass('moderator_assignments') AS table_exists,
       to_regclass('uq_mod_active_grant')   AS index_exists;

\echo ''
\echo '--- *_deleted_pair_chk constraints present (schema.sql defines 9: listings, wanted_posts,'
\echo '    lost_reports, found_reports, course_materials, course_feedback, interview_experiences,'
\echo '    threads, comments) ---'
SELECT conrelid::regclass AS table_name, conname
FROM pg_constraint
WHERE conname LIKE '%_deleted_pair_chk'
ORDER BY 1;

\echo ''
\echo '--- chat_messages: constraints and FKs (nonce = 12 bytes, ciphertext 17-16400 bytes) ---'
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'chat_messages'::regclass
ORDER BY conname;

\echo ''
\echo '--- chat_keys.key_backup: is it really NOT NULL as the app code assumes? ---'
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_name = 'chat_keys' AND column_name = 'key_backup';

\echo ''
\echo '--- Does any migration-tracking table exist? (schema.sql defines none today) ---'
SELECT table_name FROM information_schema.tables
WHERE table_name ILIKE '%migration%' OR table_name ILIKE '%schema_version%';

\echo ''
\echo '--- Highest-numbered migration-looking artifact, as a rough proxy ---'
-- seller_strikes/appeal columns only exist from migration 013/014 on; hidden_by_strike_id only
-- from 014; auto-flag/price-watch columns only from 015; placement/events tables only from 016.
-- A missing row here means that migration (or a later one) never ran.
SELECT 'seller_strikes table'              AS check, to_regclass('seller_strikes') IS NOT NULL AS present
UNION ALL
SELECT 'listings.hidden_by_strike_id',        EXISTS (SELECT 1 FROM information_schema.columns
                                                       WHERE table_name='listings' AND column_name='hidden_by_strike_id')
UNION ALL
SELECT 'listings.held_for_review_at (015)',   EXISTS (SELECT 1 FROM information_schema.columns
                                                       WHERE table_name='listings' AND column_name='held_for_review_at')
UNION ALL
SELECT 'events table (016)',                  to_regclass('events') IS NOT NULL
UNION ALL
SELECT 'chat_topics table (010)',             to_regclass('chat_topics') IS NOT NULL
UNION ALL
SELECT 'lf_matches table (012)',              to_regclass('lf_matches') IS NOT NULL;
