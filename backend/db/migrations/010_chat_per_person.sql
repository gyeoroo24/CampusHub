-- Upgrade a rev 9 database to rev 10: one chat per pair of people, with topics.
-- A new database doesn't need this: schema.sql already has everything.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/010_chat_per_person.sql
--
-- Until rev 9 a conversation was one (listing, buyer) pair, so two people who discussed three
-- listings had three chats. Now a conversation is a pair of people, and what a message is about
-- (a listing, a lost or found report, or nothing) is its topic.
--
-- Existing chats between the same two people are merged into the oldest one, each becoming a
-- listing topic. Messages are renumbered by when they were sent. Their ciphertext was bound to the
-- old conversation id, so that id is kept as crypto_context_id and the app keeps decrypting them.
-- Notifications that link to a merged chat are pointed at the one it was merged into.

BEGIN;

CREATE TYPE chat_topic_kind AS ENUM ('listing', 'lost_report', 'found_report');

-- ---------------------------------------------------------------- conversations become pairs
ALTER TABLE chat_conversations
    ADD COLUMN user_a              UUID REFERENCES users(id),
    ADD COLUMN user_b              UUID REFERENCES users(id),
    ADD COLUMN user_a_last_read_seq BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN user_b_last_read_seq BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN created_by          UUID REFERENCES users(id);

UPDATE chat_conversations
SET user_a = LEAST(buyer_id, seller_id), user_b = GREATEST(buyer_id, seller_id), created_by = buyer_id;

CREATE TEMP TABLE conv_map ON COMMIT DROP AS
SELECT c.id AS old_id,
       first_value(c.id) OVER (PARTITION BY c.user_a, c.user_b ORDER BY c.created_at, c.id) AS new_id,
       c.listing_id, c.buyer_id, c.seller_id, c.buyer_last_read_seq, c.seller_last_read_seq, c.created_at
FROM chat_conversations c;

-- ----------------------------------------------------------------------------------- topics
CREATE TABLE chat_topics (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    kind            chat_topic_kind NOT NULL,
    listing_id      UUID REFERENCES listings(id),
    lost_report_id  UUID REFERENCES lost_reports(id),
    found_report_id UUID REFERENCES found_reports(id),
    started_by      UUID NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chat_topic_one_ref CHECK (
        (kind = 'listing')      = (listing_id IS NOT NULL) AND
        (kind = 'lost_report')  = (lost_report_id IS NOT NULL) AND
        (kind = 'found_report') = (found_report_id IS NOT NULL)),
    UNIQUE (conversation_id, listing_id),
    UNIQUE (conversation_id, lost_report_id),
    UNIQUE (conversation_id, found_report_id)
);

INSERT INTO chat_topics (conversation_id, kind, listing_id, started_by, created_at)
SELECT new_id, 'listing', listing_id, buyer_id, created_at FROM conv_map;

-- --------------------------------------------------------------------------------- messages
ALTER TABLE chat_messages
    ADD COLUMN topic_id          UUID REFERENCES chat_topics(id),
    ADD COLUMN crypto_context_id UUID;

UPDATE chat_messages m SET crypto_context_id = m.conversation_id;

ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_conversation_id_seq_key;
DROP INDEX uq_chat_one_pending_offer;

-- Was each message read by the other person (per the old read markers)? Needed for the new ones.
CREATE TEMP TABLE msg_map ON COMMIT DROP AS
SELECT m.id, cm.new_id,
       row_number() OVER (PARTITION BY cm.new_id ORDER BY m.sent_at, m.seq, m.id) AS new_seq,
       t.id AS topic_id,
       (m.seq <= cm.buyer_last_read_seq)  AS read_by_buyer,
       (m.seq <= cm.seller_last_read_seq) AS read_by_seller,
       cm.buyer_id, cm.seller_id
FROM chat_messages m
JOIN conv_map cm ON cm.old_id = m.conversation_id
JOIN chat_topics t ON t.conversation_id = cm.new_id AND t.listing_id = cm.listing_id;

UPDATE chat_messages m
SET conversation_id = mm.new_id, seq = mm.new_seq, changed_seq = mm.new_seq, topic_id = mm.topic_id
FROM msg_map mm WHERE mm.id = m.id;

UPDATE chat_conversations c
SET last_seq = coalesce((SELECT max(new_seq) FROM msg_map mm WHERE mm.new_id = c.id), 0),
    last_message_at = (SELECT max(m.sent_at) FROM chat_messages m WHERE m.conversation_id = c.id),
    created_at = (SELECT min(cm.created_at) FROM conv_map cm WHERE cm.new_id = c.id),
    -- Read up to the newest message they had read, in any of the merged chats.
    user_a_last_read_seq = coalesce((SELECT max(mm.new_seq) FROM msg_map mm WHERE mm.new_id = c.id AND (
        (mm.buyer_id = c.user_a AND mm.read_by_buyer) OR (mm.seller_id = c.user_a AND mm.read_by_seller))), 0),
    user_b_last_read_seq = coalesce((SELECT max(mm.new_seq) FROM msg_map mm WHERE mm.new_id = c.id AND (
        (mm.buyer_id = c.user_b AND mm.read_by_buyer) OR (mm.seller_id = c.user_b AND mm.read_by_seller))), 0)
WHERE c.id IN (SELECT new_id FROM conv_map);

UPDATE notifications n
SET payload = jsonb_set(n.payload, '{conversation_id}', to_jsonb(cm.new_id::text))
FROM conv_map cm
WHERE n.payload ? 'conversation_id' AND n.payload->>'conversation_id' = cm.old_id::text AND cm.old_id <> cm.new_id;

DELETE FROM chat_conversations WHERE id IN (SELECT old_id FROM conv_map WHERE old_id <> new_id);

ALTER TABLE chat_messages
    ALTER COLUMN crypto_context_id SET NOT NULL,
    ADD CONSTRAINT chat_messages_conversation_id_seq_key UNIQUE (conversation_id, seq),
    ADD CONSTRAINT chat_offer_has_topic CHECK (kind <> 'offer' OR topic_id IS NOT NULL);
CREATE UNIQUE INDEX uq_chat_one_pending_offer ON chat_messages(topic_id) WHERE offer_status = 'pending';
CREATE INDEX idx_chat_messages_topic ON chat_messages(topic_id, seq);

-- ------------------------------------------------------------------------ drop the old shape
DROP INDEX idx_chat_conv_buyer;
DROP INDEX idx_chat_conv_seller;
ALTER TABLE chat_conversations
    DROP COLUMN listing_id,
    DROP COLUMN buyer_id,
    DROP COLUMN seller_id,
    DROP COLUMN buyer_last_read_seq,
    DROP COLUMN seller_last_read_seq,
    ALTER COLUMN user_a SET NOT NULL,
    ALTER COLUMN user_b SET NOT NULL,
    ALTER COLUMN created_by SET NOT NULL,
    ADD CONSTRAINT chat_pair_ordered CHECK (user_a < user_b),
    ADD CONSTRAINT chat_pair_unique UNIQUE (user_a, user_b);
CREATE INDEX idx_chat_conv_user_b ON chat_conversations(user_b, last_message_at DESC NULLS LAST);

COMMIT;
