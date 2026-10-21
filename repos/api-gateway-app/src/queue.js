import amqp from 'amqplib';
import { errorFields } from './logger.js';

const INITIAL_RECONNECT_DELAY_MS = 1000;
const MAX_RECONNECT_DELAY_MS = 30000;
const HEARTBEAT_SECONDS = 30;
const CONNECT_TIMEOUT_MS = 10000;

/**
 * RabbitMQ publisher on a confirm channel. Reconnects forever with exponential
 * backoff; while disconnected, isConnected() is false and publish() rejects.
 */
export function createQueue({ host, port, user, password, queue, logger }) {
  let connection = null;
  let channel = null;
  let reconnectTimer = null;
  let attempt = 0;
  let closing = false;

  function scheduleReconnect() {
    if (closing || reconnectTimer) {
      return;
    }
    attempt += 1;
    const delayMs = Math.min(INITIAL_RECONNECT_DELAY_MS * 2 ** (attempt - 1), MAX_RECONNECT_DELAY_MS);
    logger.warn('rabbitmq reconnect scheduled', { attempt, delayMs });
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connect();
    }, delayMs);
  }

  function handleConnectionClose(err) {
    connection = null;
    channel = null;
    if (!closing) {
      logger.warn('rabbitmq connection closed', err ? errorFields(err) : {});
      scheduleReconnect();
    }
  }

  async function connect() {
    let conn = null;
    try {
      conn = await amqp.connect(
        { protocol: 'amqp', hostname: host, port, username: user, password, heartbeat: HEARTBEAT_SECONDS },
        { timeout: CONNECT_TIMEOUT_MS },
      );
      conn.on('error', (err) => logger.error('rabbitmq connection error', errorFields(err)));
      const ch = await conn.createConfirmChannel();
      ch.on('error', (err) => logger.error('rabbitmq channel error', errorFields(err)));
      await ch.assertQueue(queue, { durable: true });

      // Only a fully set-up connection takes part in the reconnect cycle.
      conn.on('close', handleConnectionClose);
      ch.on('close', () => {
        channel = null;
        if (!closing) {
          // A channel-level failure tears down the whole connection so that the
          // regular reconnect path rebuilds a clean channel.
          conn.close().catch(() => {});
        }
      });
      connection = conn;
      channel = ch;
      attempt = 0;
      logger.info('rabbitmq connected', { host, port, queue });
    } catch (err) {
      logger.error('rabbitmq connection failed', { host, port, ...errorFields(err) });
      if (conn) {
        conn.close().catch(() => {});
      }
      scheduleReconnect();
    }
  }

  /** Publishes a persistent JSON message; resolves once the broker confirmed it. */
  function publish(body) {
    if (!channel) {
      return Promise.reject(new Error('RabbitMQ is not connected'));
    }
    const content = Buffer.from(JSON.stringify(body));
    const options = { persistent: true, contentType: 'application/json' };
    return new Promise((resolve, reject) => {
      channel.sendToQueue(queue, content, options, (err) => (err ? reject(err) : resolve()));
    });
  }

  async function close() {
    closing = true;
    clearTimeout(reconnectTimer);
    if (connection) {
      await connection.close().catch((err) => logger.warn('rabbitmq close failed', errorFields(err)));
    }
  }

  return {
    start: connect,
    publish,
    isConnected: () => channel !== null,
    close,
  };
}
