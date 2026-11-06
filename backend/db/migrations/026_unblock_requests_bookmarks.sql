-- Upgrade an existing rev 25 database to rev 26. A new database doesn't need this: schema.sql already has
-- everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/026_unblock_requests_bookmarks.sql
--
-- 1. seller_unblock_requests: a blocked seller asks the Buy & Sell moderators to unblock them. Approving one
--    (or a moderator unblocking them directly) resets their strikes and lifts the posting suspension.
-- 2. listing_bookmarks: signed-in people bookmark Buy & Sell listings (guests keep theirs on the device).
-- 3. lost_reports / found_reports.category_id may be NULL: deleting a category together with its posts
--    removes the posts (deleted_at), and the removed rows keep no category.

BEGIN;

CREATE TABLE IF NOT EXISTS seller_unblock_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message         TEXT NOT NULL CHECK (char_length(btrim(message)) BETWEEN 1 AND 1000),
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    resolved_by     UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at     TIMESTAMPTZ,
    resolution_note TEXT CHECK (char_length(resolution_note) <= 1000),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_unblock_requests_one_pending ON seller_unblock_requests(seller_id)
    WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS listing_bookmarks (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, listing_id)
);
CREATE INDEX IF NOT EXISTS idx_listing_bookmarks_listing ON listing_bookmarks(listing_id);

ALTER TABLE lost_reports ALTER COLUMN category_id DROP NOT NULL;
ALTER TABLE found_reports ALTER COLUMN category_id DROP NOT NULL;

COMMIT;
