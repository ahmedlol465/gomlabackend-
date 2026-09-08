# باب عبدو — B2B Marketplace (Egypt MVP)

3 sections: **الرئيسية** (offers) • **باب عبدو قطاعي** (piece shopping) • **باب عبدو جملة** (carton shopping + suppliers). Tiered quantity discounts set by admin. Arabic RTL, Cairo font. No fintech module.

Maksab-style B2B marketplace. Retailers buy **wholesale (جملة) or retail (قطاعي)** with **admin-controlled quantity discounts**: the more pieces/cartons, the bigger the discount. Arabic RTL, Cairo font. No fintech module.

## Run
```powershell
# Backend (double-click start-backend.bat, keep window open):
cd backend; node src/index.js --seed   # http://localhost:3100/health
# Admin dashboard: http://localhost:3100/admin  (key: admin123, env ADMIN_KEY)
# Tests: node src/smoke.js; node src/fulltest.js   # 31/31 passing
# Mobile web: flutter build web --release, serve build/web on 8080
# Phone APK: mobile/build/app/outputs/flutter-apk/app-debug.apk (same Wi-Fi as PC)
```
Test login: any phone + OTP `123456`. Coupon: `AHLAN100`.

## Pricing model
Each offer has `bulkPrice` (كرتونة), `piecePrice` (قطعة), and `tiers` e.g. `5:3, 12:7, 24:12` = 3% off at 5+, 7% at 12+, 12% at 24+ — applied per line in the same mode, computed server-side at checkout (`tierSavings` returned). Admin edits everything from `/admin`: products, offers/prices/tiers/stock, suppliers, coupons, orders status, KYC, complaints.

## Run
```powershell
# Backend (auto-started via WMI, PID varies) — manual start:
cd backend; node src/index.js --seed   # http://localhost:3000/health
# Tests:
node src/smoke.js; node src/fulltest.js   # 42/42 passing
# Mobile web:
cd mobile; flutter pub get; flutter build web --release
python -m http.server 8080 --directory build/web   # http://localhost:8080
```
Test login: any phone + OTP `123456`. Coupons: `AHLAN100`, `OMNI5`.

## Spec coverage
| Spec | Status |
|---|---|
| Triple-stream inventory (direct/marketplace/exclusive) | ✅ `source` on offers + filter chips + exclusive scroller |
| Bulk pricing (package + unit price) | ✅ cards show both + inventory count |
| Badges (Selling Fast / Shortage / discount %) | ✅ `sellingFast`, `shortage` (stock<50), `discountPct` |
| Fuzzy smart search (product/category/brand, Arabic normalization) | ✅ `/products?search=` |
| Multi-cart per wholesaler + per-supplier checkout + min-order guard | ✅ carts keyed by wholesaler, sub-orders |
| Wholesaler comparison with price differences | ✅ `/products/:id/offers` + compare sheet |
| Wallet + hide/show balance | ✅ double-entry ledger + toggle |
| Airtime + bundles + bulk scratch cards | ✅ `/topup/airtime`, `/bundles/*`, `/scratch-cards` |
| Cash-in/out (Vodafone Cash…) | ✅ `/wallets/cash-in`, `/wallets/cash-out` |
| Utilities (electricity/water/gas) + telecom invoices | ✅ `/bills/pay` (+`telecom`) |
| Donations | ✅ `/charities`, `/donations` (بنك الطعام/مصر الخير/57357) |
| P2P merchant transfer via phone or ID | ✅ `/wallet/transfer` (+self-transfer block) |
| BNPL quote | ✅ `/credit/quote` (30/60/90) |
| Goals + progress + coupons hub | ✅ `/auth/me` goals/points, `/coupons` |
| Home: segments, promo slider, Buy Again, Saving Bundles, 3 scrollers | ✅ |
| Wholesale page: 3-step audio guide, tracking bar, category grid | ✅ (TTS via flutter_tts) |
| Fintech hub: blue wallet card, transfer, service grid | ✅ |
| Categories 3-col grid, Account (Egypt flag, tiles, wallet EGP, complaints, settings) | ✅ |
| Data models (User/Product/Transaction), Flutter + Node/Express, Fawry/Paymob-ready | ✅ (JSON-file DB now; Postgres+Redis for prod) |

## Production TODO (Egypt)
Postgres + Redis, Fawry/Paymob webhook verify + idempotency, aggregator (Fawry/Bee/Aman/Masary), licensed wallet partner (CBE), FRA BNPL rules, ETA e-invoicing, FCM push, wallet PIN/biometric, real product images.
