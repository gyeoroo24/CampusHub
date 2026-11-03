-- Upgrade an existing rev 23 database to rev 24: event updates (official notices on an event).
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/024_event_updates.sql
--
-- Event pages show "Updates" from the organizer and Events moderators/admins (e.g. "Delayed by an
-- hour", "Moved to the Gymkhana") alongside the existing discussion forum from rev 17, which stays
-- in the database but the app no longer shows on the event page.

BEGIN;

CREATE TABLE IF NOT EXISTS event_updates (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id   UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    author_id  UUID NOT NULL REFERENCES users(id),
    kind       TEXT NOT NULL DEFAULT 'info' CHECK (kind IN ('info', 'time', 'venue', 'time_venue')),
    message    TEXT NOT NULL CHECK (char_length(btrim(message)) BETWEEN 1 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES users(id),
    CONSTRAINT event_updates_deleted_pair_chk CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_event_updates_event ON event_updates(event_id, created_at DESC) WHERE deleted_at IS NULL;

COMMIT;
