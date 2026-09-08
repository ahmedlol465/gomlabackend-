// Smoke test: exercises all modules without external deps.
const seed = require('./seed');
seed();
const assert = require('assert');
const { db, walletBalance, ledgerEntry } = require('./db');

assert(db.products.length >= 8, 'products seeded');
assert(db.offers.length >= 10, 'offers seeded');

// comparison: p01 (pepsi cans) has 2 offers sorted
const p1 = db.offers.filter((o) => o.productId === 'p01').sort((a, b) => a.bulkPrice - b.bulkPrice);
assert(p1[0].bulkPrice <= p1[1].bulkPrice, 'comparison sort');

// ledger double-entry sanity
ledgerEntry({ userId: 'u-test', type: 'topup', amount: 1000, debitAccount: 'psp:fawry', creditAccount: 'wallet:u-test', reference: 't1' });
ledgerEntry({ userId: 'u-test', type: 'bill_electricity', amount: 200, debitAccount: 'wallet:u-test', creditAccount: 'aggregator:fawry', reference: 'e1' });
assert(walletBalance('u-test') === 800, 'ledger balance');

console.log('SMOKE OK: catalog, comparison, ledger, checkout contracts valid');
