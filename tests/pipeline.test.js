const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createApp } = require('../app/server');
const { normalizeOrder, createOrder } = require('../app/lib/orders');
const { publishPendingEvents } = require('../app/lib/outbox');
const { orderCreated, validateEvent } = require('../shared/events');
const { createHandler } = require('../modules/messaging/lambda/order-processor');

const payload = { customer_email: 'demo@example.com', items: [{ product_id: 1, qty: 2 }] };
const event = () => orderCreated({ ...payload, order_id: 1, total_cents: 2980 });
const record = (body, messageId = 'message-1') => ({ messageId, body: JSON.stringify(body) });

function workerDatabase(failTarget) {
  const state = { status: 'received', history: [] };
  let snapshot;
  const conn = {
    async beginTransaction() { snapshot = structuredClone(state); },
    async query(sql, values) {
      if (sql.startsWith('SELECT status')) return [[{ status: state.status }]];
      if (sql.startsWith('UPDATE orders')) {
        if (values[0] === failTarget) { failTarget = null; throw new Error('temporary_database_failure'); }
        state.status = values[0];
      }
      if (sql.startsWith('INSERT IGNORE') && !state.history.includes(values[1])) state.history.push(values[1]);
      return [{}];
    },
    async commit() {},
    async rollback() { Object.assign(state, snapshot); },
    release() {},
  };
  return { state, getConnection: async () => conn };
}

test("le catalogue contient dix produits et les images de chaque catégorie", () => {
  const products = require('../catalog/products.json');
  assert.equal(products.length, 40);
  const counts = {};
  for (const product of products) {
    counts[product.category] = (counts[product.category] || 0) + 1;
    assert.match(fs.readFileSync(path.join(__dirname, '../assets', product.image_key), 'utf8'), /<svg/);
  }
  assert.deepEqual(Object.values(counts), [10, 10, 10, 10]);
});
test("le panier regroupe les doublons et verrouille les produits dans un ordre stable", () => {
  const result = normalizeOrder({ customer_email: 'DEMO@example.com', items: [
    { product_id: 2, qty: 1 }, { product_id: 1, qty: 2 }, { product_id: 1, qty: 3 },
  ] });
  assert.deepEqual(result.items, [{ product_id: 1, qty: 5 }, { product_id: 2, qty: 1 }]);
  assert.equal(result.customer_email, 'demo@example.com');
  assert.throws(() => normalizeOrder({ ...payload, items: [{ product_id: 1, qty: true }] }), /invalid_quantity/);
  assert.throws(() => normalizeOrder({ ...payload, items: [{ product_id: 1, qty: 30 }, { product_id: 1, qty: 30 }] }), /invalid_quantity/);
});
test("les erreurs de connexion à la base sont prises en charge", async () => {
  await assert.rejects(createOrder({ getConnection: async () => { throw new Error('unavailable'); } }, payload), /unavailable/);
});
test("l’API renvoie une erreur 503 contrôlée si la base est indisponible", async () => {
  const app = createApp({ pool: { getConnection: async () => { throw new Error('unavailable'); } }, signImage: async () => '' });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/orders`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'service_unavailable' });
  } finally { await new Promise((resolve) => server.close(resolve)); }
});
test("un événement invalide ne peut pas être considéré comme une commande traitée", () => {
  assert.throws(() => validateEvent({}), /invalid_order_event/);
  assert.throws(() => validateEvent({ ...event(), items: [] }), /invalid_order_event/);
});
test("le traitement enregistre les transitions et ignore les doublons", async () => {
  const database = workerDatabase();
  const logs = [];
  const handler = createHandler({ database, sleep: async () => {}, logger: (name) => logs.push(name) });
  const message = record(event());
  assert.deepEqual(await handler({ Records: [message] }), { batchItemFailures: [] });
  assert.equal(database.state.status, 'shipped');
  assert.deepEqual(database.state.history, ['confirmed', 'processing', 'shipped']);
  assert.deepEqual(logs, ['customer_confirmation', 'internal_notification', 'processing_completed']);
  await handler({ Records: [message] });
  assert.equal(database.state.history.length, 3);
  assert.equal(logs.at(-1), 'duplicate_delivery_skipped');
});
test("le traitement reprend une commande partielle sans perdre l’état validé", async () => {
  const database = workerDatabase('processing');
  const handler = createHandler({ database, sleep: async () => {}, logger: () => {} });
  const message = record(event());
  assert.deepEqual(await handler({ Records: [message] }), { batchItemFailures: [{ itemIdentifier: 'message-1' }] });
  assert.equal(database.state.status, 'confirmed');
  assert.deepEqual(await handler({ Records: [message] }), { batchItemFailures: [] });
  assert.deepEqual(database.state.history, ['confirmed', 'processing', 'shipped']);
});
test("les messages invalides échouent seuls et les messages valides aboutissent", async () => {
  const database = workerDatabase();
  const handler = createHandler({ database, sleep: async () => {}, logger: () => {} });
  const result = await handler({ Records: [{ messageId: 'invalid', body: 'not-json' }, record(event())] });
  assert.deepEqual(result.batchItemFailures, [{ itemIdentifier: 'invalid' }]);
  assert.equal(database.state.status, 'shipped');
});
test("la boîte d’envoi conserve l’événement après un échec SNS et le marque après succès", async () => {
  let pending = true;
  let snapshot;
  const conn = {
    async beginTransaction() { snapshot = pending; },
    async query(sql) {
      if (sql.startsWith('SELECT')) return [pending ? [{ event_id: 'event', payload: event() }] : []];
      pending = false; return [{}];
    },
    async commit() {}, async rollback() { pending = snapshot; }, release() {},
  };
  const database = { getConnection: async () => conn };
  await assert.rejects(publishPendingEvents(database, async () => { throw new Error('sns_unavailable'); }), /sns_unavailable/);
  assert.equal(pending, true);
  let delivered = 0;
  await publishPendingEvents(database, async () => { delivered++; });
  assert.equal(pending, false);
  await publishPendingEvents(database, async () => { delivered++; });
  assert.equal(delivered, 1);
});
