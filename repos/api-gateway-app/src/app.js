import express from 'express';
import morgan from 'morgan';
import { errorFields } from './logger.js';
import { createInventoryProxy } from './proxy.js';
import { createBillingRouter } from './routes/billing.js';

function createErrorHandler(logger) {
  // Express recognises an error handler by its four parameters.
  return (err, req, res, next) => {
    if (res.headersSent) {
      next(err);
      return;
    }
    const status = err.status ?? err.statusCode ?? 500;
    if (status >= 500) {
      logger.error('unhandled request error', { method: req.method, path: req.originalUrl, ...errorFields(err) });
      res.status(500).json({ error: 'Internal server error' });
      return;
    }
    res.status(status).json({ error: err.type === 'entity.parse.failed' ? 'Invalid JSON body' : err.message });
  };
}

/** Builds the express app; dependencies are injected so it can be tested with fakes. */
export function createApp({ queue, logger, accessLogStream, inventoryUrl }) {
  const app = express();
  app.disable('x-powered-by');

  if (accessLogStream) {
    // Health probes run every 10 s and would drown the real traffic in access.log.
    app.use(morgan('combined', { stream: accessLogStream, skip: (req) => req.path === '/health' }));
  }

  app.get('/health', (req, res) => {
    const connected = queue.isConnected();
    res.status(connected ? 200 : 503).json({
      status: connected ? 'ok' : 'error',
      rabbitmq: connected ? 'connected' : 'down',
    });
  });

  // The proxy streams the raw request to inventory-app, so it must run before
  // any body parser (which would consume the body).
  app.use(createInventoryProxy({ target: inventoryUrl, logger }));
  app.use('/api/billing', createBillingRouter({ queue, logger }));

  app.use((req, res) => res.status(404).json({ error: 'Not found' }));
  app.use(createErrorHandler(logger));
  return app;
}
