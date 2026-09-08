const express = require('express');
const { db, save, uuid } = require('../db');
const { auth } = require('./auth');

const router = express.Router();

// Arabic fuzzy normalization: أإآ->ا, ة->ه, ى->ي (smart search across products/categories/brands)
function norm(s) {
  return (s || '').replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').trim();
}

function enrichOffer(o) {
  const p = db.products.find((x) => x.id === o.productId) || {};
  const w = db.wholesalers.find((x) => x.id === o.wholesalerId) || {};
  return {
    ...o, productName: p.name, category: p.category, brand: p.brand, bulkUnit: p.bulkUnit, unitName: p.unitName,
    description: p.description || '', image: p.image || '',
    bulkQty: p.bulkQty, unitPrice: p.bulkQty ? Math.round((o.bulkPrice / p.bulkQty) * 100) / 100 : null,
    sellingFast: !!p.sellingFast, shortage: (o.stock || 0) < 50,
    discountPct: o.oldPrice ? Math.round((1 - o.bulkPrice / o.oldPrice) * 100) : 0,
    wholesalerName: w.name, wholesalerType: w.type, deliveryEta: w.deliveryEta,
  };
}

// GET /products?search=&category=&source=&hot=1 — cached for offline mode on client
router.get('/products', (req, res) => {
  const { search = '', category = '', source = '', hot = '' } = req.query;
  let offers = db.offers.map(enrichOffer);
  if (category) offers = offers.filter((o) => o.category === category);
  if (source) offers = offers.filter((o) => o.source === source); // direct | marketplace | exclusive
  if (hot === '1') offers = offers.filter((o) => o.oldPrice && o.bulkPrice < o.oldPrice);
  if (search) {
    const q = norm(search);
    offers = offers.filter((o) => norm(`${o.productName} ${o.category} ${o.brand} ${o.wholesalerName}`).includes(q));
  }
  res.json({ items: offers, categories: [...new Set(db.products.map((p) => p.category))] });
});

// GET /orders/buy-again (auth) — distinct products from past orders for "Buy Again"
router.get('/orders/buy-again', auth, (req, res) => {
  const seen = new Set();
  const items = [];
  db.orders.filter((o) => o.userId === req.user.id).reverse().forEach((order) => {
    (order.lines || []).forEach((l) => {
      if (seen.has(l.productId)) return;
      seen.add(l.productId);
      const offer = db.offers.find((o) => o.id === l.offerId);
      if (offer) items.push(enrichOffer(offer));
    });
  });
  res.json({ items: items.slice(0, 10) });
});

// GET /products/:id/offers — wholesaler comparison for same product
router.get('/products/:id/offers', (req, res) => {
  const offers = db.offers.filter((o) => o.productId === req.params.id).map(enrichOffer)
    .sort((a, b) => a.bulkPrice - b.bulkPrice);
  if (!offers.length) return res.status(404).json({ error: 'no_offers' });
  res.json({ product: db.products.find((p) => p.id === req.params.id), offers });
});

router.get('/wholesalers', (req, res) => res.json({ items: db.wholesalers }));

router.get('/wholesalers/:id', (req, res) => {
  const w = db.wholesalers.find((x) => x.id === req.params.id);
  if (!w) return res.status(404).json({ error: 'no_wholesaler' });
  const offers = db.offers.filter((o) => o.wholesalerId === w.id).map(enrichOffer);
  res.json({ ...w, offers });
});

// Best tier for a quantity: biggest discount whose minQty is reached
function tierFor(offer, qty) {
  let best = null;
  for (const t of offer.tiers || []) {
    if (qty >= t.minQty && (!best || t.discountPct > best.discountPct)) best = t;
  }
  return best;
}

