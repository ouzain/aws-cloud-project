const fs = require('node:fs');
const path = require('node:path');
const mysql = require('mysql2/promise');
function createPool() {
  return mysql.createPool({
    host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER, password: process.env.DB_PASSWORD, database: process.env.DB_NAME,
    connectionLimit: 5, connectTimeout: 10000, waitForConnections: true,
    ssl: process.env.DB_TLS === 'false' ? undefined : {
      ca: fs.readFileSync(path.join(__dirname, '../../certs/global-bundle.pem')), rejectUnauthorized: true,
    },
  });
}
async function initializeDatabase(pool) {
  const conn = await pool.getConnection();
  let locked = false;
  try {
    const [[row]] = await conn.query("SELECT GET_LOCK('vitalora-schema', 120) AS acquired");
    if (row.acquired !== 1) throw new Error('database_initialization_lock_timeout');
    locked = true;
    const schema = fs.readFileSync(path.join(__dirname, '../../sql/schema.sql'), 'utf8');
    for (const statement of schema.split(';').map((part) => part.trim()).filter(Boolean)) await conn.query(statement);
    const [columns] = await conn.query('SHOW COLUMNS FROM orders');
    for (const [name, definition] of [
      ['total_cents', 'INT NOT NULL DEFAULT 0'], ['request_id', 'VARCHAR(64) NULL UNIQUE'], ['request_hash', 'CHAR(64) NULL'],
    ]) if (!columns.some((column) => column.Field === name)) await conn.query(`ALTER TABLE orders ADD COLUMN ${name} ${definition}`);
    await conn.query(`UPDATE orders o SET total_cents = COALESCE(
      (SELECT SUM(qty * unit_price_cents) FROM order_items WHERE order_id = o.order_id), 0)`);
    const products = require('../../catalog/products.json');
    for (const p of products) await conn.query(`INSERT INTO products
      (product_id, name, category, price_cents, stock_qty, description, image_key) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE name = VALUES(name), category = VALUES(category),
      description = VALUES(description), image_key = VALUES(image_key)`,
      [p.product_id, p.name, p.category, p.price_cents, p.stock_qty, p.description, p.image_key]);
  } finally {
    try { if (locked) await conn.query("SELECT RELEASE_LOCK('vitalora-schema')"); }
    finally { conn.release(); }
  }
}
module.exports = { createPool, initializeDatabase };
