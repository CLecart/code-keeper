import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createLogger } from '../src/logger.js';

function capture() {
  const lines = [];
  return { lines, stream: { write: (chunk) => lines.push(chunk) } };
}

describe('createLogger', () => {
  it('writes one JSON line with time, level, msg and extra fields', () => {
    const { lines, stream } = capture();
    createLogger(stream).info('hello', { port: 8080 });
    assert.equal(lines.length, 1);
    assert.ok(lines[0].endsWith('\n'));
    const entry = JSON.parse(lines[0]);
    assert.equal(entry.level, 'info');
    assert.equal(entry.msg, 'hello');
    assert.equal(entry.port, 8080);
    assert.ok(!Number.isNaN(Date.parse(entry.time)));
  });

  it('serialises errors as name, message and code without a stack trace', () => {
    const { lines, stream } = capture();
    const err = Object.assign(new Error('refused'), { code: 'ECONNREFUSED' });
    createLogger(stream).error('boom', { err });
    const entry = JSON.parse(lines[0]);
    assert.equal(entry.level, 'error');
    assert.deepEqual(entry.err, { name: 'Error', message: 'refused', code: 'ECONNREFUSED' });
    assert.ok(!lines[0].includes('at '));
  });
});
