-- Rev 19: deleting a chat or a message for yourself only, and placement sheets with any email address.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/019_chat_hiding_and_any_email.sql

BEGIN;

-- "Delete chat": messages up to this seq stay hidden from that person; the other person keeps everything.
ALTER TABLE chat_conversations ADD COLUMN IF NOT EXISTS user_a_cleared_seq BIGINT NOT NULL DEFAULT 0;
ALTER TABLE chat_conversations ADD COLUMN IF NOT EXISTS user_b_cleared_seq BIGINT NOT NULL DEFAULT 0;

-- "Delete for me" on one message.
CREATE TABLE IF NOT EXISTS chat_message_hides (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, message_id)
);

-- Placement sheets may list students by any email (some give a personal one). They count towards
-- the hiring numbers; only IISc addresses are offered as seniors to contact.
ALTER TABLE placement_records ALTER COLUMN student_email TYPE citext;
ALTER TABLE placement_records DROP CONSTRAINT IF EXISTS placement_records_email_chk;
ALTER TABLE placement_records ADD CONSTRAINT placement_records_email_chk
    CHECK (student_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$');

COMMIT;
