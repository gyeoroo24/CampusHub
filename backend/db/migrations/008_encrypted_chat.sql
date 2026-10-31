-- Upgrade a rev 7 database to rev 8: end-to-end encrypted buyer–seller messaging.
-- A new database doesn't need this: schema.sql already has everything.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/008_encrypted_chat.sql
--
-- The rev 1 placeholder table chat_messages (sender, receiver, plaintext content) was never
-- used by the API; only scripts/seed_dummy_data.py wrote dummy rows into it. It is dropped here,
-- because keeping plaintext messages around would defeat the point of encrypting the new ones.
--
-- The new enum value has to be committed before it can be used, so it is added first, outside
-- the transaction below.

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'chat_message';

BEGIN;

DROP TABLE chat_messages;

CREATE TYPE chat_message_kind AS ENUM ('text', 'offer');
CREATE TYPE chat_offer_status AS ENUM ('pending', 'accepted', 'declined', 'withdrawn', 'superseded');

CREATE TABLE chat_keys (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    public_key        BYTEA NOT NULL CHECK (octet_length(public_key) = 32),   -- X25519
    key_backup        BYTEA NOT NULL CHECK (octet_length(key_backup) BETWEEN 44 AND 512),
    backup_salt       BYTEA NOT NULL CHECK (octet_length(backup_salt) BETWEEN 16 AND 64),
    backup_kdf        TEXT NOT NULL CHECK (backup_kdf = 'pbkdf2-sha256'),
    backup_iterations INT NOT NULL CHECK (backup_iterations BETWEEN 100000 AND 10000000),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    retired_at        TIMESTAMPTZ                                             -- replaced by a newer key
);
CREATE UNIQUE INDEX uq_chat_key_active ON chat_keys(user_id) WHERE retired_at IS NULL;

CREATE TABLE chat_conversations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id          UUID NOT NULL REFERENCES listings(id),
    buyer_id            UUID NOT NULL REFERENCES users(id),
    seller_id           UUID NOT NULL REFERENCES users(id),
    last_seq            BIGINT NOT NULL DEFAULT 0,
    buyer_last_read_seq BIGINT NOT NULL DEFAULT 0,
    seller_last_read_seq BIGINT NOT NULL DEFAULT 0,
    last_message_at     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chat_not_with_self CHECK (buyer_id <> seller_id),
    UNIQUE (listing_id, buyer_id)
);
CREATE INDEX idx_chat_conv_buyer  ON chat_conversations(buyer_id, last_message_at DESC NULLS LAST);
CREATE INDEX idx_chat_conv_seller ON chat_conversations(seller_id, last_message_at DESC NULLS LAST);

-- id is chosen by the sender's app: it is part of what the ciphertext is bound to, and
-- resending after a network error can't create a duplicate.
CREATE TABLE chat_messages (
    id               UUID PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    seq              BIGINT NOT NULL,                  -- order within the conversation
    changed_seq      BIGINT NOT NULL,                  -- last change (sent, offer answered, unsent)
    sender_id        UUID NOT NULL REFERENCES users(id),
    kind             chat_message_kind NOT NULL DEFAULT 'text',
    sender_key_id    UUID NOT NULL REFERENCES chat_keys(id),
    recipient_key_id UUID NOT NULL REFERENCES chat_keys(id),
    nonce            BYTEA CHECK (octet_length(nonce) = 12),
    ciphertext       BYTEA CHECK (octet_length(ciphertext) BETWEEN 17 AND 16400),   -- includes the 16-byte tag
    offer_status     chat_offer_status,
    offer_answered_at TIMESTAMPTZ,
    sent_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,                      -- unsent: the ciphertext is erased
    CONSTRAINT chat_offer_has_status CHECK ((kind = 'offer') = (offer_status IS NOT NULL)),
    CONSTRAINT chat_content_until_unsent CHECK
        ((deleted_at IS NULL) = (nonce IS NOT NULL AND ciphertext IS NOT NULL)),
    UNIQUE (conversation_id, seq)
);
CREATE INDEX idx_chat_messages_changes ON chat_messages(conversation_id, changed_seq);
CREATE INDEX idx_chat_messages_sender  ON chat_messages(sender_id, sent_at DESC);         -- send rate limit
CREATE UNIQUE INDEX uq_chat_one_pending_offer ON chat_messages(conversation_id) WHERE offer_status = 'pending';

CREATE TABLE chat_blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT chat_block_not_self CHECK (blocker_id <> blocked_id)
);
CREATE INDEX idx_chat_blocks_blocked ON chat_blocks(blocked_id);

CREATE TRIGGER trg_chat_keys_updated_at BEFORE UPDATE ON chat_keys FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
