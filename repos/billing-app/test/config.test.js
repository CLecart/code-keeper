import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ConfigError, loadConfig } from '../src/config.js';

const secrets = { DB_PASSWORD: 'db-secret', RABBITMQ_PASSWORD: 'mq-secret' };

describe('loadConfig', () => {
  it('applies defaults for every non-secret variable', () => {
    const config = loadConfig(secrets);
    assert.equal(config.port, 8080);
    assert.deepEqual(config.db, {
      host: 'billing-database',
      port: 5432,
      database: 'orders',
      user: 'billing_user',
      password: 'db-secret',
    });
    assert.deepEqual(config.rabbitmq, {
      hostname: 'rabbitmq',
      port: 5672,
      username: 'rabbit_user',
      password: 'mq-secret',
      queue: 'billing_queue',
    });
  });

  it('reads explicit values and coerces ports to numbers', () => {
    const config = loadConfig({
      ...secrets,
      PORT: '9090',
      DB_HOST: 'pg',
      DB_PORT: '15432',
      DB_NAME: 'billing',
      DB_USER: 'me',
      RABBITMQ_HOST: 'mq',
      RABBITMQ_PORT: '15672',
      RABBITMQ_USER: 'guest',
      RABBITMQ_QUEUE: 'q',
    });
    assert.equal(config.port, 9090);
    assert.equal(config.db.host, 'pg');
    assert.equal(config.db.port, 15432);
    assert.equal(config.db.database, 'billing');
    assert.equal(config.db.user, 'me');
    assert.equal(config.rabbitmq.hostname, 'mq');
    assert.equal(config.rabbitmq.port, 15672);
    assert.equal(config.rabbitmq.username, 'guest');
    assert.equal(config.rabbitmq.queue, 'q');
  });

  it('lists every missing secret in one error', () => {
    assert.throws(() => loadConfig({}), (err) =>
      err instanceof ConfigError && /DB_PASSWORD, RABBITMQ_PASSWORD/.test(err.message));
    assert.throws(() => loadConfig({ DB_PASSWORD: 'x' }), /RABBITMQ_PASSWORD/);
  });

  it('treats blank secrets as missing', () => {
    assert.throws(() => loadConfig({ ...secrets, DB_PASSWORD: '  ' }), /DB_PASSWORD/);
  });

  it('rejects invalid ports', () => {
    for (const PORT of ['abc', '0', '70000', '80.5']) {
      assert.throws(() => loadConfig({ ...secrets, PORT }), (err) => err instanceof ConfigError && /Invalid PORT/.test(err.message));
    }
  });

  it('returns a frozen object', () => {
    const config = loadConfig(secrets);
    assert.ok(Object.isFrozen(config) && Object.isFrozen(config.db) && Object.isFrozen(config.rabbitmq));
  });
});
