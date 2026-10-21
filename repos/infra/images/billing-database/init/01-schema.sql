-- Schema of the billing database.
-- Applied once by docker-entrypoint.sh, on the first start of the container;
-- every statement is idempotent so re-running the file is harmless.

CREATE TABLE IF NOT EXISTS orders (
    id              SERIAL        PRIMARY KEY,
    user_id         INTEGER       NOT NULL,
    number_of_items INTEGER       NOT NULL CHECK (number_of_items >= 0),
    total_amount    NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Orders are looked up per customer.
CREATE INDEX IF NOT EXISTS orders_user_id_idx ON orders (user_id);
