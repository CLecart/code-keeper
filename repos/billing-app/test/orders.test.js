import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { InvalidOrderError, parseOrderMessage, validateOrder } from '../src/orders.js';

const rejects = (payload, pattern) =>
  assert.throws(() => validateOrder(payload), (err) => err instanceof InvalidOrderError && pattern.test(err.message));

describe('validateOrder', () => {
  it('coerces numeric strings as sent by the audit', () => {
    assert.deepEqual(validateOrder({ user_id: '20', number_of_items: '99', total_amount: '250' }), {
      userId: 20,
      numberOfItems: 99,
      totalAmount: 250,
    });
  });

  it('accepts plain numbers, decimal amounts and zero items', () => {
    assert.deepEqual(validateOrder({ user_id: 7, number_of_items: 0, total_amount: 19.99 }), {
      userId: 7,
      numberOfItems: 0,
      totalAmount: 19.99,
    });
  });

  it('ignores extra fields', () => {
    const order = validateOrder({ user_id: 1, number_of_items: 2, total_amount: 3, note: 'ignored' });
    assert.deepEqual(Object.keys(order), ['userId', 'numberOfItems', 'totalAmount']);
  });

  it('rejects missing fields', () => {
    rejects({ number_of_items: 1, total_amount: 1 }, /Missing field "user_id"/);
    rejects({ user_id: 1, total_amount: 1 }, /Missing field "number_of_items"/);
    rejects({ user_id: 1, number_of_items: 1 }, /Missing field "total_amount"/);
  });

  it('rejects negative values', () => {
    rejects({ user_id: -1, number_of_items: 1, total_amount: 1 }, /"user_id"/);
    rejects({ user_id: 1, number_of_items: -1, total_amount: 1 }, /"number_of_items"/);
    rejects({ user_id: 1, number_of_items: 1, total_amount: '-0.01' }, /"total_amount"/);
  });

  it('rejects a zero or fractional user id', () => {
    rejects({ user_id: 0, number_of_items: 1, total_amount: 1 }, /"user_id"/);
    rejects({ user_id: '1.5', number_of_items: 1, total_amount: 1 }, /"user_id"/);
  });

  it('rejects NaN, infinities, empty strings, nulls and booleans', () => {
    rejects({ user_id: 'abc', number_of_items: 1, total_amount: 1 }, /"user_id"/);
    rejects({ user_id: 1, number_of_items: '', total_amount: 1 }, /"number_of_items"/);
    rejects({ user_id: 1, number_of_items: null, total_amount: 1 }, /"number_of_items"/);
    rejects({ user_id: 1, number_of_items: true, total_amount: 1 }, /"number_of_items"/);
    rejects({ user_id: 1, number_of_items: 1, total_amount: 'Infinity' }, /"total_amount"/);
    rejects({ user_id: 1, number_of_items: 1, total_amount: NaN }, /"total_amount"/);
  });

  it('rejects values the database columns cannot hold', () => {
    rejects({ user_id: 2147483648, number_of_items: 1, total_amount: 1 }, /"user_id"/);
    rejects({ user_id: 1, number_of_items: 1, total_amount: 1e10 }, /"total_amount"/);
  });

  it('rejects anything that is not a JSON object', () => {
    for (const payload of [null, [], 'text', 42, true]) {
      rejects(payload, /must be a JSON object/);
    }
  });

  it('does not treat inherited properties as fields', () => {
    rejects({ user_id: 1, number_of_items: 1, constructor: 1 }, /Missing field "total_amount"/);
  });
});

describe('parseOrderMessage', () => {
  it('parses a UTF-8 JSON buffer', () => {
    const content = Buffer.from('{"user_id":"20","number_of_items":"99","total_amount":"250"}');
    assert.deepEqual(parseOrderMessage(content), { userId: 20, numberOfItems: 99, totalAmount: 250 });
  });

  it('rejects malformed JSON', () => {
    assert.throws(() => parseOrderMessage(Buffer.from('not json')), /not valid JSON/);
  });

  it('rejects valid JSON that is not an object', () => {
    assert.throws(() => parseOrderMessage(Buffer.from('[1,2,3]')), /must be a JSON object/);
  });
});
