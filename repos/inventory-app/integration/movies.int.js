// Integration tests: the real application (src/index.js in a child process,
// configured through its environment like in the image) tested over HTTP
// against a real PostgreSQL 17.
//
// In CI (job integration-test), PostgreSQL is the "postgres" service of the
// job and POSTGRES_PASSWORD its throwaway password. For a local run, point the
// tests at another server with TEST_POSTGRES_HOST and TEST_POSTGRES_PORT.
//
// Each run works in a database of its own, created from schema.sql and dropped
// at the end, so nothing is left on the server.
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { createInterface } from 'node:readline';
import { setTimeout as sleep } from 'node:timers/promises';
import pg from 'pg';

const postgres = {
  host: process.env.TEST_POSTGRES_HOST || 'postgres',
  port: Number(process.env.TEST_POSTGRES_PORT || 5432),
  user: 'postgres', // superuser of the official image: the job sets no POSTGRES_USER
  password: process.env.POSTGRES_PASSWORD,
};
// Unique per run, so that two runs never share a database.
const database = `inventory_it_${randomBytes(4).toString('hex')}`;
// The service container may still be initializing when the job starts.
const WAIT_FOR_POSTGRES_MS = 60_000;

let admin; // pool on the "postgres" database: creates and drops the test database
let db; // pool on the test database: schema, and checks of what the API stored
let databaseCreated = false;
let app; // { child, logs, listening }
let baseUrl;

before(
  async () => {
    assert.ok(postgres.password, 'POSTGRES_PASSWORD must hold the password of the postgres user');
    admin = new pg.Pool({ ...postgres, database: 'postgres', connectionTimeoutMillis: 2000 });
    await waitForPostgres(admin);

    await admin.query(`CREATE DATABASE "${database}"`);
    databaseCreated = true;
    db = new pg.Pool({ ...postgres, database });
    await db.query(await readFile(new URL('schema.sql', import.meta.url), 'utf8'));

    const port = await freePort();
    app = startApp({
      NODE_ENV: 'production', // as in the image (Dockerfile)
      PORT: String(port),
      DB_HOST: postgres.host,
      DB_PORT: String(postgres.port),
      DB_NAME: database,
      DB_USER: postgres.user,
      DB_PASSWORD: postgres.password,
    });
    await app.listening;
    baseUrl = `http://127.0.0.1:${port}`;
  },
  { timeout: 2 * WAIT_FOR_POSTGRES_MS },
);

after(async () => {
  if (app?.child.exitCode === null && app.child.signalCode === null) {
    const closed = once(app.child, 'close');
    app.child.kill('SIGKILL');
    await closed;
  }
  await db?.end();
  if (databaseCreated) {
    await admin.query(`DROP DATABASE "${database}" WITH (FORCE)`);
  }
  await admin?.end();
});

describe('GET /health', () => {
  it('reports the database as up', async () => {
    assert.deepEqual(await request('GET', '/health'), { status: 200, body: { status: 'ok', database: 'up' } });
  });
});

