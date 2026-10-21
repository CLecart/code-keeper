import express from 'express';
import { createMoviesRouter } from './routes/movies.js';

/** Builds the Express application with injected dependencies so it can be unit-tested. */
export function createApp({ db, logger }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(requestLogger(logger));
  app.use(express.json({ limit: '100kb' }));

  app.get('/health', async (req, res) => {
    try {
      await db.ping();
      res.json({ status: 'ok', database: 'up' });
    } catch (err) {
      logger.warn('Health check failed', { err });
      res.status(503).json({ status: 'error', database: 'down' });
    }
  });

  app.use('/api/movies', createMoviesRouter(db));

  app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  // Express identifies error handlers by their 4-parameter signature, so `next` must stay.
  app.use((err, req, res, next) => {
    if (res.headersSent) {
      return next(err);
    }
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'Invalid JSON body' });
    }
    const status = Number(err.status ?? err.statusCode);
    if (status >= 400 && status < 500) {
      // Client errors raised by express/body-parser (413, 415, bad URI...) carry a safe message.
      return res.status(status).json({ error: err.expose ? err.message : 'Bad request' });
    }
    logger.error('Unhandled request error', { method: req.method, path: req.originalUrl, err });
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}

function requestLogger(logger) {
  return (req, res, next) => {
    // Container health checks run every few seconds and would flood the logs.
    if (req.path === '/health') {
      return next();
    }
    const startedAt = process.hrtime.bigint();
    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - startedAt) / 1e6;
      logger.info('Request completed', {
        method: req.method,
        path: req.originalUrl,
        status: res.statusCode,
        durationMs: Math.round(durationMs * 10) / 10,
      });
    });
    next();
  };
}
