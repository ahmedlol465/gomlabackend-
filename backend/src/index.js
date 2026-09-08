const path = require('path');
const express = require('express');
const { load } = require('./db');
const seed = require('./seed');
const { router: authRoutes } = require('./routes/auth');
const marketRoutes = require('./routes/market');
const adminRoutes = require('./routes/admin');

load();
// Seed demo data on first boot (or with --seed); keeps existing data otherwise (hosting-safe)
const fs = require('fs');
if (process.argv.includes('--seed') || !fs.existsSync(path.join(__dirname, '..', 'db.json'))) seed();

const app = express();
app.use(express.json());
const cors = require('cors');
app.use(cors());

app.get('/health', (req, res) => res.json({ ok: true, service: 'babaabdo-backend', time: new Date().toISOString() }));
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1', marketRoutes);
app.use('/api/v1/admin', adminRoutes);
app.get('/admin', (req, res) => res.sendFile(path.join(__dirname, '..', 'public', 'admin.html')));
app.use('/admin', express.static(path.join(__dirname, '..', 'public')));

// Geolocation delivery-zone mock
app.get('/api/v1/zones', (req, res) => {
  const { lat, lng } = req.query;
  res.json({ lat, lng, zone: 'Cairo-East', fee: 25, eta: '24-48h', cod: true });
});

const PORT = process.env.PORT || 3100;
app.listen(PORT, () => console.log(`BabaAbdo backend on http://localhost:${PORT}`));
