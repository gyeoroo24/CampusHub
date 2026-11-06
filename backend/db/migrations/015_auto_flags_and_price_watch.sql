-- Rev 15 (2 Nov 2026):
--   Future plan §1.6, automatic flagging: the system files reports itself (reports.source =
--   'system', no reporter), and can hold a listing back until a moderator looks at it
--   (listings.held_for_review_at, set when it looks like a prohibited item).
--   Future plan §2.3, price watch: listings.negotiable, listing_watches, and a new notification
--   type listing_watch (price change, or marked negotiable).
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/015_auto_flags_and_price_watch.sql

-- A new enum value can't be used in the transaction that adds it, so this goes first, on its own.
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'listing_watch';

BEGIN;
CREATE TYPE report_source AS ENUM ('user', 'system');
ALTER TABLE reports
    ALTER COLUMN reporter_id DROP NOT NULL,
    ADD COLUMN source report_source NOT NULL DEFAULT 'user',
    ADD CONSTRAINT reports_source_chk CHECK ((source = 'user') = (reporter_id IS NOT NULL));
-- At most one open automatic flag per item; a later check adds its reason to it.
CREATE UNIQUE INDEX uq_reports_one_open_system ON reports(target_type, target_id)
    WHERE status = 'open' AND source = 'system';

ALTER TABLE listings
    ADD COLUMN held_for_review_at TIMESTAMPTZ,
    ADD COLUMN negotiable BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX idx_listings_held ON listings(held_for_review_at) WHERE held_for_review_at IS NOT NULL;

CREATE TABLE listing_watches (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, listing_id)
);
CREATE INDEX idx_listing_watches_listing ON listing_watches(listing_id);
COMMIT;
