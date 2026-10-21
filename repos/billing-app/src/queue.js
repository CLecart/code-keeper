import { setTimeout as sleep } from 'node:timers/promises';
import amqp from 'amqplib';

// Teardown helper: closing something already closed is not an error worth surfacing.
async function quietly(action) {
  try {
    await action();
  } catch {
    // Already closed or closing: nothing left to do.
  }
}

// RabbitMQ consumer that reconnects forever with exponential backoff and
// re-registers its consumer on every (re)connection.
// `handler(content)` must resolve to 'ack', 'drop' or 'requeue'.
export function createQueue({
  hostname,
  port,
  username,
  password,
  queue,
  handler,
  logger,
  connect = amqp.connect,
  baseDelayMs = 1000,
  maxDelayMs = 30000,
  requeueDelayMs = 5000,
}) {
  let connection = null;
  let channel = null;
  let consumerTag = null;
  let inFlight = null;
  let reconnectTimer = null;
  let failures = 0;
  let closing = false;

  // Drops the active connection so the 'close' event triggers a reconnect.
  // Idempotent: closing a connection also closes its channel, which lands here again.
  function recycle(conn) {
    if (connection !== conn) {
      return;
    }
    connection = null;
    channel = null;
    quietly(() => conn.close());
  }

  function scheduleReconnect() {
    if (closing || reconnectTimer) {
      return;
    }
    const delayMs = Math.min(baseDelayMs * 2 ** failures, maxDelayMs);
    failures += 1;
    logger.warn('rabbitmq reconnect scheduled', { delayMs });
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      open();
    }, delayMs);
  }

  async function settle(ch, msg) {
    let outcome;
    try {
      outcome = await handler(msg.content);
    } catch (err) {
      logger.error('message handler failed', { err });
      outcome = 'requeue';
    }
    try {
      if (outcome === 'ack') {
        ch.ack(msg);
      } else if (outcome === 'drop') {
        ch.nack(msg, false, false);
      } else {
        await sleep(requeueDelayMs);
        ch.nack(msg, false, true);
      }
    } catch (err) {
      // The channel went away meanwhile: the broker redelivers unacked messages itself.
      logger.warn('could not settle message', { outcome, err });
    }
  }

  async function open() {
    if (closing) {
      return;
    }
    let conn = null;
    try {
      conn = await connect({ hostname, port, username, password, heartbeat: 30 }, { timeout: 10000 });
      conn.on('error', (err) => logger.warn('rabbitmq connection error', { err }));
      conn.on('close', () => {
        connection = null;
        channel = null;
        if (!closing) {
          logger.warn('rabbitmq connection closed');
          scheduleReconnect();
        }
      });

      const ch = await conn.createChannel();
      ch.on('error', (err) => logger.warn('rabbitmq channel error', { err }));
      ch.on('close', () => {
        channel = null;
        // The consumer dies with its channel: a fresh connection registers a new one.
        if (!closing) {
          recycle(conn);
        }
      });

      await ch.assertQueue(queue, { durable: true });
      await ch.prefetch(1);
      const consumer = await ch.consume(queue, (msg) => {
        if (msg === null) {
          logger.warn('consumer cancelled by broker');
          recycle(conn);
          return;
        }
        inFlight = settle(ch, msg).finally(() => {
          inFlight = null;
        });
      }, { noAck: false });

      connection = conn;
      channel = ch;
      consumerTag = consumer.consumerTag;
      failures = 0;
      logger.info('rabbitmq consumer ready', { queue });
    } catch (err) {
      logger.warn('rabbitmq connection failed', { err });
      scheduleReconnect();
      await quietly(() => conn?.close());
    }
  }

  return {
    start: () => open(),

    isConnected: () => channel !== null,

    async close() {
      closing = true;
      clearTimeout(reconnectTimer);
      if (channel) {
        // Stop taking deliveries, let the in-flight one settle, then tear down.
        await quietly(() => channel.cancel(consumerTag));
        await inFlight;
        await quietly(() => channel.close());
      }
      await quietly(() => connection?.close());
    },
  };
}
