-- Revision 23: deleting a Buy & Sell listing or Wanted post removes it from the database.
-- Until now DELETE /listings/{id} and DELETE /wanted/{id} only set deleted_at, so a deleted post (and the
-- reports about it) stayed in the database and in the moderators' history. Now the row goes, and with it
-- its photos, watches and reports (ON DELETE CASCADE). Two things outlive it, with a copy of its title:
--   - seller strikes (the seller's record; the listing and the report it came from are gone)
--   - chat topics (the conversation stays; the topic shows the listing as removed)
-- Idempotent.
BEGIN;

ALTER TABLE seller_strikes ADD COLUMN IF NOT EXISTS listing_title TEXT;
UPDATE seller_strikes s SET listing_title = l.title FROM listings l
 WHERE l.id = s.listing_id AND s.listing_title IS NULL;
ALTER TABLE seller_strikes ALTER COLUMN listing_id DROP NOT NULL;
ALTER TABLE seller_strikes ALTER COLUMN report_id DROP NOT NULL;
ALTER TABLE seller_strikes DROP CONSTRAINT IF EXISTS seller_strikes_listing_id_fkey;
ALTER TABLE seller_strikes ADD CONSTRAINT seller_strikes_listing_id_fkey
    FOREIGN KEY (listing_id) REFERENCES listings(id) ON DELETE SET NULL;
ALTER TABLE seller_strikes DROP CONSTRAINT IF EXISTS seller_strikes_report_id_fkey;
ALTER TABLE seller_strikes ADD CONSTRAINT seller_strikes_report_id_fkey
    FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE SET NULL;

-- A chat about a listing keeps the listing's id (no foreign key) plus its title and seller.
ALTER TABLE chat_topics ADD COLUMN IF NOT EXISTS listing_title TEXT;
ALTER TABLE chat_topics ADD COLUMN IF NOT EXISTS listing_seller_id UUID REFERENCES users(id);
UPDATE chat_topics t SET listing_title = l.title, listing_seller_id = l.seller_id FROM listings l
 WHERE l.id = t.listing_id AND t.listing_title IS NULL;
ALTER TABLE chat_topics DROP CONSTRAINT IF EXISTS chat_topics_listing_id_fkey;

-- Posts deleted before this revision go now.
DELETE FROM listings WHERE deleted_at IS NOT NULL;
DELETE FROM wanted_posts WHERE deleted_at IS NOT NULL;

COMMENT ON COLUMN listings.deleted_at IS 'Unused since revision 23: deleting a listing removes the row.';
COMMENT ON COLUMN wanted_posts.deleted_at IS 'Unused since revision 23: deleting a Wanted post removes the row.';

COMMIT;
