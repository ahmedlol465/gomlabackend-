const express = require('express');
const { db, save, uuid } = require('../db');

const router = express.Router();
const ADMIN_KEY = process.env.ADMIN_KEY || 'admin123';

function guard(req, res, next) {
  if (req.headers['x-admin-key'] !== ADMIN_KEY) return res.status(403).json({ error: 'forbidden' });
  next();
}
router.use(guard);

router.get('/overview', (req, res) => {
  const revenue = db.orders.reduce((s, o) => s + (o.total || 0), 0);
  res.json({
    products: db.products.length, offers: db.offers.length,
    orders: db.orders.length, users: db.users.length,
    revenue: Math.round(revenue * 100) / 100,
    complaints: db.complaints.filter((c) => c.status === 'open').length,
  });
});

function crud(path, table, idField = 'id') {
  router.get(`/${path}`, (req, res) => res.json({ items: db[table] }));
  router.post(`/${path}`, (req, res) => {
    const item = { id: req.body.id || uuid(), ...req.body };
    db[table].push(item);
    save();
    res.json({ ok: true, item });
  });
  router.put(`/${path}/:id`, (req, res) => {
    const item = db[table].find((x) => x[idField] === req.params.id);
    if (!item) return res.status(404).json({ error: 'not_found' });
    Object.assign(item, req.body, { [idField]: req.params.id });
    save();
    res.json({ ok: true, item });
  });
  router.delete(`/${path}/:id`, (req, res) => {
    const i = db[table].findIndex((x) => x[idField] === req.params.id);
    if (i < 0) return res.status(404).json({ error: 'not_found' });
    const [gone] = db[table].splice(i, 1);
    if (table === 'products') db.offers = db.offers.filter((o) => o.productId !== gone.id);
    save();
    res.json({ ok: true });
  });
}

crud('products', 'products');
crud('offers', 'offers');
crud('wholesalers', 'wholesalers');
crud('coupons', 'coupons');

router.get('/orders', (req, res) => {
  res.json({ items: db.orders.slice().reverse() });
});
router.patch('/orders/:id', (req, res) => {
  const o = db.orders.find((x) => x.id === req.params.id);
  if (!o) return res.status(404).json({ error: 'not_found' });
  if (req.body.status) o.status = req.body.status;
  save();
  res.json({ ok: true, order: o });
});

router.get('/users', (req, res) => res.json({ items: db.users }));
router.patch('/users/:id', (req, res) => {
  const u = db.users.find((x) => x.id === req.params.id);
  if (!u) return res.status(404).json({ error: 'not_found' });
  if (req.body.kycStatus) u.kycStatus = req.body.kycStatus;
  save();
  res.json({ ok: true, user: u });
});

router.get('/complaints', (req, res) => res.json({ items: db.complaints }));
router.patch('/complaints/:id', (req, res) => {
  const c = db.complaints.find((x) => x.id === req.params.id);
  if (!c) return res.status(404).json({ error: 'not_found' });
  if (req.body.status) c.status = req.body.status;
  save();
  res.json({ ok: true, complaint: c });
});

module.exports = router;
