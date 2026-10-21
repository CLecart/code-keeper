import assert from 'node:assert/strict';
import { once } from 'node:events';
import { describe, it } from 'node:test';
import { createApp } from '../src/app.js';
import { fakeDatabase, fakeQueue, silentLogger } from './helpers.js';

async function request(app, path) {
  const server = app.listen(0);
  await once(server, 'listening');
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${path}`);
    return { status: response.status, headers: response.headers, body: await response.json() };
  } finally {
    server.close();
  }
}

const orders = [{ id: 1, user_id: 20, number_of_items: 99, total_amount: 250, created_at: '2026-01-01T00:00:00.000Z' }];

const appWith = ({ db = fakeDatabase({ orders }), queue = fakeQueue(true) } = {}) =>
  createApp({ db, queue, logger: silentLogger });

describe('GET /health', () => {
  it('reports ok when both dependencies are up', async () => {
    const { status, headers, body } = await request(appWith(), '/health');
    assert.equal(status, 200);
    assert.deepEqual(body, { status: 'ok', database: 'up', rabbitmq: 'connected' });
    assert.equal(headers.get('x-powered-by'), null);
  });

  it('reports 503 with the database down', async () => {
    const { status, body } = await request(appWith({ db: fakeDatabase({ up: false }) }), '/health');
    assert.equal(status, 503);
    assert.deepEqual(body, { status: 'error', database: 'down', rabbitmq: 'connected' });
  });

  it('reports 503 with rabbitmq disconnected', async () => {
    const { status, body } = await request(appWith({ queue: fakeQueue(false) }), '/health');
    assert.equal(status, 503);
    assert.deepEqual(body, { status: 'error', database: 'up', rabbitmq: 'down' });
  });
});

describe('GET /api/orders', () => {
  it('lists the stored orders', async () => {
    const { status, body } = await request(appWith(), '/api/orders');
    assert.equal(status, 200);
    assert.deepEqual(body, orders);
  });

  it('answers 500 without leaking details when the query fails', async () => {
    const { status, body } = await request(appWith({ db: fakeDatabase({ up: false }) }), '/api/orders');
    assert.equal(status, 500);
    assert.deepEqual(body, { error: 'Internal server error' });
  });
});

describe('unknown routes', () => {
  it('answer 404 JSON', async () => {
    const { status, body } = await request(appWith(), '/nope');
    assert.equal(status, 404);
    assert.deepEqual(body, { error: 'Not found' });
  });
});
