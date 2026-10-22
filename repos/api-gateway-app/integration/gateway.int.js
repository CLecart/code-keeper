// Integration tests: the real gateway process (node src/index.js, configured by
// its environment as in the image) against a real RabbitMQ broker and a
// stand-in for inventory-app started by the test.
//
// In the CI, the integration-test job provides the broker as a GitLab service
// (host rabbitmq, credentials in RABBITMQ_DEFAULT_USER / RABBITMQ_DEFAULT_PASS).
// The gateway has no database: the postgres service of the job is not used here.
// Locally, start the same broker image and point the tests at it:
//   INTEGRATION_RABBITMQ_HOST=127.0.0.1 INTEGRATION_RABBITMQ_PORT=<published port> \
//   RABBITMQ_DEFAULT_USER=ci RABBITMQ_DEFAULT_PASS=<its password> npm run test:integration
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import amqp from 'amqplib';

const SERVICE_TIMEOUT_MS = 60000;
const RETRY_INTERVAL_MS = 500;
const TEST_TIMEOUT_MS = 20000;
const APP_DIR = path.join(import.meta.dirname, '..');

// Not RABBITMQ_HOST / RABBITMQ_PORT: those configure the gateway, which the test
// sets itself, and Docker before 29.0 puts RABBITMQ_PORT=tcp://<ip>:<port> in a
// job container linked to the rabbitmq service.
const broker = {
  hostname: process.env.INTEGRATION_RABBITMQ_HOST || 'rabbitmq',
  port: Number(process.env.INTEGRATION_RABBITMQ_PORT || 5672),
  username: process.env.RABBITMQ_DEFAULT_USER,
  password: process.env.RABBITMQ_DEFAULT_PASS,
};
// A queue of its own, deleted at the end: never the billing_queue of a shared broker.
const QUEUE = `billing_queue_integration_${randomUUID()}`;
const ORDER = { user_id: '20', number_of_items: '99', total_amount: '250' };

let connection; // the test's own AMQP connection, to read the queue
let inventory;
let gateway;
let gatewayUrl;
let logDir;

/** Calls attempt() until it succeeds, for at most 60 s, or until signal aborts. */
async function retry(what, attempt, signal) {
  const deadline = Date.now() + SERVICE_TIMEOUT_MS;
  for (;;) {
    try {
      return await attempt();
    } catch (err) {
      signal?.throwIfAborted();
      if (Date.now() >= deadline) {
        throw new Error(`${what} still failing after ${SERVICE_TIMEOUT_MS / 1000} s: ${err.message}`, { cause: err });
      }
    }
    await delay(RETRY_INTERVAL_MS);
  }
}

/** A free TCP port for the gateway (its configuration rejects port 0). */
async function freePort() {
  const probe = net.createServer();
  await new Promise((resolve) => probe.listen(0, resolve));
  const { port } = probe.address();
  await new Promise((resolve) => probe.close(resolve));
  return port;
}

/** Stand-in for inventory-app: records each request and answers with what it received. */
async function startInventory() {
  const requests = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      requests.push({ method: req.method, url: req.url, body });
      res.writeHead(req.method === 'POST' ? 201 : 200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ from: 'inventory-stub', method: req.method, url: req.url }));
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { server, requests, url: `http://127.0.0.1:${server.address().port}` };
}

/** Starts the gateway as the image does (node src/index.js) with this environment. */
function startGateway(env) {
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: APP_DIR,
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  for (const stream of [child.stdout, child.stderr]) {
    stream.setEncoding('utf8');
    stream.on('data', (chunk) => {
      output += chunk;
    });
  }
  // Aborted when the process ends, so a crash stops the readiness wait at once.
  const stop = new AbortController();
  const exit = new Promise((resolve) => {
    child.once('close', (code, signal) => {
      stop.abort(new Error(`the gateway exited (code ${code}, signal ${signal})`));
      resolve({ code, signal });
    });
  });
  return { child, exit, stopped: stop.signal, output: () => output };
}