// POST /cart/checkout (auth) {items:[{offerId, qty, mode:'bulk'|'piece'}], coupon?}
// mode bulk = carton price, piece = single-unit price; tiers discount by quantity in the same mode
router.post('/cart/checkout', auth, (req, res) => {
  const key = req.headers['idempotency-key'];
  if (key && db.idempotency[key]) return res.json(db.idempotency[key]);

  const { items = [], coupon } = req.body || {};
  if (!items.length) return res.status(400).json({ error: 'empty_cart' });

  let subtotal = 0; // before tier discounts
  let tierSavings = 0;
  const lines = [];
  for (const { offerId, qty, mode } of items) {
    const m = mode === 'piece' ? 'piece' : 'bulk';
    const offer = db.offers.find((o) => o.id === offerId);
    if (!offer) return res.status(400).json({ error: 'bad_offer', offerId });
    const q = Math.max(parseInt(qty) || 0, 0);
    if (!q) return res.status(400).json({ error: 'bad_qty', offerId });
    const p = db.products.find((x) => x.id === offer.productId) || {};
    const bulkQty = p.bulkQty || 1;
    const piecesNeeded = m === 'bulk' ? q * bulkQty : q;
    if ((offer.stock || 0) * bulkQty < piecesNeeded) return res.status(400).json({ error: 'insufficient_stock', offerId });
    const unit = m === 'piece' ? offer.piecePrice : offer.bulkPrice;
    const tier = tierFor(offer, q);
    const disc = tier ? tier.discountPct : 0;
    const lineTotal = Math.round(unit * q * (1 - disc / 100) * 100) / 100;
    subtotal = Math.round((subtotal + unit * q) * 100) / 100;
    tierSavings = Math.round((tierSavings + unit * q * (disc / 100)) * 100) / 100;
    lines.push({ offerId, productId: offer.productId, wholesalerId: offer.wholesalerId, qty: q, mode: m, price: unit, tier: tier || null, lineTotal });
  }

  let discount = 0;
  const afterTiers = subtotal - tierSavings;
  if (coupon) {
    const c = db.coupons.find((x) => x.code === coupon && x.active);
    if (c && afterTiers >= (c.minOrder || 0)) {
      discount = c.discount || Math.round(afterTiers * (c.discountPct || 0) / 100);
    }
  }
  const total = Math.round((afterTiers - discount) * 100) / 100;

  // min order value per wholesaler
  const byWs = {};
  lines.forEach((l) => { (byWs[l.wholesalerId] = byWs[l.wholesalerId] || []).push(l); });
  for (const [wsId, ls] of Object.entries(byWs)) {
    const w = db.wholesalers.find((x) => x.id === wsId);
    const sum = ls.reduce((s, l) => s + l.lineTotal, 0);
    if (w && sum < w.minOrderValue) return res.status(400).json({ error: 'min_order', wholesaler: w.name, min: w.minOrderValue });
  }

  lines.forEach((l) => {
    const o = db.offers.find((x) => x.id === l.offerId);
    const p = db.products.find((x) => x.id === o.productId) || {};
    o.stock = Math.round(((o.stock || 0) - l.qty / (l.mode === 'bulk' ? 1 : (p.bulkQty || 1))) * 1000) / 1000;
  });

  const order = {
    id: uuid(), userId: req.user.id, lines, subtotal, tierSavings, discount, total,
    status: 'confirmed', subOrders: Object.entries(byWs).map(([wholesalerId, wsLines]) => ({
      id: uuid(), wholesalerId, lines: wsLines,
      total: Math.round(wsLines.reduce((s, l) => s + l.lineTotal, 0) * 100) / 100, status: 'preparing',
    })),
    createdAt: new Date().toISOString(),
  };
  db.orders.push(order);
  const user = db.users.find((u) => u.id === req.user.id);
  if (user) user.points += Math.floor(total / 100);
  db.notifications.push({ id: uuid(), title: 'تم تأكيد طلبك', body: `طلب ${order.id.slice(0, 8)} بإجمالي ${total} ج.م`, createdAt: new Date().toISOString() });
  save();
  const resp = { ok: true, order };
  if (key) { db.idempotency[key] = resp; save(); }
  res.json(resp);
});

router.get('/orders', auth, (req, res) => {
  res.json({ items: db.orders.filter((o) => o.userId === req.user.id).reverse() });
});

router.get('/coupons', (req, res) => res.json({ items: db.coupons.filter((c) => c.active) }));

router.post('/complaints', auth, (req, res) => {
  const { subject, message } = req.body || {};
  const c = { id: uuid(), userId: req.user.id, subject, message, status: 'open', createdAt: new Date().toISOString() };
  db.complaints.push(c); save();
  res.json({ ok: true, complaint: c });
});

router.get('/complaints', auth, (req, res) => {
  res.json({ items: db.complaints.filter((c) => c.userId === req.user.id) });
});

router.get('/notifications', (req, res) => res.json({ items: db.notifications.slice().reverse().slice(0, 20) }));

module.exports = router;
