// VITALORA — front minimal (vanilla JS, pas de framework : le brief ne
// demande pas de soigner l'UI, juste de démontrer le parcours catalogue ->
// commande -> confirmation).

let assetsBaseUrl = null;
let products = [];
let cart = []; // [{ product, qty }] — en mémoire, pas de persistance volontaire

const catalogEl = document.getElementById("catalog");
const tabsEl = document.getElementById("category-tabs");
const cartToggleEl = document.getElementById("cart-toggle");
const cartPanelEl = document.getElementById("cart-panel");
const cartCloseEl = document.getElementById("cart-close");
const cartCountEl = document.getElementById("cart-count");
const cartItemsEl = document.getElementById("cart-items");
const cartTotalEl = document.getElementById("cart-total");
const orderFormEl = document.getElementById("order-form");
const orderFeedbackEl = document.getElementById("order-feedback");
const submitOrderEl = document.getElementById("submit-order");
const confirmationEl = document.getElementById("confirmation");
const confirmOrderIdEl = document.getElementById("confirm-order-id");
const confirmTotalEl = document.getElementById("confirm-total");
const confirmationCloseEl = document.getElementById("confirmation-close");

function formatPrice(cents) {
  return (cents / 100).toLocaleString("fr-FR", { minimumFractionDigits: 2 }) + " €";
}

function productImageMarkup(product) {
  if (assetsBaseUrl && product.image_key) {
    const url = `${assetsBaseUrl}/${product.image_key}`;
    const initial = product.name.charAt(0).toUpperCase();
    // onerror : si l'image n'existe pas encore dans le bucket, on retombe
    // sur un bloc coloré avec l'initiale plutôt qu'une icône cassée.
    return (
      `<img class="product-image" src="${url}" alt="${product.name}" ` +
      `onerror="this.outerHTML='<div class=&quot;product-image-placeholder&quot;>${initial}</div>'" />`
    );
  }
  const initial = product.name.charAt(0).toUpperCase();
  return `<div class="product-image-placeholder">${initial}</div>`;
}

function renderCatalog(list) {
  if (list.length === 0) {
    catalogEl.innerHTML = '<p class="empty-state">Aucun produit dans cette catégorie.</p>';
    return;
  }

  catalogEl.innerHTML = list
    .map((p) => {
      const outOfStock = p.stock_qty <= 0;
      return `
        <article class="product-card" data-product-id="${p.product_id}">
          ${productImageMarkup(p)}
          <p class="product-name">${p.name}</p>
          <p class="product-desc">${p.description || ""}</p>
          <div class="product-footer">
            <span class="product-price">${formatPrice(p.price_cents)}</span>
            <span class="product-stock">${outOfStock ? "Rupture" : p.stock_qty + " en stock"}</span>
          </div>
          <button class="add-to-cart" data-product-id="${p.product_id}" ${outOfStock ? "disabled" : ""}>
            Ajouter au panier
          </button>
        </article>`;
    })
    .join("");
}

async function loadConfig() {
  try {
    const res = await fetch("/config");
    const data = await res.json();
    assetsBaseUrl = data.assetsBaseUrl;
  } catch (err) {
    // Pas bloquant : les produits s'affichent avec le placeholder coloré.
    console.warn("Config indisponible, images en placeholder.", err);
  }
}

async function loadProducts(category) {
  catalogEl.innerHTML = '<p class="loading">Chargement du catalogue…</p>';
  try {
    const url = category ? `/products?category=${encodeURIComponent(category)}` : "/products";
    const res = await fetch(url);
    if (!res.ok) throw new Error("http_" + res.status);
    products = await res.json();
    renderCatalog(products);
  } catch (err) {
    catalogEl.innerHTML = '<p class="error-state">Catalogue indisponible pour le moment. Réessaie dans un instant.</p>';
    console.error("loadProducts failed:", err);
  }
}

