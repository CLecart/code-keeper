import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { ConfigError, loadConfig } from '../src/config.js';

describe('loadConfig', () => {
  it('applies the compose defaults when only the password is provided', () => {
    assert.deepEqual(loadConfig({ DB_PASSWORD: 's3cret' }), {
      port: 8080,
      db: { host: 'inventory-database', port: 5432, database: 'movies', user: 'inventory_user', password: 's3cret' },
    });
  });

  it('reads every variable from the environment', () => {
    const env = {
      PORT: '9090',
      DB_HOST: 'db.internal',
      DB_PORT: '6543',
      DB_NAME: 'catalog',
      DB_USER: 'alice',
      DB_PASSWORD: 'pw',
      UNRELATED: 'ignored',
    };
    assert.deepEqual(loadConfig(env), {
      port: 9090,
      db: { host: 'db.internal', port: 6543, database: 'catalog', user: 'alice', password: 'pw' },
    });
  });

  it('fails fast when the database password is missing or empty', () => {
    for (const env of [{}, { DB_PASSWORD: '' }]) {
      assert.throws(() => loadConfig(env), (err) => err instanceof ConfigError && /DB_PASSWORD/.test(err.message));
    }
  });

  it('rejects ports that are not integers in 1..65535', () => {
    for (const PORT of ['abc', '0', '-1', '65536', '80.5', '']) {
      const env = { PORT, DB_PASSWORD: 'pw' };
      if (PORT === '') {
        assert.equal(loadConfig(env).port, 8080); // empty means "unset": default applies
      } else {
        assert.throws(() => loadConfig(env), (err) => err instanceof ConfigError && /PORT/.test(err.message));
      }
    }
    assert.throws(() => loadConfig({ DB_PORT: 'five', DB_PASSWORD: 'pw' }), /DB_PORT/);
  });
});
