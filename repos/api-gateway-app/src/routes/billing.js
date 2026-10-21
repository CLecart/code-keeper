import express from 'express';
import { errorFields } from '../logger.js';

const REQUIRED_FIELDS = ['user_id', 'number_of_items', 'total_amount'];

const isNumeric = (value) =>
  (typeof value === 'number' && Number.isFinite(value)) ||
  (typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value)));

/** Returns null when the payload is acceptable, otherwise the message for the 400 response. */
export function validateBillingPayload(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return 'Body must be a JSON object';
  }
  const invalid = REQUIRED_FIELDS.filter((field) => !isNumeric(body[field]));
  return invalid.length > 0 ? `Missing or non-numeric field(s): ${invalid.join(', ')}` : null;
}

export function createBillingRouter({ queue, logger }) {
  const router = express.Router();

  // The JSON parser is scoped to this router (the proxy needs the raw stream).
  // Any content type is parsed as JSON: clients often post raw JSON without a
  // Content-Type header.
  router.use(express.json({ type: () => true }));

  router.post('/', async (req, res) => {
    const problem = validateBillingPayload(req.body);
    if (problem) {
      res.status(400).json({ error: problem });
      return;
    }
    if (!queue.isConnected()) {
      res.status(503).json({ error: 'Message queue unavailable' });
      return;
    }
    try {
      await queue.publish(req.body);
      res.json({ message: 'Message posted' });
    } catch (err) {
      logger.error('billing message publish failed', errorFields(err));
      res.status(503).json({ error: 'Message queue unavailable' });
    }
  });

  return router;
}
