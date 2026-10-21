import fs from 'node:fs';
import path from 'node:path';
import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createLogger, errorFields, openLogFile, teeSink } from './logger.js';
import { createQueue } from './queue.js';

const SHUTDOWN_TIMEOUT_MS = 10000;

const logger = createLogger();

/** Log files are best effort: stdout logging continues when LOG_DIR is unusable. */
function openLogFiles(logDir) {
  try {
    fs.mkdirSync(logDir, { recursive: true });
  } catch (err) {
    logger.warn('cannot create log directory', { dir: logDir, ...errorFields(err) });
  }
  return {
    gateway: openLogFile(path.join(logDir, 'gateway.log'), logger),
    access: openLogFile(path.join(logDir, 'access.log'), logger),
  };
}

async function main() {
  const config = loadConfig();
  const logFiles = openLogFiles(config.logDir);
  if (logFiles.gateway) {
    logger.addSink(logFiles.gateway);
  }
  const accessLogStream = teeSink([process.stdout, logFiles.access].filter(Boolean));

  const queue = createQueue({ ...config.rabbitmq, logger });
  // Not awaited: /api/movies must be served even while RabbitMQ is down
  // (billing answers 503 until the broker is reachable).
  queue.start();

  const app = createApp({ queue, logger, accessLogStream, inventoryUrl: config.inventoryUrl });
  const server = app.listen(config.port, () => {
    logger.info('api gateway listening', { port: config.port, inventoryUrl: config.inventoryUrl, logDir: config.logDir });
  });

  const shutdown = async (signal) => {
    logger.info('shutdown requested', { signal });
    setTimeout(() => {
      logger.error('shutdown timed out, exiting now');
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS).unref();

    server.closeIdleConnections();
    await new Promise((resolve) => server.close(resolve));
    await queue.close();
    logger.info('shutdown complete');
    await Promise.all(Object.values(logFiles).map((file) => file?.end()));
    process.exit(0);
  };
  for (const signal of ['SIGTERM', 'SIGINT']) {
    process.once(signal, () => shutdown(signal));
  }
}

main().catch((err) => {
  logger.error('startup failed', errorFields(err));
  process.exit(1);
});
