// VITALORA — serveur web (Node.js + Express + MySQL)
// Phase 3 du roadmap : catalogue, commandes, front minimal servi en statique.
// Phase 4 : chaque commande créée est publiée sur SNS (fan-out vers SQS).
// Le brief est clair : l'interface n'est pas l'objectif du projet, le front
// (public/) reste volontairement simple — il sert à démontrer le parcours
// catalogue -> commande -> confirmation de bout en bout.

const path = require("path");
const express = require("express");
const mysql = require("mysql2/promise");
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const PORT = process.env.PORT || 3000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const sns = new SNSClient({ region: process.env.AWS_REGION || "eu-west-3" });
const ORDER_TOPIC_ARN = process.env.ORDER_TOPIC_ARN;

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 5,
});

// Utilisé par le health check de l'ALB (target group "/health").
// Ne dépend pas de la base pour rester vert même si RDS redémarre.
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Le front (public/app.js) construit les URLs d'images produits à partir de
// ça plutôt que de coder le bucket en dur côté client.
app.get("/config", (req, res) => {
  const bucket = process.env.ASSETS_BUCKET;
  const region = process.env.AWS_REGION || "eu-west-3";
  res.json({
    assetsBaseUrl: bucket ? `https://${bucket}.s3.${region}.amazonaws.com` : null,
  });
});

app.get("/products", async (req, res) => {
  try {
    const { category } = req.query;
    const [rows] = category
      ? await pool.query("SELECT * FROM products WHERE category = ? ORDER BY name", [category])
      : await pool.query("SELECT * FROM products ORDER BY category, name");
    res.json(rows);
  } catch (err) {
    console.error("GET /products failed:", err.message);
    res.status(500).json({ error: "catalog_unavailable" });
  }
});

app.get("/products/:id", async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT * FROM products WHERE product_id = ?", [req.params.id]);
    if (rows.length === 0) return res.status(404).json({ error: "not_found" });
    res.json(rows[0]);
  } catch (err) {
    console.error("GET /products/:id failed:", err.message);
    res.status(500).json({ error: "catalog_unavailable" });
  }
});

// Publie l'événement "commande créée". Appelé APRÈS le commit : la commande est
// déjà enregistrée, un échec SNS est donc loggé mais ne doit pas la faire échouer.
async function publishOrderCreated(order) {
  if (!ORDER_TOPIC_ARN) {
    console.warn("ORDER_TOPIC_ARN not set, skipping order event for order", order.order_id);
    return;
  }
  try {
    const { MessageId } = await sns.send(
      new PublishCommand({
        TopicArn: ORDER_TOPIC_ARN,
        Subject: `VITALORA - commande #${order.order_id} confirmee`,
        Message: JSON.stringify(order),
        MessageAttributes: { eventType: { DataType: "String", StringValue: "order.created" } },
      })
    );
    console.log(`order ${order.order_id} published to SNS (MessageId ${MessageId})`);
  } catch (err) {
    console.error(`SNS publish failed for order ${order.order_id}:`, err.message);
  }
}

function validateOrderPayload(body) {
  const { customer_email, items } = body || {};

  if (typeof customer_email !== "string" || !EMAIL_RE.test(customer_email)) {
    return "invalid_email";
  }
  if (!Array.isArray(items) || items.length === 0) {
    return "empty_cart";
  }
  for (const item of items) {
    const productId = Number(item && item.product_id);
    const qty = Number(item && item.qty);
    if (!Number.isInteger(productId) || productId <= 0) return "invalid_product_id";
    if (!Number.isInteger(qty) || qty <= 0 || qty > 50) return "invalid_quantity";
  }
  return null;
}

// POST /orders { customer_email, items: [{ product_id, qty }] }
app.post("/orders", async (req, res) => {
  const validationError = validateOrderPayload(req.body);
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  const { customer_email, items } = req.body;
  const conn = await pool.getConnection();

  try {
    await conn.beginTransaction();

    const [orderResult] = await conn.query(
      "INSERT INTO orders (customer_email, status) VALUES (?, 'received')",
      [customer_email]
    );
    const orderId = orderResult.insertId;
    let totalCents = 0;

    for (const item of items) {
      // FOR UPDATE verrouille la ligne le temps de la transaction : deux
      // commandes concurrentes sur le même produit ne peuvent pas lire le
      // même stock et le décrémenter toutes les deux en double.
      const [[product]] = await conn.query(
        "SELECT price_cents, stock_qty FROM products WHERE product_id = ? FOR UPDATE",
        [item.product_id]
      );
      if (!product) {
        throw Object.assign(new Error("product_not_found"), { httpStatus: 400, code: "product_not_found" });
      }
      if (product.stock_qty < item.qty) {
        throw Object.assign(new Error("insufficient_stock"), { httpStatus: 409, code: "insufficient_stock" });
      }

      await conn.query(
        "INSERT INTO order_items (order_id, product_id, qty, unit_price_cents) VALUES (?, ?, ?, ?)",
        [orderId, item.product_id, item.qty, product.price_cents]
      );
      totalCents += item.qty * product.price_cents;
      await conn.query("UPDATE products SET stock_qty = stock_qty - ? WHERE product_id = ?", [
        item.qty,
        item.product_id,
      ]);
    }

    await conn.commit();

    await publishOrderCreated({
      order_id: orderId,
      customer_email,
      items: items.map((it) => ({ product_id: Number(it.product_id), qty: Number(it.qty) })),
      total_cents: totalCents,
      created_at: new Date().toISOString(),
    });

    res.status(201).json({ order_id: orderId, status: "received" });
  } catch (err) {
    await conn.rollback();
    const status = err.httpStatus || 500;
    const code = err.code || "order_failed";
    if (status === 500) console.error("POST /orders failed:", err.message);
    res.status(status).json({ error: code });
  } finally {
    conn.release();
  }
});

// Récupère une commande + ses lignes, pour l'écran de confirmation du front
// et pour le scénario de démo (section "Scénarios de test" du roadmap).
app.get("/orders/:id", async (req, res) => {
  try {
    const [[order]] = await pool.query("SELECT * FROM orders WHERE order_id = ?", [req.params.id]);
    if (!order) return res.status(404).json({ error: "not_found" });

    const [items] = await pool.query(
      `SELECT oi.product_id, p.name, oi.qty, oi.unit_price_cents
       FROM order_items oi
       JOIN products p ON p.product_id = oi.product_id
       WHERE oi.order_id = ?`,
      [req.params.id]
    );

    const total_cents = items.reduce((sum, it) => sum + it.qty * it.unit_price_cents, 0);

    res.json({ ...order, items, total_cents });
  } catch (err) {
    console.error("GET /orders/:id failed:", err.message);
    res.status(500).json({ error: "order_lookup_failed" });
  }
});

app.listen(PORT, () => {
  console.log(`VITALORA web server listening on port ${PORT}`);
});
