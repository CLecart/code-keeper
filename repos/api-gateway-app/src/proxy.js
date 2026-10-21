import { createProxyMiddleware } from 'http-proxy-middleware';
import { errorFields } from './logger.js';

const PROXY_TIMEOUT_MS = 30000;

/** Only the movies resource of inventory-app is exposed through the gateway. */
export function isInventoryPath(pathname) {
  return pathname === '/api/movies' || pathname.startsWith('/api/movies/');
}

/**
 * Reverse proxy to inventory-app. Registered at the application root with a
 * path filter (not mounted under /api/movies) so the path reaches the upstream
 * unchanged.
 */
export function createInventoryProxy({ target, logger }) {
  return createProxyMiddleware({
    target,
    pathFilter: isInventoryPath,
    changeOrigin: true,
    proxyTimeout: PROXY_TIMEOUT_MS,
    on: {
      error(err, req, res) {
        logger.error('inventory proxy error', { method: req.method, path: req.url, ...errorFields(err) });
        if (res.headersSent) {
          // The upstream failed mid-response: cut the connection rather than
          // deliver a truncated body with a successful status.
          res.destroy();
          return;
        }
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Inventory service unavailable' }));
      },
    },
  });
}
