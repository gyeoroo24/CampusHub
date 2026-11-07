-- Upgrade a rev 8 database to rev 9: messaging keys can be held by the server (no passphrase).
-- A new database doesn't need this: schema.sql already has everything.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/009_server_held_chat_keys.sql
--
-- backup_kdf = 'none' means key_backup is the plain 32-byte private key, so the server can read
-- messages. Existing passphrase backups ('pbkdf2-sha256') stay valid; the app moves each one to
-- 'none' the next time it is unlocked. True end-to-end encryption is a planned improvement.

BEGIN;

ALTER TABLE chat_keys
    DROP CONSTRAINT chat_keys_key_backup_check,
    DROP CONSTRAINT chat_keys_backup_salt_check,
    DROP CONSTRAINT chat_keys_backup_kdf_check,
    DROP CONSTRAINT chat_keys_backup_iterations_check,
    ALTER COLUMN backup_salt DROP NOT NULL,
    ALTER COLUMN backup_iterations DROP NOT NULL,
    ADD CONSTRAINT chat_keys_backup_check CHECK (
        (backup_kdf = 'pbkdf2-sha256'
            AND octet_length(key_backup) BETWEEN 44 AND 512
            AND octet_length(backup_salt) BETWEEN 16 AND 64
            AND backup_iterations BETWEEN 100000 AND 10000000)
        OR (backup_kdf = 'none'
            AND octet_length(key_backup) = 32
            AND backup_salt IS NULL
            AND backup_iterations IS NULL));

COMMIT;
