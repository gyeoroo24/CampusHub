-- Rev 20: each mess has an event card (Food/Mess) kept in step with its menu, and placement dates
-- imported without a time say "time to be announced" instead of showing a made-up one.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/020_mess_event_cards_and_tba_times.sql

BEGIN;
ALTER TABLE messes ADD COLUMN IF NOT EXISTS event_id UUID REFERENCES events(id) ON DELETE SET NULL;
ALTER TABLE ppt_info ADD COLUMN IF NOT EXISTS time_tbd BOOLEAN NOT NULL DEFAULT FALSE;
COMMIT;
