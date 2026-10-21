import { parseOrderMessage } from './orders.js';

// SQLSTATE classes 22 (data exception) and 23 (integrity constraint violation)
// mean the row itself is unacceptable: redelivering it could never succeed.
const PERMANENT_SQLSTATE_CLASSES = new Set(['22', '23']);

const isPermanentDatabaseError = (err) =>
  typeof err.code === 'string' && PERMANENT_SQLSTATE_CLASSES.has(err.code.slice(0, 2));

// Builds the message handler: maps one delivery to an outcome the queue
// module settles with the broker: 'ack' (stored), 'drop' (invalid, never
// retried) or 'requeue' (transient failure, redelivered later).
export function createOrderHandler({ db, logger }) {
  return async (content) => {
    let order;
    try {
      order = parseOrderMessage(content);
    } catch (err) {
      logger.warn('dropping invalid message', { reason: err.message, preview: content.toString('utf8', 0, 200) });
      return 'drop';
    }

    try {
      const row = await db.insertOrder(order);
      logger.info('order stored', { id: row.id, userId: row.user_id });
      return 'ack';
    } catch (err) {
      if (isPermanentDatabaseError(err)) {
        logger.warn('dropping message rejected by the database', { err });
        return 'drop';
      }
      logger.error('could not store order, will requeue', { err });
      return 'requeue';
    }
  };
}
