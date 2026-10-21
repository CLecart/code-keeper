import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createOrderHandler } from '../src/consumer.js';
import { silentLogger } from './helpers.js';

const valid = Buffer.from('{"user_id":"20","number_of_items":"99","total_amount":"250"}');

function handlerWith(insertOrder) {
  return createOrderHandler({ db: { insertOrder }, logger: silentLogger });
}

describe('createOrderHandler', () => {
  it('stores a valid message with coerced values and acks it', async () => {
    const inserted = [];
    const handle = handlerWith(async (order) => {
      inserted.push(order);
      return { id: 1, user_id: order.userId };
    });
    assert.equal(await handle(valid), 'ack');
    assert.deepEqual(inserted, [{ userId: 20, numberOfItems: 99, totalAmount: 250 }]);
  });

  it('drops an unparseable or invalid message without touching the database', async () => {
    const handle = handlerWith(async () => assert.fail('must not insert'));
    assert.equal(await handle(Buffer.from('{not json')), 'drop');
    assert.equal(await handle(Buffer.from('{"user_id":-1,"number_of_items":1,"total_amount":1}')), 'drop');
  });

  it('requeues on a transient database failure', async () => {
    const handle = handlerWith(async () => {
      throw Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' });
    });
    assert.equal(await handle(valid), 'requeue');
  });

  it('drops a message the database rejects permanently', async () => {
    const handle = handlerWith(async () => {
      throw Object.assign(new Error('check constraint violated'), { code: '23514' });
    });
    assert.equal(await handle(valid), 'drop');
  });
});
