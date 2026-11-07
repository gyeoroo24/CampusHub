-- One-off cleanup after the 2026-11 audit fixes (DI-02, DI-03). No schema change; safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/027_audit_cleanup.sql
--
-- 1. bookmarks.target_id has no foreign key (it can be a listing or an event), so deleting a listing left
--    its bookmark rows behind. The API now deletes them with the listing; this removes the old ones.
-- 2. Removing a Lost & Found report (deleted_at) kept its photo rows. The API now deletes them and their
--    files; this removes the old rows. Their files in S3 are listed first so they can be deleted too:
--      SELECT s3_key FROM lost_report_photos p JOIN lost_reports r ON r.id = p.lost_report_id
--       WHERE r.deleted_at IS NOT NULL
--      UNION ALL
--      SELECT s3_key FROM found_report_photos p JOIN found_reports r ON r.id = p.found_report_id
--       WHERE r.deleted_at IS NOT NULL;

BEGIN;

DELETE FROM bookmarks b
 WHERE b.target_type = 'listing' AND NOT EXISTS (SELECT 1 FROM listings l WHERE l.id = b.target_id);

DELETE FROM lost_report_photos p USING lost_reports r
 WHERE r.id = p.lost_report_id AND r.deleted_at IS NOT NULL;
DELETE FROM found_report_photos p USING found_reports r
 WHERE r.id = p.found_report_id AND r.deleted_at IS NOT NULL;

COMMIT;
