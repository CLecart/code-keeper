// Pure parsing and validation of a billing message. No I/O here.

// Bounds of the target columns (INTEGER and NUMERIC(12,2)): a value the
// database can never accept must be rejected up front, not retried forever.
const INT32_MAX = 2147483647;
const MAX_AMOUNT = 9999999999.99;

export class InvalidOrderError extends Error {
  constructor(message) {
    super(message);
    this.name = 'InvalidOrderError';
  }
}

// Accepts numbers and numeric strings (the gateway forwards whatever the
// client sent); anything else, including '' and null, is NaN.
function toNumber(value) {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    return Number(value);
  }
  return NaN;
}

function field(payload, name) {
  if (!Object.hasOwn(payload, name)) {
    throw new InvalidOrderError(`Missing field "${name}"`);
  }
  return toNumber(payload[name]);
}

function integerField(payload, name, min) {
  const value = field(payload, name);
  if (!Number.isInteger(value) || value < min || value > INT32_MAX) {
    throw new InvalidOrderError(`Field "${name}" must be an integer between ${min} and ${INT32_MAX}`);
  }
  return value;
}

function amountField(payload, name) {
  const value = field(payload, name);
  if (!Number.isFinite(value) || value < 0 || value > MAX_AMOUNT) {
    throw new InvalidOrderError(`Field "${name}" must be a number between 0 and ${MAX_AMOUNT}`);
  }
  return value;
}

export function validateOrder(payload) {
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new InvalidOrderError('Message must be a JSON object');
  }
  return {
    userId: integerField(payload, 'user_id', 1),
    numberOfItems: integerField(payload, 'number_of_items', 0),
    totalAmount: amountField(payload, 'total_amount'),
  };
}

export function parseOrderMessage(content) {
  let payload;
  try {
    payload = JSON.parse(content.toString('utf8'));
  } catch (err) {
    throw new InvalidOrderError(`Message is not valid JSON: ${err.message}`);
  }
  return validateOrder(payload);
}
