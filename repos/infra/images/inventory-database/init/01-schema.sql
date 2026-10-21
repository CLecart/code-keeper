-- Schema of the inventory database.
-- Applied once by docker-entrypoint.sh, on the first start of the container;
-- every statement is idempotent so re-running the file is harmless.

CREATE TABLE IF NOT EXISTS movies (
    id          SERIAL       PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    description TEXT         NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Trigram index backing the case-insensitive substring search on the title
-- (GET /api/movies?title=... uses ILIKE '%...%', which a btree cannot serve).
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS movies_title_trgm_idx
    ON movies USING gin (title gin_trgm_ops);
