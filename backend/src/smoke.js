// Smoke test: exercises all modules without external deps.
const seed = require('./seed');
seed();
const assert = require('assert');
const { db, walletBalance, ledgerEntry } = require('./db');

assert(db.products.length >= 120, 'products seeded');
assert(db.offers.length >= 120, 'offers seeded');
assert(db.wholesalers.length === 1, 'single wholesaler');
assert(db.categories.length >= 10, 'categories seeded');

// single-supplier: every offer is from بابا عبدو
assert(db.offers.every((o) => o.wholesalerId === 'ws0'), 'all offers from ws0');
assert(db.categories.slice().sort().join(',') === [...new Set(db.products.map((p) => p.category))].sort().join(','), 'categories match products');

// ledger double-entry sanity
ledgerEntry({ userId: 'u-test', type: 'topup', amount: 1000, debitAccount: 'psp:fawry', creditAccount: 'wallet:u-test', reference: 't1' });
ledgerEntry({ userId: 'u-test', type: 'bill_electricity', amount: 200, debitAccount: 'wallet:u-test', creditAccount: 'aggregator:fawry', reference: 'e1' });
assert(walletBalance('u-test') === 800, 'ledger balance');

console.log('SMOKE OK: catalog, single-supplier, ledger contracts valid');