import { setTimeout as sleep } from 'node:timers/promises';
import pg from 'pg';

const { Pool } = pg;

// total_amount is NUMERIC in PostgreSQL, which pg returns as a string.
const ORDER_COLUMNS = 'id, user_id, number_of_items, total_amount::float8 AS total_amount, created_at';

// Wraps a pg Pool behind the small interface the rest of the app depends on.
export function createDatabase(config, logger) {
  const pool = new Pool({ ...config, max: 5, connectionTimeoutMillis: 3000 });
  // An idle client can be dropped by the server (restart, network cut); without
  // a listener pg would raise it as an uncaught error and kill the process.
  pool.on('error', (err) => logger.warn('database pool error', { err }));

  return {
    async waitForDatabase({ attempts = 30, delayMs = 2000 } = {}) {
      for (let attempt = 1; attempt <= attempts; attempt += 1) {
        try {
          await pool.query('SELECT 1');
          return;
        } catch (err) {
          if (attempt === attempts) {
            throw new Error(`Database unreachable after ${attempts} attempts: ${err.message}`);
          }
          logger.warn('database not ready, retrying', { attempt, attempts, delayMs, err });
          await sleep(delayMs);
        }
      }
    },

    async ping() {
      try {
        await pool.query('SELECT 1');
        return true;
      } catch {
        return false;
      }
    },

    async insertOrder({ userId, numberOfItems, totalAmount }) {
      const { rows } = await pool.query(
        `INSERT INTO orders (user_id, number_of_items, total_amount)
         VALUES ($1, $2, $3)
         RETURNING ${ORDER_COLUMNS}`,
        [userId, numberOfItems, totalAmount],
      );
      return rows[0];
    },

    async listOrders() {
      const { rows } = await pool.query(`SELECT ${ORDER_COLUMNS} FROM orders ORDER BY id`);
      return rows;
    },

    close: () => pool.end(),
  };
}
