import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { parseMovieId, validateMoviePayload } from '../src/routes/movies.js';

describe('parseMovieId', () => {
  it('accepts positive integers up to the SERIAL range', () => {
    assert.equal(parseMovieId('1'), 1);
    assert.equal(parseMovieId('42'), 42);
    assert.equal(parseMovieId('007'), 7);
    assert.equal(parseMovieId('2147483647'), 2147483647);
  });

  it('rejects anything that is not a positive 32-bit integer', () => {
    for (const raw of ['0', '-1', 'abc', '1.5', '1e3', ' 1', '1 ', '', '2147483648', undefined, 7]) {
      assert.equal(parseMovieId(raw), null, `expected null for ${JSON.stringify(raw)}`);
    }
  });
});

describe('validateMoviePayload', () => {
  it('accepts a title with an optional description', () => {
    assert.deepEqual(validateMoviePayload({ title: 'Alien', description: 'In space...' }), {
      value: { title: 'Alien', description: 'In space...' },
    });
  });

  it('trims the title and defaults the description to an empty string', () => {
    assert.deepEqual(validateMoviePayload({ title: '  Alien  ' }), { value: { title: 'Alien', description: '' } });
    assert.deepEqual(validateMoviePayload({ title: 'Alien', description: null }), {
      value: { title: 'Alien', description: '' },
    });
  });

  it('ignores unknown fields', () => {
    assert.deepEqual(validateMoviePayload({ title: 'Alien', id: 99, rating: 5 }), {
      value: { title: 'Alien', description: '' },
    });
  });

  it('rejects bodies that are not JSON objects', () => {
    for (const body of [undefined, null, 'Alien', 42, ['Alien']]) {
      assert.equal(validateMoviePayload(body).error, 'Request body must be a JSON object');
    }
  });

  it('rejects a missing, blank or non-string title', () => {
    for (const body of [{}, { title: '' }, { title: '   ' }, { title: 12 }, { title: null }, { title: ['x'] }]) {
      assert.equal(validateMoviePayload(body).error, 'title is required and must be a non-empty string');
    }
  });

  it('rejects a title longer than 255 characters', () => {
    assert.equal(validateMoviePayload({ title: 'a'.repeat(255) }).error, undefined);
    assert.equal(validateMoviePayload({ title: 'a'.repeat(256) }).error, 'title must be at most 255 characters');
  });

  it('rejects a non-string description', () => {
    for (const description of [5, {}, [], true]) {
      assert.equal(validateMoviePayload({ title: 'Alien', description }).error, 'description must be a string');
    }
  });

  // PostgreSQL cannot store U+0000 in a text column: the request must fail with
  // a 400 rather than reach the driver and be reported as a 500.
  it('rejects a NUL character in the title or the description', () => {
    const expected = 'title and description must not contain NUL characters';
    assert.equal(validateMoviePayload({ title: 'Ali\u0000en' }).error, expected);
    assert.equal(validateMoviePayload({ title: 'Alien', description: 'in\u0000space' }).error, expected);
    assert.equal(validateMoviePayload({ title: 'Alien', description: 'in space' }).error, undefined);
  });
});
