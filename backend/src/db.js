// In-memory + JSON-file DB. Swap to Postgres without changing route contracts.
// Tables: users, companies, products, offers, wholesalers, orders, ledger, coupons, goals, complaints, notifications
const fs = require('fs');
const path = require('path');
const { v4: uuid } = require('uuid');

const DB_FILE = path.join(__dirname, '..', 'db.json');

const db = {
  schemaVersion: 1,
  admin: null,
  users: [],
  wholesalers: [],
  products: [],
  offers: [],
  orders: [],
  ledger: [],
  coupons: [],
  complaints: [],
  notifications: [],
  otp: {}, // phone -> code
  idempotency: {}, // key -> response
};

function save() {
  try { fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2)); } catch (_) {}
}
function load() {
  try {
    if (fs.existsSync(DB_FILE)) {
      const raw = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
      Object.assign(db, raw);
    }
  } catch (_) {}
}

// Double-entry ledger: every money movement creates debit+credit pair.
function ledgerEntry({ userId, type, amount, debitAccount, creditAccount, reference }) {
  const entry = {
    id: uuid(),
    userId, type, amount,
    debitAccount, creditAccount, reference: reference || '',
    createdAt: new Date().toISOString(),
  };
  db.ledger.push(entry);
  save();
  return entry;
}

function walletBalance(userId) {
  return db.ledger
    .filter((e) => e.userId === userId)
    .reduce((sum, e) => {
      if (e.creditAccount === `wallet:${userId}`) return sum + e.amount;
      if (e.debitAccount === `wallet:${userId}`) return sum - e.amount;
      return sum;
    }, 0);
}

module.exports = { db, save, load, ledgerEntry, walletBalance, uuid };
