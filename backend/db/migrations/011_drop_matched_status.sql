-- Rev 11: Lost & Found reports are just open or closed. The "matched" status is no longer offered
-- by the app or accepted by the API, so any report still marked matched goes back to open.
-- (The enum value stays in lost_found_status: removing a Postgres enum value means rebuilding the
-- type, and nothing can write it any more.)
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/011_drop_matched_status.sql

BEGIN;
UPDATE lost_reports  SET status = 'open' WHERE status = 'matched';
UPDATE found_reports SET status = 'open' WHERE status = 'matched';
COMMIT;