describe('movies CRUD against PostgreSQL', () => {
  beforeEach(async () => {
    await db.query('TRUNCATE movies RESTART IDENTITY');
  });

  it('POST creates a movie (201) and stores it in the movies table', async () => {
    const res = await request('POST', '/api/movies', { title: 'Alien', description: 'In space...' });
    assert.equal(res.status, 201);
    const { id, title, description, created_at: createdAt } = res.body;
    assert.deepEqual({ id, title, description }, { id: 1, title: 'Alien', description: 'In space...' });

    // The row in PostgreSQL is exactly what the API answered.
    const { rows } = await db.query('SELECT id, title, description, created_at FROM movies');
    assert.deepEqual(rows, [{ id, title, description, created_at: new Date(createdAt) }]);
  });

  it('GET lists the movies by id and filters them by title, wildcards matched literally', async () => {
    const titles = ['Alien', 'Blade Runner', 'Aliens', '100% Wolf', '1000 Ways to Die'];
    // One after the other: the ids, hence the order of the list, follow this array.
    for (const title of titles) {
      assert.equal((await request('POST', '/api/movies', { title })).status, 201);
    }
    assert.deepEqual(await listTitles(''), titles);
    assert.deepEqual(await listTitles('?title=aLIEN'), ['Alien', 'Aliens']);
    // "100%" must not match "1000 Ways to Die": the ILIKE pattern is escaped.
    assert.deepEqual(await listTitles('?title=100%25'), ['100% Wolf']);
  });

  it('GET /:id returns the stored movie', async () => {
    const created = await createMovie({ title: 'Alien', description: 'In space...' });
    assert.deepEqual(await request('GET', `/api/movies/${created.id}`), { status: 200, body: created });
  });

  it('PUT /:id updates the stored movie and keeps its id and creation date', async () => {
    const created = await createMovie({ title: 'Alien', description: 'v1' });
    const expected = { ...created, title: "Alien (Director's Cut)", description: 'v2' };

    const res = await request('PUT', `/api/movies/${created.id}`, { title: "Alien (Director's Cut)", description: 'v2' });
    assert.deepEqual(res, { status: 200, body: expected });
    assert.deepEqual(await request('GET', `/api/movies/${created.id}`), { status: 200, body: expected });
  });

  it('DELETE /:id removes the movie from the movies table', async () => {
    const created = await createMovie({ title: 'Alien' });
    const kept = await createMovie({ title: 'Aliens' });

    assert.deepEqual(await request('DELETE', `/api/movies/${created.id}`), {
      status: 200,
      body: { message: 'Movie deleted', id: created.id },
    });
    const { rows } = await db.query('SELECT id FROM movies ORDER BY id');
    assert.deepEqual(rows, [{ id: kept.id }]);
  });

  it('answers 404 for a movie that does not exist', async () => {
    const created = await createMovie({ title: 'Alien' });
    const missing = `/api/movies/${created.id + 1}`;
    const notFound = { status: 404, body: { error: 'Movie not found' } };

    assert.deepEqual(await request('GET', missing), notFound);
    assert.deepEqual(await request('PUT', missing, { title: 'x' }), notFound);
    assert.deepEqual(await request('DELETE', missing), notFound);
  });

  it('DELETE / removes every movie and reports the count', async () => {
    await createMovie({ title: 'Alien' });
    await createMovie({ title: 'Aliens' });

    assert.deepEqual(await request('DELETE', '/api/movies'), {
      status: 200,
      body: { message: 'All movies deleted', deleted: 2 },
    });
    assert.deepEqual((await db.query('SELECT count(*)::int AS count FROM movies')).rows, [{ count: 0 }]);
  });
});

// Last on purpose: stops the application. A rolling update sends SIGTERM to
// the old pods, which must drain and close their database pool, then exit 0.
describe('shutdown', () => {
  it('exits with code 0 on SIGTERM after closing the database pool', async () => {
    const closed = once(app.child, 'close');
    app.child.kill('SIGTERM');
    const [code, signal] = await closed;

    assert.deepEqual({ code, signal }, { code: 0, signal: null });
    assert.ok(app.logs.some((entry) => entry.msg === 'Shutdown complete'));
  });
});

/** Retries until PostgreSQL accepts connections, for at most WAIT_FOR_POSTGRES_MS. */
async function waitForPostgres(pool) {
  const deadline = Date.now() + WAIT_FOR_POSTGRES_MS;
  for (;;) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (err) {
      if (Date.now() >= deadline) {
        throw new Error(`PostgreSQL unreachable at ${postgres.host}:${postgres.port}: ${err.message}`, { cause: err });
      }
      await sleep(1000);
    }
  }
}

/** A free local port: the application refuses PORT=0, so it cannot pick one itself. */
async function freePort() {
  const probe = createServer().listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const { port } = probe.address();
  probe.close();
  await once(probe, 'close');
  return port;
}

/**
 * Starts the entry point of the image with only the given environment, and
 * collects its JSON log lines (src/logger.js); `listening` resolves once the
 * HTTP server is up and rejects if the process ends first.
 */
function startApp(env) {
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: new URL('..', import.meta.url),
    env,
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const logs = [];
  const listening = new Promise((resolve, reject) => {
    createInterface({ input: child.stdout }).on('line', (line) => {
      const entry = JSON.parse(line);
      logs.push(entry);
      if (entry.msg === 'HTTP server listening') {
        resolve();
      }
    });
    child.once('error', reject);
    child.once('close', (code) => {
      reject(new Error(`inventory-app exited with code ${code} before listening: ${JSON.stringify(logs.at(-1))}`));
    });
  });
  return { child, logs, listening };
}

/** Sends a JSON request to the application; returns the status and the parsed body. */
async function request(method, path, body) {
  const res = await fetch(baseUrl + path, {
    method,
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function createMovie(movie) {
  const res = await request('POST', '/api/movies', movie);
  assert.equal(res.status, 201);
  return res.body;
}

async function listTitles(query) {
  const res = await request('GET', `/api/movies${query}`);
  assert.equal(res.status, 200);
  return res.body.map((movie) => movie.title);
}
