import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/logger.js';

/** In-memory stand-in for src/db.js exposing the same interface. */
function createFakeDb() {
  const movies = new Map();
  let nextId = 1;
  const db = {
    failing: false, // when true every call throws, to exercise the 500/503 paths
    reset() {
      movies.clear();
      nextId = 1;
      db.failing = false;
    },
    async ping() {
      guard();
    },
    async listMovies(title) {
      guard();
      const all = [...movies.values()];
      return title ? all.filter((m) => m.title.toLowerCase().includes(title.toLowerCase())) : all;
    },
    async getMovie(id) {
      guard();
      return movies.get(id) ?? null;
    },
    async createMovie({ title, description }) {
      guard();
      const movie = { id: nextId, title, description, created_at: '2026-01-01T00:00:00.000Z' };
      nextId += 1;
      movies.set(movie.id, movie);
      return movie;
    },
    async updateMovie(id, { title, description }) {
      guard();
      if (!movies.has(id)) {
        return null;
      }
      const movie = { ...movies.get(id), title, description };
      movies.set(id, movie);
      return movie;
    },
    async deleteMovie(id) {
      guard();
      return movies.delete(id);
    },
    async deleteAllMovies() {
      guard();
      const count = movies.size;
      movies.clear();
      return count;
    },
  };
  function guard() {
    if (db.failing) {
      throw new Error('database exploded');
    }
  }
  return db;
}

const db = createFakeDb();
const logLines = [];
let server;
let baseUrl;

/** Sends a request; `body` is sent verbatim when it is a string, JSON-encoded otherwise. */
async function request(method, path, body) {
  const res = await fetch(baseUrl + path, {
    method,
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
    body: body === undefined || typeof body === 'string' ? body : JSON.stringify(body),
  });
  return { status: res.status, headers: res.headers, body: await res.json() };
}

before(async () => {
  const logger = createLogger({ service: 'test', stream: { write: (line) => logLines.push(JSON.parse(line)) } });
  const app = createApp({ db, logger });
  server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
});

beforeEach(() => {
  db.reset();
  logLines.length = 0;
});

describe('GET /health', () => {
  it('reports the database as up', async () => {
    const res = await request('GET', '/health');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { status: 'ok', database: 'up' });
    assert.equal(res.headers.get('x-powered-by'), null);
  });

  it('answers 503 when the database is unreachable', async () => {
    db.failing = true;
    const res = await request('GET', '/health');
    assert.equal(res.status, 503);
    assert.deepEqual(res.body, { status: 'error', database: 'down' });
  });
});

describe('POST /api/movies', () => {
  it('creates a movie and answers 201 with the created object', async () => {
    const res = await request('POST', '/api/movies', { title: 'Alien', description: 'In space...' });
    assert.equal(res.status, 201);
    assert.deepEqual(res.body, { id: 1, title: 'Alien', description: 'In space...', created_at: '2026-01-01T00:00:00.000Z' });
  });

  it('rejects an invalid body with 400', async () => {
    const res = await request('POST', '/api/movies', { description: 'no title' });
    assert.equal(res.status, 400);
    assert.deepEqual(res.body, { error: 'title is required and must be a non-empty string' });
  });

  it('rejects a request without a JSON body with 400', async () => {
    const res = await request('POST', '/api/movies');
    assert.equal(res.status, 400);
    assert.deepEqual(res.body, { error: 'Request body must be a JSON object' });
  });

  it('rejects malformed JSON with 400', async () => {
    for (const raw of ['{"title": ', '"just a string"', '42']) {
      const res = await request('POST', '/api/movies', raw);
      assert.equal(res.status, 400, `raw=${raw}`);
      assert.deepEqual(res.body, { error: 'Invalid JSON body' });
    }
  });

  it('rejects an oversized body with 413', async () => {
    const res = await request('POST', '/api/movies', { title: 'x', description: 'y'.repeat(200 * 1024) });
    assert.equal(res.status, 413);
    assert.deepEqual(res.body, { error: 'request entity too large' });
  });
});

