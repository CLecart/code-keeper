import express from 'express';

export function createApp({ db, queue, logger }) {
  const app = express();
  app.disable('x-powered-by');

  app.get('/health', async (req, res) => {
    const databaseUp = await db.ping();
    const queueUp = queue.isConnected();
    const healthy = databaseUp && queueUp;
    res.status(healthy ? 200 : 503).json({
      status: healthy ? 'ok' : 'error',
      database: databaseUp ? 'up' : 'down',
      rabbitmq: queueUp ? 'connected' : 'down',
    });
  });

  app.get('/api/orders', async (req, res) => {
    res.json(await db.listOrders());
  });

  app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  // Express recognises error handlers by their four-argument signature.
  app.use((err, req, res, next) => {
    logger.error('request failed', { method: req.method, path: req.path, err });
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}
