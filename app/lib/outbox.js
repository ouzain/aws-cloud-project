async function publishPendingEvents(pool, publish) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [events] = await conn.query(`SELECT event_id, payload FROM outbox
      WHERE published_at IS NULL ORDER BY created_at LIMIT 5 FOR UPDATE SKIP LOCKED`);
    for (const row of events) {
      await publish(typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload);
      await conn.query('UPDATE outbox SET published_at = CURRENT_TIMESTAMP WHERE event_id = ?', [row.event_id]);
    }
    await conn.commit();
  } catch (error) { await conn.rollback().catch(() => {}); throw error; }
  finally { conn.release(); }
}
module.exports = { publishPendingEvents };