describe('GET /api/movies', () => {
  it('lists movies and filters them by title (case-insensitive)', async () => {
    await request('POST', '/api/movies', { title: 'Alien' });
    await request('POST', '/api/movies', { title: 'Aliens' });
    await request('POST', '/api/movies', { title: 'Blade Runner' });

    const all = await request('GET', '/api/movies');
    assert.equal(all.status, 200);
    assert.deepEqual(
      all.body.map((m) => m.title),
      ['Alien', 'Aliens', 'Blade Runner'],
    );

    const filtered = await request('GET', '/api/movies?title=ALIEN');
    assert.equal(filtered.status, 200);
    assert.deepEqual(
      filtered.body.map((m) => m.title),
      ['Alien', 'Aliens'],
    );
  });

  it('rejects a repeated title filter with 400', async () => {
    const res = await request('GET', '/api/movies?title=a&title=b');
    assert.equal(res.status, 400);
    assert.deepEqual(res.body, { error: 'title filter must be a single string' });
  });

  it('rejects a NUL character in the title filter with 400', async () => {
    const res = await request('GET', '/api/movies?title=%00');
    assert.equal(res.status, 400);
    assert.deepEqual(res.body, { error: 'title filter must not contain NUL characters' });
  });
});

describe('GET /api/movies/:id', () => {
  it('returns the movie', async () => {
    await request('POST', '/api/movies', { title: 'Alien' });
    const res = await request('GET', '/api/movies/1');
    assert.equal(res.status, 200);
    assert.equal(res.body.title, 'Alien');
  });

  it('answers 404 for an unknown id and 400 for an invalid one', async () => {
    assert.deepEqual(await stripHeaders(request('GET', '/api/movies/999')), { status: 404, body: { error: 'Movie not found' } });
    assert.deepEqual(await stripHeaders(request('GET', '/api/movies/abc')), {
      status: 400,
      body: { error: 'id must be a positive integer' },
    });
  });
});

describe('PUT /api/movies/:id', () => {
  it('updates an existing movie', async () => {
    await request('POST', '/api/movies', { title: 'Alien', description: 'v1' });
    const res = await request('PUT', '/api/movies/1', { title: 'Alien (Director\'s Cut)' });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      id: 1,
      title: 'Alien (Director\'s Cut)',
      description: '',
      created_at: '2026-01-01T00:00:00.000Z',
    });
  });

  it('answers 404 for an unknown id and 400 for an invalid body', async () => {
    assert.equal((await request('PUT', '/api/movies/42', { title: 'x' })).status, 404);
    await request('POST', '/api/movies', { title: 'Alien' });
    const res = await request('PUT', '/api/movies/1', { title: '' });
    assert.equal(res.status, 400);
  });
});

describe('DELETE /api/movies', () => {
  it('deletes one movie by id', async () => {
    await request('POST', '/api/movies', { title: 'Alien' });
    assert.deepEqual(await stripHeaders(request('DELETE', '/api/movies/1')), {
      status: 200,
      body: { message: 'Movie deleted', id: 1 },
    });
    assert.equal((await request('DELETE', '/api/movies/1')).status, 404);
  });

  it('deletes every movie and reports the count', async () => {
    await request('POST', '/api/movies', { title: 'Alien' });
    await request('POST', '/api/movies', { title: 'Aliens' });
    assert.deepEqual(await stripHeaders(request('DELETE', '/api/movies')), {
      status: 200,
      body: { message: 'All movies deleted', deleted: 2 },
    });
    assert.deepEqual((await request('GET', '/api/movies')).body, []);
  });
});

describe('error handling', () => {
  it('answers 404 JSON for unknown routes', async () => {
    assert.deepEqual(await stripHeaders(request('GET', '/nope')), { status: 404, body: { error: 'Not found' } });
  });

  it('hides internal errors behind a generic 500 and logs them', async () => {
    db.failing = true;
    const res = await request('GET', '/api/movies');
    assert.equal(res.status, 500);
    assert.deepEqual(res.body, { error: 'Internal server error' });
    const errorLog = logLines.find((line) => line.level === 'error');
    assert.equal(errorLog.msg, 'Unhandled request error');
    assert.deepEqual(errorLog.err, { name: 'Error', message: 'database exploded' });
  });

  it('writes one JSON line per completed request', async () => {
    await request('GET', '/api/movies');
    const accessLog = logLines.find((line) => line.msg === 'Request completed');
    assert.equal(accessLog.level, 'info');
    assert.equal(accessLog.service, 'test');
    assert.equal(accessLog.method, 'GET');
    assert.equal(accessLog.path, '/api/movies');
    assert.equal(accessLog.status, 200);
    assert.equal(typeof accessLog.durationMs, 'number');
    assert.match(accessLog.time, /^\d{4}-\d{2}-\d{2}T/);
  });
});

async function stripHeaders(pending) {
  const { status, body } = await pending;
  return { status, body };
}
