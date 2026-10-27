// VITALORA — serveur web minimal (Node.js + Express + MySQL)
// Le brief est clair : l'interface n'est pas l'objectif du projet, ce fichier
// reste volontairement simple. Il sert surtout à valider que la chaîne
// ALB -> EC2 -> RDS fonctionne de bout en bout (Phases 1 et 2 du roadmap).

const express = require("express");
const mysql = require("mysql2/promise");

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;

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

app.get("/", (req, res) => {
  res.send(
    "<h1>VITALORA</h1><p>Boutique en ligne de compléments alimentaires.</p>" +
      '<p>Catalogue : <a href="/products">/products</a></p>'
  );
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

// POST /orders { customer_email, items: [{ product_id, qty }] }
app.post("/orders", async (req, res) => {
  const { customer_email, items } = req.body || {};
  if (!customer_email || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: "invalid_order" });
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [orderResult] = await conn.query(
      "INSERT INTO orders (customer_email, status) VALUES (?, 'received')",
      [customer_email]
    );
    const orderId = orderResult.insertId;

    for (const item of items) {
      const [[product]] = await conn.query("SELECT price_cents FROM products WHERE product_id = ?", [
        item.product_id,
      ]);
      if (!product) throw new Error(`product_not_found:${item.product_id}`);

      await conn.query(
        "INSERT INTO order_items (order_id, product_id, qty, unit_price_cents) VALUES (?, ?, ?, ?)",
        [orderId, item.product_id, item.qty, product.price_cents]
      );
    }

    await conn.commit();

    // TODO (Phase 4, Personne C) : publier sur SNS pour déclencher la
    // confirmation client + le traitement interne (emballage/expédition).
    // L'IAM du rôle EC2 autorise déjà sns:Publish sur `${project_name}-*`,
    // il suffira d'ajouter l'appel SDK ici une fois le topic créé.

    res.status(201).json({ order_id: orderId, status: "received" });
  } catch (err) {
    await conn.rollback();
    console.error("POST /orders failed:", err.message);
    res.status(500).json({ error: "order_failed" });
  } finally {
    conn.release();
  }
});

app.listen(PORT, () => {
  console.log(`VITALORA web server listening on port ${PORT}`);
});
