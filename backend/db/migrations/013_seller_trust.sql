-- Rev 13: Seller trust score (future plan §1.5) — moderator-confirmed listing removals accumulate
-- into a "Negative Seller" / "Blocked Seller" tag, never from raw report counts.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/013_seller_trust.sql

BEGIN;
CREATE TYPE seller_strike_severity AS ENUM ('severe', 'non_severe');

ALTER TABLE users
    ADD COLUMN listing_suspended_at     TIMESTAMPTZ,
    ADD COLUMN listing_suspended_reason TEXT;

CREATE TABLE seller_strikes (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id      UUID NOT NULL REFERENCES users(id),
    listing_id     UUID NOT NULL REFERENCES listings(id),
    report_id      UUID NOT NULL UNIQUE REFERENCES reports(id),
    severity       seller_strike_severity NOT NULL,
    moderator_id   UUID NOT NULL REFERENCES users(id),
    moderator_note TEXT,
    appeal_message    TEXT,
    appeal_created_at TIMESTAMPTZ,
    excluded          BOOLEAN NOT NULL DEFAULT FALSE,
    excluded_by       UUID REFERENCES users(id),
    excluded_at       TIMESTAMPTZ,
    excluded_note     TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_seller_strikes_seller ON seller_strikes(seller_id);
COMMIT;
