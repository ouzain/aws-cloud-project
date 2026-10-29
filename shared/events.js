const { randomUUID } = require('node:crypto');
function orderCreated(order) {
  return { event_id: randomUUID(), event_type: 'order.created', ...order, created_at: new Date().toISOString() };
}
function validateEvent(event) {
  if (!event || event.event_type !== 'order.created' ||
      typeof event.event_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(event.event_id) ||
      !Number.isSafeInteger(event.order_id) || event.order_id <= 0 ||
      !Number.isSafeInteger(event.total_cents) || event.total_cents < 0 ||
      !Array.isArray(event.items) || !event.items.length ||
      event.items.some((item) => !item || !Number.isSafeInteger(item.product_id) || item.product_id <= 0 ||
        !Number.isInteger(item.qty) || item.qty < 1 || item.qty > 50)) throw new Error('invalid_order_event');
  return event;
}
function log(event, details = {}, error = false) {
  (error ? console.error : console.log)(JSON.stringify({ timestamp: new Date().toISOString(), event, ...details }));
}
module.exports = { orderCreated, validateEvent, log };
