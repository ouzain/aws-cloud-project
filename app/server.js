const path = require('node:path');
const express = require('express');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { createPool, initializeDatabase } = require('./lib/database');
const { createOrder, getOrder, normalizeOrder } = require('./lib/orders');
const { publishPendingEvents } = require('./lib/outbox');
const { log } = require('../shared/events');

function createApp({ pool, signImage }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '32kb' }));
  app.use(express.static(path.join(__dirname, 'public')));
  const route = (handler) => (req, res, next) => Promise.resolve(handler(req, res)).catch(next);
  app.get('/health', (_req, res) => res.json({ status: 'ok' }));
  app.get('/ready', route(async (_req, res) => {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  }));
  app.get('/products', route(async (req, res) => {
    const [rows] = req.query.category
      ? await pool.query('SELECT * FROM products WHERE category = ? ORDER BY product_id', [req.query.category])
      : await pool.query('SELECT * FROM products ORDER BY product_id');
    res.json(await Promise.all(rows.map(async (product) => ({ ...product, image_url: await signImage(product.image_key) }))));
  }));
  app.get('/products/:id', route(async (req, res) => {
    const [[product]] = await pool.query('SELECT * FROM products WHERE product_id = ?', [req.params.id]);
    if (!product) return res.status(404).json({ error: 'not_found' });
    res.json({ ...product, image_url: await signImage(product.image_key) });
  }));
  app.post('/orders', route(async (req, res) => {
    const order = await createOrder(pool, normalizeOrder(req.body), req.get('Idempotency-Key'));
    log('order_created', { orderId: order.order_id, status: order.status });
    res.status(201).json(order);
  }));
  app.get('/orders/:id', route(async (req, res) => {
    const order = await getOrder(pool, req.params.id);
    if (!order) return res.status(404).json({ error: 'not_found' });
    res.json(order);
  }));
  app.use((error, _req, res, _next) => {
    const status = error.httpStatus || (error.type === 'entity.parse.failed' ? 400 : 503);
    const code = error.httpStatus ? error.code : status === 400 ? 'invalid_json' : 'service_unavailable';
    log('request_failed', { code, error: error.message }, true);
    res.status(status).json({ error: code });
  });
  return app;
}

async function main() {
  const pool = createPool();
  await initializeDatabase(pool);
  const region = process.env.AWS_REGION;
  const sns = new SNSClient({ region, maxAttempts: 3 });
  const s3 = new S3Client({ region });
  const app = createApp({ pool, signImage: (key) => getSignedUrl(s3, new GetObjectCommand({
    Bucket: process.env.ASSETS_BUCKET, Key: key,
  }), { expiresIn: 3600 }) });
  let publishing = false;
  async function flush() {
    if (publishing) return;
    publishing = true;
    try {
      await publishPendingEvents(pool, async (event) => {
        const result = await sns.send(new PublishCommand({
          TopicArn: process.env.ORDER_TOPIC_ARN,
          Subject: `VITALORA : commande n°${event.order_id} reçue`,
          Message: JSON.stringify(event),
          MessageAttributes: { eventType: { DataType: 'String', StringValue: event.event_type } },
        }));
        log('order_published', { orderId: event.order_id, eventId: event.event_id, messageId: result.MessageId });
      });
    } catch (error) { log('outbox_publish_failed', { error: error.message }, true); }
    finally { publishing = false; }
  }
  const timer = setInterval(flush, 2000);
  const server = app.listen(process.env.PORT || 3000, () => log('server_started'));
  flush();
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => {
    clearInterval(timer);
    server.close(() => pool.end().finally(() => process.exit(0)));
  });
}
if (require.main === module) main().catch((error) => { log('startup_failed', { error: error.message }, true); process.exitCode = 1; });
module.exports = { createApp };
