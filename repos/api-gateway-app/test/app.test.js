import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createApp } from '../src/app.js';

const logger = { info() {}, warn() {}, error() {} };
const AUDIT_BODY = { user_id: '20', number_of_items: '99', total_amount: '250' };

function createFakeQueue({ connected = true, failPublish = false } = {}) {
  const published = [];
  return {
    published,
    isConnected: () => connected,
    async publish(body) {
      if (failPublish) {
        throw new Error('message nacked by broker');
      }
      published.push(body);
    },
  };
}

async function withApp(queue, run) {
  const server = createApp({ queue, logger, inventoryUrl: 'http://127.0.0.1:9' }).listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}

const postJson = (url, body, headers = { 'Content-Type': 'application/json' }) =>
  fetch(url, { method: 'POST', headers, body: typeof body === 'string' ? body : JSON.stringify(body) });

test('POST /api/billing publishes the body and answers 200', async () => {
  const queue = createFakeQueue();
  await withApp(queue, async (base) => {
    const res = await postJson(`${base}/api/billing`, AUDIT_BODY);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { message: 'Message posted' });
    assert.equal(res.headers.get('x-powered-by'), null);
  });
  assert.deepEqual(queue.published, [AUDIT_BODY]);
});

test('POST /api/billing/ with a trailing slash and without Content-Type is accepted', async () => {
  const queue = createFakeQueue();
  await withApp(queue, async (base) => {
    const res = await postJson(`${base}/api/billing/`, AUDIT_BODY, {});
    assert.equal(res.status, 200);
  });
  assert.deepEqual(queue.published, [AUDIT_BODY]);
});

test('POST /api/billing answers 400 on invalid bodies and publishes nothing', async () => {
  const queue = createFakeQueue();
  await withApp(queue, async (base) => {
    const cases = [
      [{ user_id: '20' }, 'Missing or non-numeric field(s): number_of_items, total_amount'],
      [[1, 2, 3], 'Body must be a JSON object'],
      ['{"user_id": 20,', 'Invalid JSON body'],
    ];
    for (const [body, error] of cases) {
      const res = await postJson(`${base}/api/billing`, body);
      assert.equal(res.status, 400);
      assert.deepEqual(await res.json(), { error });
    }
  });
  assert.deepEqual(queue.published, []);
});

test('POST /api/billing answers 503 while RabbitMQ is disconnected', async () => {
  await withApp(createFakeQueue({ connected: false }), async (base) => {
    const res = await postJson(`${base}/api/billing`, AUDIT_BODY);
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: 'Message queue unavailable' });
  });
});

test('POST /api/billing answers 503 when the broker does not confirm the message', async () => {
  await withApp(createFakeQueue({ failPublish: true }), async (base) => {
    const res = await postJson(`${base}/api/billing`, AUDIT_BODY);
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: 'Message queue unavailable' });
  });
});

test('GET /health reflects the RabbitMQ connection state', async () => {
  await withApp(createFakeQueue(), async (base) => {
    const res = await fetch(`${base}/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'ok', rabbitmq: 'connected' });
  });
  await withApp(createFakeQueue({ connected: false }), async (base) => {
    const res = await fetch(`${base}/health`);
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { status: 'error', rabbitmq: 'down' });
  });
});

test('unknown routes answer 404 JSON', async () => {
  await withApp(createFakeQueue(), async (base) => {
    for (const [method, path] of [['GET', '/nope'], ['GET', '/api/billing'], ['DELETE', '/api/billing/1']]) {
      const res = await fetch(`${base}${path}`, { method });
      assert.equal(res.status, 404, `${method} ${path}`);
      assert.deepEqual(await res.json(), { error: 'Not found' });
    }
  });
});
