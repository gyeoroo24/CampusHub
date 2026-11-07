-- Rev 14: a report-driven listing removal now hides the listing instead of
-- soft-deleting it, and a moderator can reject an appeal (not just overturn it).
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/014_reversible_listing_hide.sql

BEGIN;
ALTER TABLE seller_strikes
    ADD COLUMN appeal_resolved_at TIMESTAMPTZ,
    ADD COLUMN appeal_resolved_by UUID REFERENCES users(id);

CREATE INDEX idx_seller_strikes_pending_appeal ON seller_strikes(appeal_created_at)
    WHERE appeal_message IS NOT NULL AND appeal_resolved_at IS NULL;

ALTER TABLE listings ADD COLUMN hidden_by_strike_id UUID REFERENCES seller_strikes(id);
CREATE INDEX idx_listings_hidden ON listings(hidden_by_strike_id) WHERE hidden_by_strike_id IS NOT NULL;
COMMIT;
