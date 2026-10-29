const { createHash } = require('node:crypto');
const { orderCreated } = require('../../shared/events');
function fail(code, httpStatus = 400) { return Object.assign(new Error(code), { code, httpStatus }); }
function normalizeOrder(body) {
  if (!body || typeof body.customer_email !== 'string' || body.customer_email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.customer_email)) throw fail('invalid_email');
  if (!Array.isArray(body.items) || !body.items.length || body.items.length > 40) throw fail('invalid_cart');
  const quantities = new Map();
  for (const item of body.items) {
    if (!item || !Number.isSafeInteger(item.product_id) || item.product_id <= 0) throw fail('invalid_product_id');
    if (!Number.isInteger(item.qty) || item.qty < 1 || item.qty > 50) throw fail('invalid_quantity');
    const qty = (quantities.get(item.product_id) || 0) + item.qty;
    if (qty > 50) throw fail('invalid_quantity');
    quantities.set(item.product_id, qty);
  }
  return { customer_email: body.customer_email.toLowerCase(),
    items: [...quantities].sort(([a], [b]) => a - b).map(([product_id, qty]) => ({ product_id, qty })) };
}
async function createOrder(pool, payload, requestId) {
  if (requestId && !/^[a-zA-Z0-9_-]{1,64}$/.test(requestId)) throw fail('invalid_request_id');
  const hash = createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  let conn, transaction = false;
  try {
    conn = await pool.getConnection();
    await conn.beginTransaction(); transaction = true;
    if (requestId) {
      const [[existing]] = await conn.query('SELECT * FROM orders WHERE request_id = ? FOR UPDATE', [requestId]);
      if (existing) {
        if (existing.request_hash !== hash) throw fail('idempotency_conflict', 409);
        await conn.commit(); transaction = false;
        return { order_id: existing.order_id, status: existing.status, total_cents: existing.total_cents };
      }
    }
    const [result] = await conn.query(`INSERT INTO orders (customer_email, status, request_id, request_hash)
      VALUES (?, 'received', ?, ?)`, [payload.customer_email, requestId || null, hash]);
    const orderId = result.insertId;
    let total = 0;
    for (const item of payload.items) {
      // Un ordre de verrouillage stable réduit les interblocages entre commandes simultanées.
      const [[product]] = await conn.query('SELECT price_cents, stock_qty FROM products WHERE product_id = ? FOR UPDATE', [item.product_id]);
      if (!product) throw fail('product_not_found');
      if (product.stock_qty < item.qty) throw fail('insufficient_stock', 409);
      await conn.query('INSERT INTO order_items (order_id, product_id, qty, unit_price_cents) VALUES (?, ?, ?, ?)', [orderId, item.product_id, item.qty, product.price_cents]);
      await conn.query('UPDATE products SET stock_qty = stock_qty - ? WHERE product_id = ?', [item.qty, item.product_id]);
      total += product.price_cents * item.qty;
    }
    await conn.query('UPDATE orders SET total_cents = ? WHERE order_id = ?', [total, orderId]);
    const event = orderCreated({ order_id: orderId, ...payload, total_cents: total });
    await conn.query('INSERT INTO outbox (event_id, order_id, payload) VALUES (?, ?, ?)', [event.event_id, orderId, JSON.stringify(event)]);
    await conn.query("INSERT INTO order_status_history (order_id, status) VALUES (?, 'received')", [orderId]);
    await conn.commit(); transaction = false;
    return { order_id: orderId, status: 'received', total_cents: total };
  } catch (error) {
    if (transaction) await conn.rollback().catch(() => {});
    throw error;
  } finally { conn?.release(); }
}
async function getOrder(pool, orderId) {
  const [[order]] = await pool.query('SELECT order_id, customer_email, status, total_cents, created_at FROM orders WHERE order_id = ?', [orderId]);
  if (!order) return null;
  const [items] = await pool.query(`SELECT oi.product_id, p.name, oi.qty, oi.unit_price_cents
    FROM order_items oi JOIN products p USING (product_id) WHERE oi.order_id = ?`, [orderId]);
  const [history] = await pool.query('SELECT status, created_at FROM order_status_history WHERE order_id = ? ORDER BY id', [orderId]);
  return { ...order, items, history };
}
module.exports = { normalizeOrder, createOrder, getOrder };
