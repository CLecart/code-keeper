import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createOrderHandler } from './consumer.js';
import { createDatabase } from './db.js';
import { createLogger } from './logger.js';
import { createQueue } from './queue.js';

const SHUTDOWN_TIMEOUT_MS = 10000;

const logger = createLogger();

function listen(app, port) {
  return new Promise((resolve, reject) => {
    const server = app.listen(port);
    server.once('listening', () => resolve(server));
    server.once('error', reject);
  });
}

const closeServer = (server) => new Promise((resolve) => server.close(resolve));

async function main() {
  const config = loadConfig();

  const db = createDatabase(config.db, logger);
  await db.waitForDatabase();
  logger.info('database ready', { host: config.db.host, database: config.db.database });

  const queue = createQueue({ ...config.rabbitmq, handler: createOrderHandler({ db, logger }), logger });
  await queue.start();

  const server = await listen(createApp({ db, queue, logger }), config.port);
  logger.info('http server listening', { port: config.port });

  let shuttingDown = false;
  const shutdown = async (signal) => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    logger.info('shutting down', { signal });
    setTimeout(() => {
      logger.error('shutdown timed out, exiting');
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS).unref();

    await closeServer(server);
    await queue.close();
    await db.close();
    logger.info('shutdown complete');
    process.exit(0);
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((err) => {
  logger.error('fatal startup error', { err });
  process.exit(1);
});