function renderCart() {
  cartCountEl.textContent = cart.reduce((sum, line) => sum + line.qty, 0);

  if (cart.length === 0) {
    cartItemsEl.innerHTML = '<p class="empty-state">Panier vide.</p>';
    cartTotalEl.textContent = formatPrice(0);
    submitOrderEl.disabled = true;
    return;
  }

  cartItemsEl.innerHTML = cart
    .map(
      (line, index) => `
        <div class="cart-line">
          <span>${line.product.name} × ${line.qty}</span>
          <span>${formatPrice(line.product.price_cents * line.qty)}</span>
          <button type="button" class="remove-line" data-index="${index}" aria-label="Retirer">×</button>
        </div>`
    )
    .join("");

  const total = cart.reduce((sum, line) => sum + line.product.price_cents * line.qty, 0);
  cartTotalEl.textContent = formatPrice(total);
  submitOrderEl.disabled = false;
}

function addToCart(productId) {
  const product = products.find((p) => p.product_id === productId);
  if (!product) return;

  const existing = cart.find((line) => line.product.product_id === productId);
  if (existing) {
    existing.qty += 1;
  } else {
    cart.push({ product, qty: 1 });
  }
  renderCart();
  cartPanelEl.classList.remove("hidden");
}

function removeFromCart(index) {
  cart.splice(index, 1);
  renderCart();
}

// --- Événements catalogue ---------------------------------------------

catalogEl.addEventListener("click", (event) => {
  const button = event.target.closest(".add-to-cart");
  if (!button) return;
  addToCart(Number(button.dataset.productId));
});

tabsEl.addEventListener("click", (event) => {
  const tab = event.target.closest(".tab");
  if (!tab) return;
  tabsEl.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
  tab.classList.add("active");
  loadProducts(tab.dataset.category || undefined);
});

// --- Événements panier ---------------------------------------------

cartToggleEl.addEventListener("click", () => cartPanelEl.classList.toggle("hidden"));
cartCloseEl.addEventListener("click", () => cartPanelEl.classList.add("hidden"));

cartItemsEl.addEventListener("click", (event) => {
  const button = event.target.closest(".remove-line");
  if (!button) return;
  removeFromCart(Number(button.dataset.index));
});

// --- Soumission de commande ---------------------------------------------

orderFormEl.addEventListener("submit", async (event) => {
  event.preventDefault();
  orderFeedbackEl.textContent = "";
  orderFeedbackEl.classList.remove("error");

  if (cart.length === 0) return;

  const customerEmail = document.getElementById("customer-email").value.trim();
  const payload = {
    customer_email: customerEmail,
    items: cart.map((line) => ({ product_id: line.product.product_id, qty: line.qty })),
  };

  submitOrderEl.disabled = true;
  submitOrderEl.textContent = "Envoi en cours…";

  try {
    const res = await fetch("/orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json();

    if (!res.ok) {
      throw new Error(data.error || "order_failed");
    }

    const total = cart.reduce((sum, line) => sum + line.product.price_cents * line.qty, 0);
    confirmOrderIdEl.textContent = "#" + data.order_id;
    confirmTotalEl.textContent = "Total : " + formatPrice(total);
    confirmationEl.classList.remove("hidden");

    cart = [];
    renderCart();
    cartPanelEl.classList.add("hidden");
    orderFormEl.reset();
    loadProducts(); // rafraîchit les stocks affichés
  } catch (err) {
    orderFeedbackEl.textContent = orderErrorMessage(err.message);
    orderFeedbackEl.classList.add("error");
  } finally {
    submitOrderEl.disabled = cart.length === 0;
    submitOrderEl.textContent = "Valider la commande";
  }
});

function orderErrorMessage(code) {
  switch (code) {
    case "invalid_email":
      return "Adresse e-mail invalide.";
    case "empty_cart":
      return "Le panier est vide.";
    case "insufficient_stock":
      return "Stock insuffisant pour un des produits.";
    case "product_not_found":
      return "Un produit du panier n'existe plus.";
    default:
      return "Une erreur est survenue, réessaie.";
  }
}

confirmationCloseEl.addEventListener("click", () => confirmationEl.classList.add("hidden"));

// --- Démarrage ---------------------------------------------

loadConfig().then(() => loadProducts());
renderCart();
