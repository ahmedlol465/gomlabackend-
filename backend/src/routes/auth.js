const express = require('express');
const jwt = require('jsonwebtoken');
const { db, save, uuid } = require('../db');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'maksab-dev-secret';
const MOCK_OTP = '123456';

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'missing_token' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch { return res.status(401).json({ error: 'invalid_token' }); }
}

// POST /auth/request-otp {phone} -> mock SMS
router.post('/request-otp', (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'phone_required' });
  db.otp[phone] = MOCK_OTP;
  save();
  res.json({ ok: true, hint: 'dev OTP is 123456 (replace with SMS provider)' });
});

// POST /auth/verify-otp {phone, otp, name?, role?}
router.post('/verify-otp', (req, res) => {
  const { phone, otp, name, role } = req.body || {};
  if (db.otp[phone] !== otp && otp !== MOCK_OTP) return res.status(400).json({ error: 'invalid_otp' });
  let user = db.users.find((u) => u.phone === phone);
  if (!user) {
    user = {
      id: uuid(), phone, name: name || 'تاجر', role: role || 'retailer',
      kycStatus: 'pending', points: 0, creditLimit: 5000,
      location: null, createdAt: new Date().toISOString(),
    };
    db.users.push(user);
  }
  save();
  const token = jwt.sign({ id: user.id, phone: user.phone, role: user.role }, JWT_SECRET, { expiresIn: '30d' });
  res.json({ token, user });
});

// POST /kyc (auth) {taxId, commercialRegister, shopName, lat, lng}
router.post('/kyc', auth, (req, res) => {
  const user = db.users.find((u) => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'no_user' });
  const { taxId, commercialRegister, shopName, lat, lng } = req.body || {};
  Object.assign(user, { shopName, taxId, commercialRegister, kycStatus: 'under_review', location: { lat, lng } });
  save();
  res.json({ ok: true, kycStatus: user.kycStatus });
});

router.get('/me', auth, (req, res) => {
  const user = db.users.find((u) => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'no_user' });
  const orders = db.orders.filter((o) => o.userId === user.id);
  const orderCount = orders.length;
  res.json({
    ...user,
    stats: { orderCount, aov: orderCount ? Math.round(orders.reduce((s, o) => s + o.total, 0) / orderCount) : 0 },
    goals: [
      { id: 'g1', title: 'اطلب 5 مرات هذا الأسبوع', progress: Math.min(orderCount % 5, 5), target: 5, reward: '100 نقطة' },
    ],
  });
});

module.exports = { router, auth, JWT_SECRET };
