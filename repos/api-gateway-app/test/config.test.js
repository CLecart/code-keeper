import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ConfigError, loadConfig } from '../src/config.js';

const secrets = { RABBITMQ_USER: 'rabbit_user', RABBITMQ_PASSWORD: 's3cret' };

const throwsConfigError = (env, pattern) =>
  assert.throws(() => loadConfig(env), (err) => err instanceof ConfigError && pattern.test(err.message));

test('applies the documented defaults', () => {
  assert.deepEqual(loadConfig(secrets), {
    port: 3000,
    inventoryUrl: 'http://inventory-app:8080',
    logDir: '/var/logs/api-gateway',
    rabbitmq: {
      host: 'rabbitmq',
      port: 5672,
      user: 'rabbit_user',
      password: 's3cret',
      queue: 'billing_queue',
    },
  });
});

test('reads overrides and normalises the inventory URL', () => {
  const config = loadConfig({
    ...secrets,
    PORT: '8081',
    INVENTORY_APP_URL: 'http://localhost:9090/',
    RABBITMQ_HOST: 'mq',
    RABBITMQ_PORT: '5673',
    RABBITMQ_QUEUE: 'orders',
    LOG_DIR: '/tmp/logs',
  });
  assert.equal(config.port, 8081);
  assert.equal(config.inventoryUrl, 'http://localhost:9090');
  assert.equal(config.logDir, '/tmp/logs');
  assert.deepEqual(config.rabbitmq, { host: 'mq', port: 5673, user: 'rabbit_user', password: 's3cret', queue: 'orders' });
});

test('strips every trailing slash of the inventory URL', () => {
  const inventoryUrl = (url) => loadConfig({ ...secrets, INVENTORY_APP_URL: url }).inventoryUrl;
  assert.equal(inventoryUrl('http://localhost:9090///'), 'http://localhost:9090');
  assert.equal(inventoryUrl('http://inventory-app:8080/api/'), 'http://inventory-app:8080/api');
  assert.equal(inventoryUrl(`http://a/${'/'.repeat(100000)}x`), `http://a/${'/'.repeat(100000)}x`);
});

test('fails fast when a secret is missing or empty', () => {
  throwsConfigError({}, /Missing required environment variable\(s\): RABBITMQ_USER, RABBITMQ_PASSWORD/);
  throwsConfigError({ ...secrets, RABBITMQ_PASSWORD: '' }, /RABBITMQ_PASSWORD/);
});

test('rejects invalid ports', () => {
  for (const port of ['0', 'abc', '70000', '80.5']) {
    throwsConfigError({ ...secrets, PORT: port }, /PORT must be a TCP port number/);
    throwsConfigError({ ...secrets, RABBITMQ_PORT: port }, /RABBITMQ_PORT must be a TCP port number/);
  }
});

test('rejects an inventory URL that is not absolute http(s)', () => {
  throwsConfigError({ ...secrets, INVENTORY_APP_URL: 'inventory-app:8080' }, /INVENTORY_APP_URL must use http or https/);
  throwsConfigError({ ...secrets, INVENTORY_APP_URL: 'ftp://inventory-app' }, /INVENTORY_APP_URL must use http or https/);
  throwsConfigError({ ...secrets, INVENTORY_APP_URL: '::not a url' }, /INVENTORY_APP_URL must be an absolute URL/);
});
