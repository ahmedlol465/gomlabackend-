const express = require('express');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { db, save, uuid } = require('../db');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'maksab-dev-secret';
const ADMIN_USER = 'admin';
const ADMIN_PASS_HASH_KEY = process.env.ADMIN_KEY || 'admin123';

function hashPass(pw) {
  return crypto.createHash('sha256').update(pw + ADMIN_PASS_HASH_KEY).digest('hex');
}

function initAdmin() {
  if (!db.admin) db.admin = { username: 'admin', passwordHash: hashPass(ADMIN_PASS_HASH_KEY) };
  if (!db.admin.passwordHash) db.admin.passwordHash = hashPass(ADMIN_PASS_HASH_KEY);
  save();
}

function adminGuard(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'unauthorized' });
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    if (decoded.role !== 'admin') return res.status(403).json({ error: 'forbidden' });
    req.admin = decoded;
    next();
  } catch { return res.status(401).json({ error: 'invalid_token' }); }
}

router.post('/login', (req, res) => {
  initAdmin();
  const { username, password } = req.body || {};
  if (username !== ADMIN_USER || hashPass(password || '') !== db.admin.passwordHash) {
    return res.status(401).json({ error: 'wrong_credentials' });
  }
  const token = jwt.sign({ role: 'admin', username: ADMIN_USER }, JWT_SECRET, { expiresIn: '7d' });
  res.json({ ok: true, token });
});

router.post('/change-password', adminGuard, (req, res) => {
  initAdmin();
  const { currentPassword, newPassword } = req.body || {};
  if (hashPass(currentPassword || '') !== db.admin.passwordHash) {
    return res.status(400).json({ error: 'wrong_current_password' });
  }
  if (!newPassword || newPassword.length < 6) {
    return res.status(400).json({ error: 'password_too_short' });
  }
  db.admin.passwordHash = hashPass(newPassword);
  save();
  const token = jwt.sign({ role: 'admin', username: ADMIN_USER }, JWT_SECRET, { expiresIn: '7d' });
  res.json({ ok: true, token });
});

router.use(adminGuard);

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
router.delete('/users/:id', (req, res) => {
  const i = db.users.findIndex((x) => x.id === req.params.id);
  if (i < 0) return res.status(404).json({ error: 'not_found' });
  db.users.splice(i, 1);
  save();
  res.json({ ok: true });
});

router.get('/complaints', (req, res) => res.json({ items: db.complaints.slice().reverse() }));
router.patch('/complaints/:id', (req, res) => {
  const c = db.complaints.find((x) => x.id === req.params.id);
  if (!c) return res.status(404).json({ error: 'not_found' });
  if (req.body.status) c.status = req.body.status;
  if (req.body.adminReply) { c.adminReply = req.body.adminReply; c.repliedAt = new Date().toISOString(); }
  save();
  res.json({ ok: true, complaint: c });
});

module.exports = router;
