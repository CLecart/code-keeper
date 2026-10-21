import assert from 'node:assert/strict';
import { test } from 'node:test';
import { validateBillingPayload } from '../src/routes/billing.js';

test('accepts the audit payload made of numeric strings', () => {
  assert.equal(validateBillingPayload({ user_id: '20', number_of_items: '99', total_amount: '250' }), null);
});

test('accepts plain numbers and ignores extra fields', () => {
  assert.equal(validateBillingPayload({ user_id: 20, number_of_items: 0, total_amount: 12.5, note: 'x' }), null);
});

test('rejects bodies that are not JSON objects', () => {
  for (const body of [undefined, null, 'text', 42, ['user_id']]) {
    assert.equal(validateBillingPayload(body), 'Body must be a JSON object');
  }
});

test('lists every missing or non-numeric field', () => {
  assert.equal(
    validateBillingPayload({ user_id: '20', number_of_items: 'many' }),
    'Missing or non-numeric field(s): number_of_items, total_amount',
  );
});

test('rejects empty strings and non-finite numbers', () => {
  for (const value of ['', '  ', NaN, Infinity, '1e999', true, {}]) {
    assert.equal(
      validateBillingPayload({ user_id: value, number_of_items: '1', total_amount: '1' }),
      'Missing or non-numeric field(s): user_id',
    );
  }
});
