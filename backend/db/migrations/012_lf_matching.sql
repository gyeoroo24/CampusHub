-- Rev 12: Lost & Found matching by description and photo (future plan §1.2, app/matching).
-- Existing reports start pending (matched_rev NULL); match them once with
--   python -m app.matching --backfill
-- (or invoke the matcher Lambda with {"backfill": true}).
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/012_lf_matching.sql

BEGIN;
ALTER TABLE lost_reports  ADD COLUMN match_rev INT NOT NULL DEFAULT 1, ADD COLUMN matched_rev INT;
ALTER TABLE found_reports ADD COLUMN match_rev INT NOT NULL DEFAULT 1, ADD COLUMN matched_rev INT;

CREATE TABLE lf_embeddings (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lost_report_id  UUID REFERENCES lost_reports(id) ON DELETE CASCADE,
    found_report_id UUID REFERENCES found_reports(id) ON DELETE CASCADE,
    model           TEXT NOT NULL,
    s3_key          TEXT,
    source_hash     TEXT NOT NULL,
    vec             REAL[] NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT lf_embeddings_one_report_chk CHECK ((lost_report_id IS NULL) <> (found_report_id IS NULL))
);
CREATE UNIQUE INDEX uq_lf_embeddings ON lf_embeddings
    (COALESCE(lost_report_id, found_report_id), model, COALESCE(s3_key, ''));

CREATE TABLE lf_matches (
    lost_report_id  UUID NOT NULL REFERENCES lost_reports(id) ON DELETE CASCADE,
    found_report_id UUID NOT NULL REFERENCES found_reports(id) ON DELETE CASCADE,
    score           REAL NOT NULL CHECK (score BETWEEN 0 AND 1),
    text_sim        REAL,
    photo_sim       REAL,
    cross_sim       REAL,
    reasons         TEXT[] NOT NULL DEFAULT '{}',
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    notified_at     TIMESTAMPTZ,
    PRIMARY KEY (lost_report_id, found_report_id)
);
CREATE INDEX idx_lf_matches_found ON lf_matches(found_report_id);
COMMIT;
