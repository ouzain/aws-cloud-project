let products = [];
let cart = [];
let lastRequest;
let statusTimer;
const byId = (id) => document.getElementById(id);
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const price = (cents) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(cents / 100);
const orderStatusLabel = (status) => ({ received: 'Reçue', confirmed: 'Confirmée',
  processing: 'En préparation', shipped: 'Expédiée' }[status] || 'En attente de mise à jour');

async function loadProducts(category = document.querySelector('.tab.active')?.dataset.category) {
  byId('catalog').innerHTML = '<p class="loading">Chargement des produits…</p>';
  try {
    const response = await fetch(category ? '/products?category=' + encodeURIComponent(category) : '/products');
    if (!response.ok) throw new Error('catalog_unavailable');
    products = await response.json();
    byId('catalog').innerHTML = products.map((p) => `<article class="product-card">
      <img class="product-image" src="${escapeHtml(p.image_url)}" alt="${escapeHtml(p.name)}" />
      <p class="product-name">${escapeHtml(p.name)}</p><p class="product-desc">${escapeHtml(p.description)}</p>
      <div class="product-footer"><span class="product-price">${price(p.price_cents)}</span>
      <span class="product-stock">${p.stock_qty > 0 ? p.stock_qty + ' en stock' : 'Rupture de stock'}</span></div>
      <button class="add-to-cart" data-product-id="${p.product_id}" ${p.stock_qty <= 0 ? 'disabled' : ''}>Ajouter au panier</button>
      </article>`).join('');
  } catch (error) { byId('catalog').innerHTML = '<p class="error-state">Le catalogue est temporairement indisponible. Veuillez réessayer.</p>'; }
}
function renderCart() {
  byId('cart-count').textContent = cart.reduce((n, line) => n + line.qty, 0);
  byId('cart-items').innerHTML = cart.length ? cart.map((line, index) => `<div class="cart-line">
    <span>${escapeHtml(line.product.name)} × ${line.qty}</span><span>${price(line.product.price_cents * line.qty)}</span>
    <button type="button" class="remove-line" data-index="${index}" aria-label="Retirer cet article">×</button></div>`).join('') : '<p class="empty-state">Votre panier est vide.</p>';
  byId('cart-total').textContent = price(cart.reduce((n, line) => n + line.qty * line.product.price_cents, 0));
  byId('submit-order').disabled = !cart.length;
}
byId('catalog').addEventListener('click', (event) => {
  const button = event.target.closest('.add-to-cart');
  if (!button) return;
  const product = products.find((p) => p.product_id === Number(button.dataset.productId));
  const line = cart.find((item) => item.product.product_id === product.product_id);
  if ((line?.qty || 0) >= Math.min(product.stock_qty, 50)) return;
  if (line) line.qty++; else cart.push({ product, qty: 1 });
  renderCart(); byId('cart-panel').classList.remove('hidden');
});
byId('category-tabs').addEventListener('click', (event) => {
  const tab = event.target.closest('.tab');
  if (!tab) return;
  document.querySelectorAll('.tab').forEach((item) => item.classList.remove('active'));
  tab.classList.add('active'); loadProducts(tab.dataset.category);
});
byId('cart-items').addEventListener('click', (event) => {
  const button = event.target.closest('.remove-line');
  if (button) { cart.splice(Number(button.dataset.index), 1); renderCart(); }
});
byId('cart-toggle').onclick = () => byId('cart-panel').classList.toggle('hidden');
byId('cart-close').onclick = () => byId('cart-panel').classList.add('hidden');
byId('confirmation-close').onclick = () => { byId('confirmation').classList.add('hidden'); clearTimeout(statusTimer); };

async function trackOrder(orderId, attempt = 0) {
  try {
    const response = await fetch('/orders/' + orderId);
    if (!response.ok) throw new Error('status_unavailable');
    const order = await response.json();
    byId('confirm-status').textContent = 'Statut de la commande : ' + orderStatusLabel(order.status);
    if (order.status === 'shipped') return;
  } catch (error) { byId('confirm-status').textContent = 'Votre commande est enregistrée. Son statut sera bientôt actualisé.'; }
  if (attempt < 40) statusTimer = setTimeout(() => trackOrder(orderId, attempt + 1), 1500);
}
byId('order-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!cart.length) return;
  const payload = JSON.stringify({ customer_email: byId('customer-email').value.trim(),
    items: cart.map((line) => ({ product_id: line.product.product_id, qty: line.qty })) });
  if (lastRequest?.payload !== payload) lastRequest = { payload,
    key: Array.from(crypto.getRandomValues(new Uint8Array(16)), (n) => n.toString(16).padStart(2, '0')).join('') };
  byId('order-feedback').textContent = '';
  byId('submit-order').disabled = true;
  byId('submit-order').textContent = 'Enregistrement de la commande…';
  try {
    const response = await fetch('/orders', { method: 'POST', headers: {
      'Content-Type': 'application/json', 'Idempotency-Key': lastRequest.key,
    }, body: payload });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    byId('confirm-order-id').textContent = '#' + data.order_id;
    byId('confirm-total').textContent = 'Total : ' + price(data.total_cents);
    byId('confirm-status').textContent = 'Statut de la commande : ' + orderStatusLabel(data.status);
    byId('confirmation').classList.remove('hidden');
    clearTimeout(statusTimer); trackOrder(data.order_id);
    cart = []; lastRequest = null; renderCart();
    byId('cart-panel').classList.add('hidden'); byId('order-form').reset(); loadProducts();
  } catch (error) {
    byId('order-feedback').textContent = error.message === 'insufficient_stock'
      ? 'Le stock est insuffisant pour cette commande.' : 'La commande n’a pas pu être confirmée. Veuillez réessayer.';
    byId('order-feedback').classList.add('error');
  } finally { byId('submit-order').disabled = !cart.length; byId('submit-order').textContent = 'Valider la commande'; }
});
loadProducts(); renderCart();
