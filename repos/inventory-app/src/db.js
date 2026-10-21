import pg from 'pg';

const MOVIE_COLUMNS = 'id, title, description, created_at';

export function createPool({ host, port, database, user, password }) {
  return new pg.Pool({
    host,
    port,
    database,
    user,
    password,
    max: 10,
    connectionTimeoutMillis: 3000, // shorter than the Docker healthcheck timeout so /health answers 503 in time
    idleTimeoutMillis: 30000,
  });
}

/**
 * Blocks until the database answers `SELECT 1`, retrying with a fixed delay.
 * Compose's depends_on only covers the very first start; this also covers restarts.
 */
export async function waitForDatabase(pool, { logger, attempts = 30, delayMs = 2000, sleep = defaultSleep } = {}) {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (err) {
      if (attempt === attempts) {
        throw new Error(`Database unreachable after ${attempts} attempts: ${err.message}`);
      }
      logger.warn('Database not ready, retrying', { attempt, attempts, delayMs, err });
      await sleep(delayMs);
    }
  }
}

/** Escapes LIKE/ILIKE wildcards so that user input is matched literally. */
export function escapeLikePattern(text) {
  return text.replace(/[\\%_]/g, '\\$&');
}

/** Data-access layer for the `movies` table. Parameterized queries only. */
export function createDb(pool) {
  return {
    async ping() {
      await pool.query('SELECT 1');
    },

    async listMovies(titleFilter) {
      const { rows } = titleFilter
        ? await pool.query(`SELECT ${MOVIE_COLUMNS} FROM movies WHERE title ILIKE $1 ORDER BY id`, [
            `%${escapeLikePattern(titleFilter)}%`,
          ])
        : await pool.query(`SELECT ${MOVIE_COLUMNS} FROM movies ORDER BY id`);
      return rows;
    },

    async getMovie(id) {
      const { rows } = await pool.query(`SELECT ${MOVIE_COLUMNS} FROM movies WHERE id = $1`, [id]);
      return rows[0] ?? null;
    },

    async createMovie({ title, description }) {
      const { rows } = await pool.query(
        `INSERT INTO movies (title, description) VALUES ($1, $2) RETURNING ${MOVIE_COLUMNS}`,
        [title, description],
      );
      return rows[0];
    },

    async updateMovie(id, { title, description }) {
      const { rows } = await pool.query(
        `UPDATE movies SET title = $2, description = $3 WHERE id = $1 RETURNING ${MOVIE_COLUMNS}`,
        [id, title, description],
      );
      return rows[0] ?? null;
    },

    async deleteMovie(id) {
      const { rowCount } = await pool.query('DELETE FROM movies WHERE id = $1', [id]);
      return rowCount > 0;
    },

    async deleteAllMovies() {
      const { rowCount } = await pool.query('DELETE FROM movies');
      return rowCount;
    },
  };
}

function defaultSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
