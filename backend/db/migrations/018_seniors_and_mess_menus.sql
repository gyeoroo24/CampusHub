-- Rev 18: senior contacts on company pages, monthly mess menus with meal alerts, and forum posts no
-- longer starting with their author's own upvote.
-- A new database doesn't need this: schema.sql already has everything. Safe to run twice.
--
--   docker exec -i campushub-db-1 psql -v ON_ERROR_STOP=1 -U campushub -d campushub \
--       < db/migrations/018_seniors_and_mess_menus.sql

-- New enum values must be committed before they can be used, so this runs outside the transaction.
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'mess_menu';

BEGIN;

-- Posts used to start upvoted by their author (rev 17). They start at 0 now, so take those votes back.
DELETE FROM thread_votes v USING threads t WHERE v.thread_id = t.id AND v.user_id = t.author_id;
DELETE FROM comment_votes v USING comments c WHERE v.comment_id = c.id AND v.user_id = c.user_id;

-- Seniors to contact about a company: the placement sheet's students, plus people moderators add.
ALTER TABLE placement_records ADD COLUMN IF NOT EXISTS contact_hidden BOOLEAN NOT NULL DEFAULT FALSE;
CREATE TABLE IF NOT EXISTS company_seniors (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id     UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name           TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
    email          TEXT NOT NULL CHECK (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    phone          TEXT CHECK (phone ~ '^\+?[0-9]{10,15}$'),
    role_title     TEXT CHECK (char_length(role_title) <= 200),
    placement_year SMALLINT NOT NULL CHECK (placement_year BETWEEN 2000 AND 2100),
    offer_type     TEXT NOT NULL DEFAULT 'off_campus'
                   CHECK (offer_type IN ('on_campus', 'off_campus', 'ppo', 'internship')),
    note           TEXT CHECK (char_length(note) <= 500),
    added_by       UUID NOT NULL REFERENCES users(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, email, placement_year)
);

-- Mess menus.
CREATE TABLE IF NOT EXISTS messes (
    id           SERIAL PRIMARY KEY,
    name         TEXT UNIQUE NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 60),
    breakfast_at TIME NOT NULL DEFAULT '07:30',
    lunch_at     TIME NOT NULL DEFAULT '12:30',
    snacks_at    TIME NOT NULL DEFAULT '16:45',
    dinner_at    TIME NOT NULL DEFAULT '19:30',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS mess_menus (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mess_id     INT NOT NULL REFERENCES messes(id) ON DELETE CASCADE,
    valid_from  DATE NOT NULL,
    valid_to    DATE NOT NULL,
    file_s3_key TEXT,
    notes       TEXT CHECK (char_length(notes) <= 2000),
    created_by  UUID NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (valid_to >= valid_from AND valid_to - valid_from <= 92)
);
CREATE INDEX IF NOT EXISTS idx_mess_menus_mess ON mess_menus(mess_id, valid_from);
CREATE TABLE IF NOT EXISTS mess_menu_items (
    menu_id UUID NOT NULL REFERENCES mess_menus(id) ON DELETE CASCADE,
    weekday SMALLINT NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    meal    TEXT NOT NULL CHECK (meal IN ('breakfast', 'lunch', 'snacks', 'dinner')),
    items   TEXT NOT NULL CHECK (char_length(btrim(items)) BETWEEN 1 AND 1000),
    PRIMARY KEY (menu_id, weekday, meal)
);
CREATE TABLE IF NOT EXISTS mess_follows (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mess_id    INT NOT NULL REFERENCES messes(id) ON DELETE CASCADE,
    meals      TEXT[] NOT NULL CHECK (cardinality(meals) >= 1
                   AND meals <@ ARRAY['breakfast', 'lunch', 'snacks', 'dinner']),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, mess_id)
);
CREATE INDEX IF NOT EXISTS idx_mess_follows_mess ON mess_follows(mess_id);
CREATE TABLE IF NOT EXISTS mess_alerts_sent (
    mess_id    INT NOT NULL REFERENCES messes(id) ON DELETE CASCADE,
    day        DATE NOT NULL,
    meal       TEXT NOT NULL,
    recipients INT NOT NULL,
    sent_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (mess_id, day, meal)
);

COMMIT;
