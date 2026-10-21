import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { setTimeout as sleep } from 'node:timers/promises';
import { describe, it } from 'node:test';
import { createQueue } from '../src/queue.js';
import { silentLogger } from './helpers.js';

// In-memory stand-in for amqplib: records channel calls and lets tests
// deliver messages or kill the connection.
function fakeBroker() {
  const broker = { connections: [], failNext: 0 };
  broker.connect = async () => {
    if (broker.failNext > 0) {
      broker.failNext -= 1;
      throw new Error('ECONNREFUSED');
    }
    const connection = new EventEmitter();
    const channel = new EventEmitter();
    Object.assign(channel, {
      calls: [],
      assertQueue: async (...args) => channel.calls.push(['assertQueue', ...args]),
      prefetch: async (...args) => channel.calls.push(['prefetch', ...args]),
      consume: async (queue, onMessage, options) => {
        channel.calls.push(['consume', queue, options]);
        channel.deliver = onMessage;
        return { consumerTag: 'tag-1' };
      },
      ack: (...args) => channel.calls.push(['ack', ...args]),
      nack: (...args) => channel.calls.push(['nack', ...args]),
      cancel: async (tag) => channel.calls.push(['cancel', tag]),
      close: async () => {
        channel.calls.push(['close']);
        channel.emit('close');
      },
    });
    Object.assign(connection, {
      channel,
      createChannel: async () => channel,
      close: async () => {
        connection.closed = true;
        channel.emit('close');
        connection.emit('close');
      },
    });
    broker.connections.push(connection);
    return connection;
  };
  return broker;
}

function queueWith(broker, handler) {
  return createQueue({
    hostname: 'mq',
    port: 5672,
    username: 'u',
    password: 'p',
    queue: 'billing_queue',
    handler,
    logger: silentLogger,
    connect: broker.connect,
    baseDelayMs: 1,
    maxDelayMs: 4,
    requeueDelayMs: 0,
  });
}

const message = { content: Buffer.from('{}') };
const settled = () => sleep(5);

describe('createQueue', () => {
  it('declares a durable queue, prefetch 1 and a manual-ack consumer', async () => {
    const broker = fakeBroker();
    const queue = queueWith(broker, async () => 'ack');
    await queue.start();
    assert.equal(queue.isConnected(), true);
    assert.deepEqual(broker.connections[0].channel.calls, [
      ['assertQueue', 'billing_queue', { durable: true }],
      ['prefetch', 1],
      ['consume', 'billing_queue', { noAck: false }],
    ]);
    await queue.close();
  });

  it('acks stored messages, drops invalid ones and requeues transient failures', async () => {
    const broker = fakeBroker();
    const outcomes = ['ack', 'drop', 'requeue'];
    const queue = queueWith(broker, async () => outcomes.shift());
    await queue.start();
    const { channel } = broker.connections[0];
    for (let i = 0; i < 3; i += 1) {
      channel.deliver(message);
      await settled();
    }
    assert.deepEqual(channel.calls.slice(3), [
      ['ack', message],
      ['nack', message, false, false],
      ['nack', message, false, true],
    ]);
    await queue.close();
  });

  it('requeues when the handler throws', async () => {
    const broker = fakeBroker();
    const queue = queueWith(broker, async () => {
      throw new Error('unexpected');
    });
    await queue.start();
    const { channel } = broker.connections[0];
    channel.deliver(message);
    await settled();
    assert.deepEqual(channel.calls.at(-1), ['nack', message, false, true]);
    await queue.close();
  });

  it('retries until the broker accepts the connection', async () => {
    const broker = fakeBroker();
    broker.failNext = 2;
    const queue = queueWith(broker, async () => 'ack');
    await queue.start();
    assert.equal(queue.isConnected(), false);
    await sleep(50);
    assert.equal(queue.isConnected(), true);
    assert.equal(broker.connections.length, 1);
    await queue.close();
  });

  it('reconnects and re-registers the consumer after the connection drops', async () => {
    const broker = fakeBroker();
    const queue = queueWith(broker, async () => 'ack');
    await queue.start();
    broker.connections[0].emit('close');
    assert.equal(queue.isConnected(), false);
    await sleep(50);
    assert.equal(queue.isConnected(), true);
    assert.equal(broker.connections.length, 2);
    assert.equal(typeof broker.connections[1].channel.deliver, 'function');
    await queue.close();
  });

  it('recycles the connection when the broker cancels the consumer', async () => {
    const broker = fakeBroker();
    const queue = queueWith(broker, async () => 'ack');
    await queue.start();
    broker.connections[0].channel.deliver(null);
    await sleep(50);
    assert.equal(broker.connections[0].closed, true);
    assert.equal(broker.connections.length, 2);
    assert.equal(queue.isConnected(), true);
    await queue.close();
  });

  it('cancels the consumer, waits for the in-flight message and stops reconnecting on close', async () => {
    const broker = fakeBroker();
    let release;
    const queue = queueWith(broker, () => new Promise((resolve) => {
      release = () => resolve('ack');
    }));
    await queue.start();
    const { channel } = broker.connections[0];
    channel.deliver(message);
    await settled();
    const closing = queue.close();
    await settled();
    assert.deepEqual(channel.calls.at(-1), ['cancel', 'tag-1']);
    release();
    await closing;
    assert.deepEqual(channel.calls.slice(-2), [['ack', message], ['close']]);
    assert.equal(broker.connections[0].closed, true);
    await sleep(20);
    assert.equal(broker.connections.length, 1);
    assert.equal(queue.isConnected(), false);
  });
});
