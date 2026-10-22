// Integration tests: the real billing-app (src/index.js in a child process,
// configured by its real config module) against a real PostgreSQL and a real
// RabbitMQ, the services of the integration-test job in CI. To run them
// locally against containers of the same images, override hosts and ports:
//
//   POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=<port> POSTGRES_PASSWORD=<password> \
//   RABBITMQ_HOST=127.0.0.1 RABBITMQ_PORT=<port> RABBITMQ_DEFAULT_USER=ci \
//   RABBITMQ_DEFAULT_PASS=<password> npm run test:integration
//
// Each run works in a database and a queue of its own, removed at the end.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { setTimeout as sleep } from 'node:timers/promises';
import amqp from 'amqplib';
import pg from 'pg';

const ROOT = join(import.meta.dirname, '..');
const SERVICE_TIMEOUT_MS = 60_000;
const suffix = `${process.pid}_${randomBytes(4).toString('hex')}`;
const DATABASE = `billing_it_${suffix}`;
const QUEUE = `billing_queue_it_${suffix}`;

// The variables of the integration-test job, which the service containers
// read too: same passwords on both sides.
function settings(env = process.env) {
  const required = (name) => {
    if (!env[name]) {
      throw new Error(`${name} must be set (password of the test service)`);
    }
    return env[name];
  };
  return {
    postgres: {
      host: env.POSTGRES_HOST || 'postgres',
      port: Number(env.POSTGRES_PORT || 5432),
      user: env.POSTGRES_USER || 'postgres',
      password: required('POSTGRES_PASSWORD'),
    },
    rabbitmq: {
      hostname: env.RABBITMQ_HOST || 'rabbitmq',
      port: Number(env.RABBITMQ_PORT || 5672),
      username: env.RABBITMQ_DEFAULT_USER || 'ci',
      password: required('RABBITMQ_DEFAULT_PASS'),
    },
  };
}

// The services start together with the job: retry until they accept connections.
async function retry(service, action) {
  const deadline = Date.now() + SERVICE_TIMEOUT_MS;
  for (;;) {
    try {
      return await action();
    } catch (err) {
      if (Date.now() >= deadline) {
        throw new Error(`${service} unreachable after ${SERVICE_TIMEOUT_MS / 1000} s: ${err.message}`, { cause: err });
      }
      await sleep(1000);
    }
  }
}

// The config module rejects PORT=0: borrow a free port for the HTTP server.
async function freePort() {
  const server = createServer().listen(0, '127.0.0.1');
  await once(server, 'listening');
  const { port } = server.address();
  server.close();
  await once(server, 'close');
  return port;
}

