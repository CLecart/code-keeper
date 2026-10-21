import { createApp } from './app.js';
import { ConfigError, loadConfig } from './config.js';
import { createDb, createPool, waitForDatabase } from './db.js';
import { createLogger } from './logger.js';

// Must stay below Docker's default 10 s stop timeout, after which the container is SIGKILLed.
const SHUTDOWN_TIMEOUT_MS = 8000;

const logger = createLogger({ service: 'inventory-app' });

async function main() {
  const config = loadConfig();
  const pool = createPool(config.db);
  // pg emits 'error' on idle clients when the database goes away; unhandled, it would crash Node.
  pool.on('error', (err) => logger.error('Idle database client error', { err }));

  await waitForDatabase(pool, { logger });
  logger.info('Database connection established', {
    host: config.db.host,
    port: config.db.port,
    database: config.db.database,
  });

  const app = createApp({ db: createDb(pool), logger });
  const server = app.listen(config.port, () => logger.info('HTTP server listening', { port: config.port }));

  registerShutdown({ server, pool });
}

/** Graceful shutdown on SIGTERM/SIGINT: stop accepting requests, drain, close the pool, exit 0. */
function registerShutdown({ server, pool }) {
  let shuttingDown = false;

  const shutdown = async (signal) => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    logger.info('Shutdown requested', { signal });
    setTimeout(() => {
      logger.error('Shutdown timed out, forcing exit');
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS).unref();

    try {
      server.closeIdleConnections();
      await new Promise((resolve) => server.close(resolve));
      await pool.end();
      logger.info('Shutdown complete');
      process.exit(0);
    } catch (err) {
      logger.error('Shutdown failed', { err });
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((err) => {
  logger.error(err instanceof ConfigError ? 'Invalid configuration' : 'Fatal startup error', { err });
  process.exit(1);
});