/** Sends a request to the gateway; returns its status and JSON body. */
async function call(method, urlPath, body) {
  const init =
    body === undefined
      ? { method }
      : { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
  const res = await fetch(`${gatewayUrl}${urlPath}`, init);
  return { status: res.status, body: await res.json() };
}

before(async () => {
  assert.ok(broker.username && broker.password, 'set RABBITMQ_DEFAULT_USER and RABBITMQ_DEFAULT_PASS, as in the CI job');
  // The service container may still be starting: wait until it accepts the credentials.
  connection = await retry(`RabbitMQ at ${broker.hostname}:${broker.port}`, () =>
    amqp.connect({ protocol: 'amqp', ...broker }, { timeout: 5000 }),
  );
  inventory = await startInventory();
  logDir = await fs.mkdtemp(path.join(os.tmpdir(), 'api-gateway-it-'));
  const port = await freePort();
  gatewayUrl = `http://127.0.0.1:${port}`;
  gateway = startGateway({
    PORT: String(port),
    INVENTORY_APP_URL: inventory.url,
    RABBITMQ_HOST: broker.hostname,
    RABBITMQ_PORT: String(broker.port),
    RABBITMQ_USER: broker.username,
    RABBITMQ_PASSWORD: broker.password,
    RABBITMQ_QUEUE: QUEUE,
    LOG_DIR: logDir,
  });
  try {
    // Ready once it listens and holds its RabbitMQ channel.
    await retry(
      'GET /health',
      async () => {
        const res = await fetch(`${gatewayUrl}/health`);
        assert.deepEqual(await res.json(), { status: 'ok', rabbitmq: 'connected' });
      },
      gateway.stopped,
    );
  } catch (err) {
    // Its log says why: credentials, unreachable broker, port taken...
    throw new Error(`gateway not ready: ${err.message}\n--- gateway output ---\n${gateway.output()}`, { cause: err });
  }
});

after(async () => {
  // Still running only when it never got ready or ignored SIGTERM.
  if (gateway?.child.exitCode === null && gateway.child.signalCode === null) {
    gateway.child.kill('SIGKILL');
  }
  await gateway?.exit;
  if (connection) {
    const channel = await connection.createChannel();
    await channel.deleteQueue(QUEUE);
    await connection.close();
  }
  if (inventory) {
    inventory.server.closeAllConnections();
    await new Promise((resolve) => inventory.server.close(resolve));
  }
  if (logDir) {
    await fs.rm(logDir, { recursive: true, force: true });
  }
});

test('POST /api/billing publishes the order into the RabbitMQ queue', { timeout: TEST_TIMEOUT_MS }, async () => {
  const channel = await connection.createChannel();
  // A channel the broker closes also emits 'error': the rejected call reports it.
  channel.on('error', () => {});
  try {
    // Declared as billing-app (the consumer) declares it: fails if the gateway created it otherwise.
    await channel.assertQueue(QUEUE, { durable: true });

    assert.deepEqual(await call('POST', '/api/billing', { user_id: '20' }), {
      status: 400,
      body: { error: 'Missing or non-numeric field(s): number_of_items, total_amount' },
    });
    assert.deepEqual(await call('POST', '/api/billing', ORDER), { status: 200, body: { message: 'Message posted' } });

    // The gateway answers once the broker has confirmed the message: it is already queued.
    const message = await channel.get(QUEUE, { noAck: true });
    assert.ok(message, `no message in ${QUEUE}`);
    assert.deepEqual(JSON.parse(message.content.toString()), ORDER);
    assert.equal(message.properties.contentType, 'application/json');
    assert.equal(message.properties.deliveryMode, 2, 'persistent message');
    // Exactly one message: the invalid order was not published.
    assert.equal(await channel.get(QUEUE, { noAck: true }), false);
  } finally {
    // Closing fails on a channel the broker already closed; the assertion error matters more.
    await channel.close().catch(() => {});
  }
});

test('/api/movies requests are proxied to inventory-app unchanged', { timeout: TEST_TIMEOUT_MS }, async () => {
  const movie = { title: 'Alien', description: 'Science fiction, 1979' };
  const answer = (method, url) => ({ from: 'inventory-stub', method, url });

  assert.deepEqual(await call('GET', '/api/movies?title=Alien'), { status: 200, body: answer('GET', '/api/movies?title=Alien') });
  assert.deepEqual(await call('POST', '/api/movies', movie), { status: 201, body: answer('POST', '/api/movies') });
  assert.deepEqual(await call('DELETE', '/api/movies/7'), { status: 200, body: answer('DELETE', '/api/movies/7') });

  // Path, query, method and body arrive unchanged, and nothing else (billing, health) reached inventory-app.
  assert.deepEqual(inventory.requests, [
    { method: 'GET', url: '/api/movies?title=Alien', body: '' },
    { method: 'POST', url: '/api/movies', body: JSON.stringify(movie) },
    { method: 'DELETE', url: '/api/movies/7', body: '' },
  ]);
});

// A rolling update stops the old pods with SIGTERM: the gateway must close its
// server and its RabbitMQ connection, then exit 0 (exit 1 = shutdown timed out).
test('the gateway stops cleanly on SIGTERM', { timeout: TEST_TIMEOUT_MS }, async () => {
  gateway.child.kill('SIGTERM');
  const { code, signal } = await gateway.exit;
  assert.equal(code, 0, `exit code ${code} (signal ${signal}), output:\n${gateway.output()}`);
});