describe('billing-app with a real PostgreSQL and RabbitMQ', () => {
  let config;
  let admin; // maintenance database "postgres": creates and drops the test database
  let databaseCreated = false;
  let db; // the test database, as the application sees it
  let connection;
  let channel;
  let app;
  let appPort;
  const appLog = [];

  const running = () => app.exitCode === null && app.signalCode === null;

  async function get(path) {
    const response = await fetch(`http://127.0.0.1:${appPort}${path}`);
    return { status: response.status, body: await response.json() };
  }

  // Published as the api-gateway does: persistent JSON message, confirmed by the broker.
  async function publish(content) {
    channel.sendToQueue(QUEUE, Buffer.from(content), { persistent: true, contentType: 'application/json' });
    await channel.waitForConfirms();
  }

  const lastOrderId = async () => (await db.query('SELECT coalesce(max(id), 0) AS id FROM orders')).rows[0].id;

  // The consumer stores messages asynchronously: polls for the rows added after afterId.
  async function ordersAfter(afterId) {
    const deadline = Date.now() + 15_000;
    for (;;) {
      const { rows } = await db.query(
        'SELECT user_id, number_of_items, total_amount::text AS total_amount FROM orders WHERE id > $1 ORDER BY id',
        [afterId],
      );
      if (rows.length > 0 || Date.now() >= deadline) {
        return rows;
      }
      await sleep(200);
    }
  }

  // GET /health answers 200 once the database answers and the consumer is registered.
  async function waitForHealth() {
    const deadline = Date.now() + SERVICE_TIMEOUT_MS;
    for (;;) {
      if (!running()) {
        throw new Error(`billing-app exited with code ${app.exitCode} (its log follows the tests)`);
      }
      const health = await get('/health').catch(() => null); // not listening yet
      if (health?.status === 200) {
        return;
      }
      if (Date.now() >= deadline) {
        throw new Error(`billing-app not healthy after ${SERVICE_TIMEOUT_MS / 1000} s (its log follows the tests)`);
      }
      await sleep(500);
    }
  }

  // SIGTERM, as Kubernetes stops the pod. index.js exits by itself within 10 s;
  // SIGKILL after 15 s so that no process outlives the tests.
  async function stopApp() {
    if (!running()) {
      return [app.exitCode, app.signalCode];
    }
    const closed = once(app, 'close');
    app.kill('SIGTERM');
    const killer = setTimeout(() => app.kill('SIGKILL'), 15_000);
    try {
      return await closed;
    } finally {
      clearTimeout(killer);
    }
  }

  before(async () => {
    config = settings();

    admin = new pg.Pool({ ...config.postgres, database: 'postgres', max: 1, connectionTimeoutMillis: 5000 });
    await retry('PostgreSQL', () => admin.query('SELECT 1'));
    connection = await retry('RabbitMQ', () => amqp.connect(config.rabbitmq, { timeout: 5000 }));
    // A broken connection or channel makes the next call fail with the reason;
    // without listeners, their 'error' events would crash the test process.
    connection.on('error', () => {});

    await admin.query(`CREATE DATABASE ${pg.escapeIdentifier(DATABASE)}`);
    databaseCreated = true;
    db = new pg.Pool({ ...config.postgres, database: DATABASE, max: 2 });
    // Schema of the platform database (see the header of the fixture).
    await db.query(await readFile(join(import.meta.dirname, 'fixtures', '01-schema.sql'), 'utf8'));

    appPort = await freePort();
    app = spawn(process.execPath, [join(ROOT, 'src', 'index.js')], {
      cwd: ROOT,
      // Only what the application reads, as in its Kubernetes manifest: the
      // rest of the job environment never reaches it.
      env: {
        NODE_ENV: 'production',
        PORT: String(appPort),
        DB_HOST: config.postgres.host,
        DB_PORT: String(config.postgres.port),
        DB_NAME: DATABASE,
        DB_USER: config.postgres.user,
        DB_PASSWORD: config.postgres.password,
        RABBITMQ_HOST: config.rabbitmq.hostname,
        RABBITMQ_PORT: String(config.rabbitmq.port),
        RABBITMQ_USER: config.rabbitmq.username,
        RABBITMQ_PASSWORD: config.rabbitmq.password,
        RABBITMQ_QUEUE: QUEUE,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    for (const stream of [app.stdout, app.stderr]) {
      stream.setEncoding('utf8').on('data', (chunk) => appLog.push(chunk));
    }
    await waitForHealth();

    channel = await connection.createConfirmChannel();
    channel.on('error', () => {});
  }, { timeout: 4 * SERVICE_TIMEOUT_MS });

  // Every step runs even if an earlier one failed, then the errors are reported.
  after(async (t) => {
    const errors = [];
    const attempt = async (step) => {
      try {
        await step();
      } catch (err) {
        errors.push(err);
      }
    };

    if (app) {
      await attempt(stopApp);
      for (const line of appLog.join('').split('\n').filter(Boolean)) {
        t.diagnostic(`billing-app: ${line}`);
      }
    }
    if (connection) {
      await attempt(async () => {
        const cleanup = await connection.createChannel();
        await cleanup.deleteQueue(QUEUE);
        await cleanup.close();
      });
      await attempt(() => connection.close());
    }
    if (db) {
      await attempt(() => db.end());
    }
    if (databaseCreated) {
      await attempt(() => admin.query(`DROP DATABASE ${pg.escapeIdentifier(DATABASE)} WITH (FORCE)`));
    }
    if (admin) {
      await attempt(() => admin.end());
    }
    if (errors.length > 0) {
      throw new AggregateError(errors, 'cleanup failed');
    }
  }, { timeout: SERVICE_TIMEOUT_MS });

  it('reports both dependencies up and consumes the configured queue', async () => {
    assert.deepEqual(await get('/health'), {
      status: 200,
      body: { status: 'ok', database: 'up', rabbitmq: 'connected' },
    });
    const { consumerCount } = await channel.checkQueue(QUEUE);
    assert.equal(consumerCount, 1);
  });

  it('stores an order published on the queue and lists it on GET /api/orders', async () => {
    const previous = await lastOrderId();
    // Numeric strings, as the api-gateway forwards the body of POST /api/billing.
    await publish(JSON.stringify({ user_id: '20', number_of_items: '99', total_amount: '250' }));

    assert.deepEqual(await ordersAfter(previous), [{ user_id: 20, number_of_items: 99, total_amount: '250.00' }]);

    const { status, body } = await get('/api/orders');
    assert.equal(status, 200);
    const listed = body.filter((order) => order.id > previous);
    assert.deepEqual(
      listed.map(({ user_id, number_of_items, total_amount }) => ({ user_id, number_of_items, total_amount })),
      [{ user_id: 20, number_of_items: 99, total_amount: 250 }],
    );
    assert.ok(!Number.isNaN(Date.parse(listed[0].created_at)));
  });

  it('drops invalid messages without storing them', async () => {
    const previous = await lastOrderId();
    await publish('{not json');
    // Valid JSON the table itself would accept (no constraint on user_id):
    // only the validation of billing-app keeps it out.
    await publish(JSON.stringify({ user_id: -5, number_of_items: 1, total_amount: 10 }));
    // A single consumer takes one message at a time, in queue order: once this
    // order is stored, both invalid messages have been handled.
    await publish(JSON.stringify({ user_id: 21, number_of_items: 1, total_amount: 9.99 }));

    assert.deepEqual(await ordersAfter(previous), [{ user_id: 21, number_of_items: 1, total_amount: '9.99' }]);
  });

  it('stops cleanly on SIGTERM and leaves no message in the queue', async () => {
    const [code, signal] = await stopApp();
    assert.deepEqual({ code, signal }, { code: 0, signal: null });
    // An unacknowledged message would be back in the queue once the consumer is
    // gone: an empty queue means every message was acknowledged or dropped.
    const { messageCount, consumerCount } = await channel.checkQueue(QUEUE);
    assert.deepEqual({ messageCount, consumerCount }, { messageCount: 0, consumerCount: 0 });
  });
});
