import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createDb, escapeLikePattern, waitForDatabase } from '../src/db.js';

const silentLogger = { info() {}, warn() {}, error() {} };

/** Fake pg pool that replays scripted results (an Error entry is thrown) and records calls. */
function createFakePool(results) {
  const calls = [];
  return {
    calls,
    async query(text, params) {
      calls.push({ text, params });
      const result = results.shift();
      if (result instanceof Error) {
        throw result;
      }
      return result;
    },
  };
}

describe('waitForDatabase', () => {
  it('returns immediately when the database answers', async () => {
    const pool = createFakePool([{ rows: [] }]);
    const sleeps = [];
    await waitForDatabase(pool, { logger: silentLogger, sleep: async (ms) => sleeps.push(ms) });
    assert.equal(pool.calls.length, 1);
    assert.deepEqual(sleeps, []);
  });

  it('retries with the configured delay until the database answers', async () => {
    const pool = createFakePool([new Error('ECONNREFUSED'), new Error('ECONNREFUSED'), { rows: [] }]);
    const sleeps = [];
    const warnings = [];
    const logger = { ...silentLogger, warn: (msg, fields) => warnings.push({ msg, fields }) };
    await waitForDatabase(pool, { logger, attempts: 5, delayMs: 10, sleep: async (ms) => sleeps.push(ms) });
    assert.equal(pool.calls.length, 3);
    assert.deepEqual(sleeps, [10, 10]);
    assert.deepEqual(
      warnings.map((w) => w.fields.attempt),
      [1, 2],
    );
  });

  it('gives up after the configured number of attempts', async () => {
    const pool = createFakePool([new Error('boom'), new Error('boom'), new Error('boom')]);
    const sleeps = [];
    await assert.rejects(
      waitForDatabase(pool, { logger: silentLogger, attempts: 3, delayMs: 1, sleep: async (ms) => sleeps.push(ms) }),
      /unreachable after 3 attempts: boom/,
    );
    assert.equal(pool.calls.length, 3);
    assert.equal(sleeps.length, 2);
  });
});

describe('escapeLikePattern', () => {
  it('escapes LIKE wildcards and the escape character itself', () => {
    assert.equal(escapeLikePattern('100% sure_thing\\'), '100\\% sure\\_thing\\\\');
    assert.equal(escapeLikePattern('plain'), 'plain');
  });
});

describe('createDb', () => {
  it('filters titles with an escaped ILIKE pattern', async () => {
    const pool = createFakePool([{ rows: [{ id: 1 }] }]);
    const rows = await createDb(pool).listMovies('50%');
    assert.deepEqual(rows, [{ id: 1 }]);
    assert.match(pool.calls[0].text, /ILIKE \$1/);
    assert.deepEqual(pool.calls[0].params, ['%50\\%%']);
  });

  it('lists everything ordered by id when no filter is given', async () => {
    const pool = createFakePool([{ rows: [] }]);
    await createDb(pool).listMovies(undefined);
    assert.match(pool.calls[0].text, /ORDER BY id$/);
    assert.equal(pool.calls[0].params, undefined);
  });

  it('returns null for a missing movie and maps delete row counts', async () => {
    const pool = createFakePool([{ rows: [] }, { rows: [] }, { rowCount: 0 }, { rowCount: 1 }, { rowCount: 7 }]);
    const db = createDb(pool);
    assert.equal(await db.getMovie(9), null);
    assert.equal(await db.updateMovie(9, { title: 't', description: '' }), null);
    assert.equal(await db.deleteMovie(9), false);
    assert.equal(await db.deleteMovie(1), true);
    assert.equal(await db.deleteAllMovies(), 7);
    assert.deepEqual(
      pool.calls.map((c) => c.params),
      [[9], [9, 't', ''], [9], [1], undefined],
    );
  });
});
