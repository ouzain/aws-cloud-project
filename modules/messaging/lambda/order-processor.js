const { createPool } = require('../../../app/lib/database');
const { validateEvent, log } = require('../../../shared/events');
let pool;
async function transition(database, orderId, allowed, target) {
  const conn = await database.getConnection();
  try {
    await conn.beginTransaction();
    const [[order]] = await conn.query('SELECT status FROM orders WHERE order_id = ? FOR UPDATE', [orderId]);
    if (!order) throw new Error('order_not_found');
    if (!allowed.includes(order.status)) { await conn.commit(); return false; }
    await conn.query('UPDATE orders SET status = ? WHERE order_id = ?', [target, orderId]);
    await conn.query('INSERT IGNORE INTO order_status_history (order_id, status) VALUES (?, ?)', [orderId, target]);
    await conn.commit(); return true;
  } catch (error) { await conn.rollback().catch(() => {}); throw error; }
  finally { conn.release(); }
}
function createHandler({ database, sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)), logger = log }) {
  return async (event) => {
    const batchItemFailures = [];
    for (const record of event.Records) {
      try {
        const order = validateEvent(JSON.parse(record.body));
        const details = { orderId: order.order_id, eventId: order.event_id };
        if (await transition(database, order.order_id, ['received'], 'confirmed')) logger('customer_confirmation', { ...details, status: 'confirmed' });
        if (await transition(database, order.order_id, ['confirmed'], 'processing')) logger('internal_notification', { ...details, status: 'processing' });
        await sleep(1500);
        if (await transition(database, order.order_id, ['processing'], 'shipped')) logger('processing_completed', { ...details, status: 'shipped' });
        else logger('duplicate_delivery_skipped', details);
      } catch (error) {
        logger('order_pipeline_error', { messageId: record.messageId, error: error.message }, true);
        batchItemFailures.push({ itemIdentifier: record.messageId });
      }
    }
    return { batchItemFailures };
  };
}
exports.handler = async (event, context) => {
  context.callbackWaitsForEmptyEventLoop = false;
  pool ||= createPool();
  return createHandler({ database: pool })(event);
};
exports.createHandler = createHandler;
exports.transition = transition;
