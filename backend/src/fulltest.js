// Full spec coverage test: marketplace + tiered pricing + admin. Backend must be running.
const BASE = 'http://localhost:3100/api/v1';
const ADMIN = { 'x-admin-key': process.env.ADMIN_KEY || 'admin123' };
let pass = 0, fail = 0;
const results = [];
function check(name, cond, extra = '') {
  if (cond) { pass++; results.push(`PASS ${name}`); }
  else { fail++; results.push(`FAIL ${name} ${extra}`); }
}
async function req(method, path, body, token, admin = false) {
  const r = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(admin ? ADMIN : {}), 'Idempotency-Key': `${Date.now()}-${Math.random()}` },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch (_) {}
  return { status: r.status, json, text };
}

(async () => {
  let r = await req('POST', '/auth/request-otp', { phone: '01099999999' });
  check('request-otp', r.status === 200 && r.json.ok);
  r = await req('POST', '/auth/verify-otp', { phone: '01099999999', otp: '123456', name: 'tester' });
  check('verify-otp', r.status === 200 && !!r.json.token);
  const T = r.json.token;
  r = await req('POST', '/auth/kyc', { shopName: 'test', taxId: '1', commercialRegister: '2', lat: 30, lng: 31 }, T);
  check('kyc', r.json.ok === true);

  // Catalog + streams
  r = await req('GET', '/products');
  check('products-all', r.json.items.length >= 30, `got ${r.json.items?.length}`);
  for (const s of ['direct', 'marketplace', 'exclusive']) {
    r = await req('GET', `/products?source=${s}`);
    check(`stream-${s}`, r.json.items.length > 0 && r.json.items.every((o) => o.source === s));
  }
  // piece price + tiers present on every offer
  r = await req('GET', '/products');
  check('piece-tiers-present', r.json.items.every((o) => o.piecePrice > 0 && Array.isArray(o.tiers) && o.tiers.length > 0));
  check('badges-present', r.json.items.some((o) => o.sellingFast) && r.json.items.some((o) => o.shortage));
  r = await req('GET', '/products?hot=1');
  check('hot-offers', r.json.items.length > 0);
  r = await req('GET', '/products?search=' + encodeURIComponent('البان'));
  check('search-fuzzy-norm', r.json.items.length > 0);
  r = await req('GET', '/products/p01/offers');
  check('comparison', r.json.offers.length >= 2);

  // Tiered pricing math: bulk mode, qty hitting tier (default tiers 5:3, 12:7, 24:12)
  const prod = await req('GET', '/products');
  const bulk = prod.json.items.find((o) => o.wholesalerId === 'ws0' && o.source === 'direct');
  const unit = bulk.bulkPrice;
  r = await req('POST', '/cart/checkout', { items: [{ offerId: bulk.id, qty: 12, mode: 'bulk' }] }, T);
  const line = r.json.order?.lines?.[0];
  const expected = Math.round(unit * 12 * 0.93 * 100) / 100;
  check('tier-bulk-12', r.json.ok && line?.tier?.discountPct === 7 && Math.abs(line.lineTotal - expected) < 0.01, JSON.stringify(line));
  check('tier-savings', (r.json.order?.tierSavings || 0) > 0);

  // Piece mode pricing
  r = await req('POST', '/cart/checkout', { items: [{ offerId: bulk.id, qty: 3, mode: 'piece' }] }, T);
  const pl = r.json.order?.lines?.[0];
  check('piece-mode', r.json.ok && pl?.mode === 'piece' && Math.abs(pl.lineTotal - bulk.piecePrice * 3) < 0.01, JSON.stringify(pl));

  // Piece tier: 24 pieces -> 12% off piece price
  r = await req('POST', '/cart/checkout', { items: [{ offerId: bulk.id, qty: 24, mode: 'piece' }] }, T);
  check('tier-piece-24', r.json.ok && r.json.order.lines[0]?.tier?.discountPct === 12);

  // Coupon still applies after tiers
  r = await req('POST', '/cart/checkout', { items: [{ offerId: bulk.id, qty: 12, mode: 'bulk' }], coupon: 'AHLAN100' }, T);
  check('coupon-after-tiers', r.json.ok && r.json.order.discount === 100);

  r = await req('GET', '/orders', null, T);
  check('orders', r.json.items.length >= 3);
  r = await req('GET', '/orders/buy-again', null, T);
  check('buy-again', r.json.items.length >= 1);
  r = await req('GET', '/auth/me', null, T);
  check('me-goals', !!r.json.goals && (r.json.points ?? 0) > 0);

  // Admin API
  r = await req('GET', '/admin/overview', null, null, true);
  check('admin-overview', r.json.products >= 30 && r.json.orders >= 3);
  r = await req('GET', '/admin/overview');
  check('admin-guard', r.status === 403);
  // create product + offer with custom tiers, verify pricing uses them
  r = await req('POST', '/admin/products', { name: 'منتج اختبار', category: 'بقالة', brand: 'تست', unitName: 'قطعة', bulkUnit: 'كرتونة (10)', bulkQty: 10, sellingFast: false }, null, true);
  const pid = r.json.item?.id;
  check('admin-create-product', !!pid);
  r = await req('POST', '/admin/offers', { productId: pid, wholesalerId: 'ws0', source: 'direct', bulkPrice: 1000, piecePrice: 115, oldPrice: null, stock: 100, tiers: [{ minQty: 2, discountPct: 50 }] }, null, true);
  const oid = r.json.item?.id;
  check('admin-create-offer', !!oid);
  r = await req('POST', '/cart/checkout', { items: [{ offerId: oid, qty: 2, mode: 'bulk' }] }, T);
  check('admin-tier-applied', r.json.ok && Math.abs(r.json.order.lines[0].lineTotal - 1000) < 0.01, JSON.stringify(r.json.order?.lines?.[0]));
  r = await req('PUT', `/admin/offers/${oid}`, { bulkPrice: 900 }, null, true);
  check('admin-update-offer', r.json.ok && r.json.item.bulkPrice === 900);
  r = await req('DELETE', `/admin/offers/${oid}`, null, null, true);
  check('admin-delete-offer', r.json.ok === true);
  r = await req('DELETE', `/admin/products/${pid}`, null, null, true);
  check('admin-delete-product', r.json.ok === true);
  // coupons + users + orders + complaints admin
  r = await req('GET', '/admin/coupons', null, null, true);
  check('admin-coupons', r.json.items.length >= 2);
  r = await req('POST', '/complaints', { subject: 't', message: 'm' }, T);
  check('complaint', r.json.ok === true);
  r = await req('GET', '/admin/complaints', null, null, true);
  check('admin-complaints', r.json.items.length >= 1);

  console.log(results.join('\n'));
  console.log(`\nTOTAL: ${pass} pass, ${fail} fail`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('HARNESS ERROR', e); process.exit(2); });
