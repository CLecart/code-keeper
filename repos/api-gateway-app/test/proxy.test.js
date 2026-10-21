import assert from 'node:assert/strict';
import http from 'node:http';
import { test } from 'node:test';
import { createApp } from '../src/app.js';
import { isInventoryPath } from '../src/proxy.js';

const logger = { info() {}, warn() {}, error() {} };
const queue = { isConnected: () => true, publish: async () => {} };

const listen = (server) =>
  new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(`http://127.0.0.1:${server.address().port}`)));

function close(server) {
  server.closeAllConnections();
  return new Promise((resolve) => server.close(resolve));
}

/** Fake inventory-app that records what it receives and echoes the path back. */
function createFakeInventory() {
  const requests = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      requests.push({ method: req.method, url: req.url, body, host: req.headers.host, type: req.headers['content-type'] });
      res.writeHead(req.url === '/api/movies/404' ? 404 : 200, { 'Content-Type': 'application/json', 'X-Upstream': 'inventory' });
      res.end(JSON.stringify({ echoed: req.url }));
    });
  });
  return { server, requests };
}

async function withGateway(inventoryUrl, run) {
  const server = http.createServer(createApp({ queue, logger, inventoryUrl }));
  const base = await listen(server);
  try {
    await run(base);
  } finally {
    await close(server);
  }
}

test('isInventoryPath matches only the movies resource', () => {
  for (const pathname of ['/api/movies', '/api/movies/', '/api/movies/42']) {
    assert.equal(isInventoryPath(pathname), true, pathname);
  }
  for (const pathname of ['/api/moviesx', '/api/billing', '/api', '/health', '/']) {
    assert.equal(isInventoryPath(pathname), false, pathname);
  }
});

test('forwards path, query, method and body unchanged and relays the upstream response', async () => {
  const inventory = createFakeInventory();
  const inventoryUrl = await listen(inventory.server);
  try {
    await withGateway(inventoryUrl, async (base) => {
      const get = await fetch(`${base}/api/movies/42`);
      assert.equal(get.status, 200);
      assert.equal(get.headers.get('x-upstream'), 'inventory');
      assert.deepEqual(await get.json(), { echoed: '/api/movies/42' });

      await fetch(`${base}/api/movies?title=Alien`);

      const post = await fetch(`${base}/api/movies`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title: 'Alien' }),
      });
      assert.equal(post.status, 200);

      const missing = await fetch(`${base}/api/movies/404`, { method: 'DELETE' });
      assert.equal(missing.status, 404);
      assert.deepEqual(await missing.json(), { echoed: '/api/movies/404' });
    });
  } finally {
    await close(inventory.server);
  }

  assert.deepEqual(
    inventory.requests.map(({ method, url, body }) => ({ method, url, body })),
    [
      { method: 'GET', url: '/api/movies/42', body: '' },
      { method: 'GET', url: '/api/movies?title=Alien', body: '' },
      { method: 'POST', url: '/api/movies', body: '{"title":"Alien"}' },
      { method: 'DELETE', url: '/api/movies/404', body: '' },
    ],
  );
  assert.equal(inventory.requests[2].type, 'application/json');
  // changeOrigin: the upstream sees its own host header, not the gateway's.
  assert.equal(inventory.requests[0].host, new URL(inventoryUrl).host);
});

test('does not proxy paths outside /api/movies', async () => {
  const inventory = createFakeInventory();
  const inventoryUrl = await listen(inventory.server);
  try {
    await withGateway(inventoryUrl, async (base) => {
      const res = await fetch(`${base}/api/moviesx`);
      assert.equal(res.status, 404);
      assert.deepEqual(await res.json(), { error: 'Not found' });
    });
  } finally {
    await close(inventory.server);
  }
  assert.deepEqual(inventory.requests, []);
});

test('answers 502 JSON when inventory-app is unreachable', async () => {
  // Reserve a port and release it so nothing listens there.
  const probe = http.createServer();
  const deadUrl = await listen(probe);
  await close(probe);

  await withGateway(deadUrl, async (base) => {
    const res = await fetch(`${base}/api/movies`);
    assert.equal(res.status, 502);
    assert.equal(res.headers.get('content-type'), 'application/json');
    assert.deepEqual(await res.json(), { error: 'Inventory service unavailable' });
  });
});
