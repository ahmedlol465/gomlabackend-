import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'api.dart';

const mBlue = Color(0xFF0B63E5);
const navy = Color(0xFF0A3A5C);
const limeBg = Color(0xFF9FE870);
const bannerGreenBg = Color(0xFFD9F2DC);
const badgeOrange = Color(0xFFE08A00);
const ctaYellow = Color(0xFFFFC107);
const tileBg = Color(0xFFEAF3FB);
const pageBg = Color(0xFFF6F8FB);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  runApp(const MaksabApp());
}

class MaksabApp extends StatelessWidget {
  const MaksabApp({super.key});
  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true, scaffoldBackgroundColor: pageBg, colorScheme: ColorScheme.fromSeed(seedColor: mBlue));
    return MaterialApp(
      title: 'بابا عبدو',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      theme: base.copyWith(
        textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
      ),
      home: Directionality(textDirection: TextDirection.rtl, child: Api.token == null ? const OnboardingScreen() : const HomeScreen()),
    );
  }
}

String egp(num? v) => '${(v ?? 0).toStringAsFixed(2)} ج.م';

String orderStatusAr(String? s) {
  switch (s) {
    case 'confirmed': return 'مؤكد';
    case 'preparing': return 'قيد التجهيز';
    case 'shipping': return 'قيد الشحن';
    case 'delivered': return 'تم التوصيل';
    case 'cancelled': return 'ملغي';
    default: return s ?? '';
  }
}

void toast(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1200)));
}

const catIcons = {
  'مشروبات': Icons.local_drink, 'مبردات ومجمدات': Icons.ac_unit, 'بقالة': Icons.shopping_basket,
  'منظفات ومطهرات': Icons.cleaning_services, 'صابون': Icons.soap, 'حلويات وشوكولاتة': Icons.cookie,
  'سايب': Icons.grain, 'مأكولات أساسية': Icons.rice_bowl, 'شيبسي ومقرمشات': Icons.fastfood,
  'ورقيات وحفاضات': Icons.baby_changing_station, 'مستهلكات وبطاريات': Icons.battery_charging_full,
  'عناية شخصية': Icons.spa, 'جبن والبان': Icons.egg, 'مياه معدنية': Icons.water_drop,
  'ياميش رمضان': Icons.nights_stay, 'ألبان': Icons.coffee,
};

// ---------- Tiered pricing helpers (mirror server math) ----------
List tiersOf(Map o) => (o['tiers'] as List?) ?? const [];

Map? bestTier(Map o, int qty) {
  Map? best;
  for (final t in tiersOf(o)) {
    final m = t as Map;
    if ((m['minQty'] as num) <= qty && (best == null || (m['discountPct'] as num) > (best['discountPct'] as num))) best = m;
  }
  return best;
}

Map? nextTier(Map o, int qty) {
  Map? next;
  for (final t in tiersOf(o)) {
    final m = t as Map;
    if ((m['minQty'] as num) > qty && (next == null || (m['minQty'] as num) < (next['minQty'] as num))) next = m;
  }
  return next;
}

num unitOf(Map o, String mode) => ((mode == 'piece' ? o['piecePrice'] : o['bulkPrice']) as num?) ?? 0;

num lineTotalOf(Map o, int qty, String mode) {
  final b = bestTier(o, qty);
  final disc = b == null ? 0 : (b['discountPct'] as num);
  return (unitOf(o, mode) * qty * (1 - disc / 100) * 100).round() / 100;
}

String modeLabel(String mode) => mode == 'piece' ? 'قطاعي' : 'جملة';

// ---------- Multi-cart: one cart per wholesaler, lines carry bulk/piece mode ----------
class CartState extends ChangeNotifier {
  final Map<String, Map<String, dynamic>> carts = {};
  void add(Map offer, String mode, int qty) {
    final o = offer as Map<String, dynamic>;
    final wsId = (o['wholesalerId'] ?? 'ws0') as String;
    final key = '${o['id']}__$mode';
    carts.putIfAbsent(wsId, () => {'wsName': o['wholesalerName'] ?? 'المورد', 'lines': <String, dynamic>{}});
    final lines = carts[wsId]!['lines'] as Map<String, dynamic>;
    if (lines.containsKey(key)) { lines[key]!['qty'] = (lines[key]!['qty'] as int) + qty; }
    else { lines[key] = {'offer': o, 'qty': qty, 'mode': mode}; }
    notifyListeners();
  }
  void setQty(String wsId, String key, int qty) {
    final lines = carts[wsId]?['lines'] as Map<String, dynamic>?;
    if (lines == null || !lines.containsKey(key)) return;
    if (qty <= 0) { lines.remove(key); if (lines.isEmpty) carts.remove(wsId); }
    else { lines[key]!['qty'] = qty; }
    notifyListeners();
  }
  void clearWs(String wsId) { carts.remove(wsId); notifyListeners(); }
  int get cartCount => carts.length;
  int get itemCount => carts.values.fold(0, (s, c) => s + ((c['lines'] as Map).values.fold(0, (a, e) => a + (e['qty'] as int))));
  num wsTotal(String wsId) {
    final lines = carts[wsId]?['lines'] as Map<String, dynamic>?;
    if (lines == null) return 0;
    return (lines.values.fold<num>(0, (s, e) => s + lineTotalOf(e['offer'] as Map, e['qty'] as int, e['mode'] as String)) * 100).round() / 100;
  }
  num wsSavings(String wsId) {
    final lines = carts[wsId]?['lines'] as Map<String, dynamic>?;
    if (lines == null) return 0;
    return (lines.values.fold<num>(0, (s, e) {
      final o = e['offer'] as Map; final q = e['qty'] as int; final m = e['mode'] as String;
      return s + (unitOf(o, m) * q - lineTotalOf(o, q, m));
    }) * 100).round() / 100;
  }
}
final cart = CartState();

// ---------- Onboarding ----------
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  final phoneCtrl = TextEditingController();
  final otpCtrl = TextEditingController();
  final shopCtrl = TextEditingController();
  final taxCtrl = TextEditingController();
  int step = 0; String err = ''; String msg = ''; bool busy = false;
  int resendIn = 0; Timer? timer;
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  void startResendTimer() {
    timer?.cancel();
    setState(() => resendIn = 30);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (resendIn <= 1) { t.cancel(); setState(() => resendIn = 0); }
      else { setState(() => resendIn--); }
    });
  }
  bool validPhone(String p) => RegExp(r'^01\d{9}$').hasMatch(p.trim());
  Future<void> requestOtp() async {
    final p = phoneCtrl.text.trim();
    if (!validPhone(p)) { setState(() => err = 'اكتب رقم موبايل مصري صحيح (11 رقم يبدأ بـ 01)'); return; }
    setState(() { busy = true; err = ''; msg = ''; });
    try {
      await Api.post('/auth/request-otp', {'phone': p});
      setState(() => msg = 'اتبعتلّك كود على $p (وضع التجربة: 123456)');
      startResendTimer();
    } catch (_) { setState(() => msg = 'تعذر الاتصال بالسيرفر — هتكمل بوضع التجربة (123456)'); startResendTimer(); }
    finally { if (mounted) setState(() { busy = false; step = 1; }); }
  }
  Future<void> verify() async {
    if (otpCtrl.text.trim().length != 6) { setState(() => err = 'الكود 6 أرقام'); return; }
    setState(() => busy = true);
    try {
      final r = await Api.post('/auth/verify-otp', {'phone': phoneCtrl.text.trim(), 'otp': otpCtrl.text.trim(), 'name': 'تاجر'});
      await Api.saveToken(r['token'] as String);
    } catch (_) { setState(() => msg = 'وضع تجريبي بدون سيرفر'); }
    finally { if (mounted) setState(() { busy = false; step = 2; }); }
  }
  Future<void> submitKyc() async {
    if (shopCtrl.text.trim().length < 2) { setState(() => err = 'اكتب اسم المحل'); return; }
    if (taxCtrl.text.trim().isEmpty) { setState(() => err = 'اكتب البطاقة الضريبية أو السجل التجاري'); return; }
    setState(() { busy = true; err = ''; });
    try { await Api.post('/auth/kyc', {'shopName': shopCtrl.text.trim(), 'taxId': taxCtrl.text.trim(), 'commercialRegister': 'CR-001', 'lat': 30.0444, 'lng': 31.2357}); } catch (_) {}
    if (!mounted) return;
    setState(() => busy = false);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: HomeScreen())));
  }
  @override
  Widget build(BuildContext context) {
    const titles = ['رقم الموبايل', 'كود التحقق', 'بيانات المحل'];
    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 16),
        const CircleAvatar(radius: 42, backgroundColor: mBlue, child: Text('ب', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold))),
        const SizedBox(height: 10),
        const Text('بابا عبدو', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: mBlue)),
        const Text('جملة وقطاعي لتجار التجزئة — كل ما تزود، الخصم يكبر', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 18),
        Row(children: List.generate(3, (i) => Expanded(child: Container(height: 5, margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: i <= step ? mBlue : Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))))),
        const SizedBox(height: 6),
        Text('خطوة ${step + 1} من 3: ${titles[step]}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 18),
        if (step == 0) ...[
          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, maxLength: 11,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'رقم الموبايل (01xxxxxxxxx)', prefixIcon: Icon(Icons.phone))),
          const SizedBox(height: 12),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: busy ? null : requestOtp,
            child: busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('إرسال الكود', style: TextStyle(fontSize: 16))),
        ] else if (step == 1) ...[
          Text('الكود اتبعت على ${phoneCtrl.text.trim()}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(controller: otpCtrl, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'كود التحقق')),
          const SizedBox(height: 12),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: busy ? null : verify,
            child: busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('تأكيد', style: TextStyle(fontSize: 16))),
          TextButton(onPressed: resendIn > 0 || busy ? null : requestOtp, child: Text(resendIn > 0 ? 'إعادة الإرسال بعد $resendIn ث' : 'إعادة إرسال الكود')),
        ] else ...[
          TextField(controller: shopCtrl, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'اسم المحل *', prefixIcon: Icon(Icons.store))),
          const SizedBox(height: 10),
          TextField(controller: taxCtrl, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'البطاقة الضريبية / السجل التجاري *', prefixIcon: Icon(Icons.badge))),
          const SizedBox(height: 6),
          const Text('الموقع: القاهرة (تحديد تلقائي لربط التوصيل)', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: busy ? null : submitKyc,
            child: busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('ابدأ البيع والشرا', style: TextStyle(fontSize: 16))),
        ],
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12))),
      ]))),
    );
  }
}

// ---------- Home shell ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int seg = 0; // 0 الرئيسية (عروض), 1 بابا عبدو قطاعي, 2 بابا عبدو جملة
  void go(int i) => setState(() => seg = i);
  @override
  Widget build(BuildContext context) {
    final pages = [const OffersGrid(), const RetailTab(), WholesaleTab(onGo: go)];
    return ListenableBuilder(
      listenable: cart,
      builder: (_, __) => Scaffold(
        body: SafeArea(child: Column(children: [TopTiles(seg: seg, onSel: go), Expanded(child: pages[seg])])),
        floatingActionButton: cart.cartCount > 0
            ? FloatingActionButton(backgroundColor: mBlue, onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: MultiCartSheet())), child: const Icon(Icons.shopping_cart, color: Colors.white))
            : null,
        bottomNavigationBar: BottomNav(seg: seg, onHome: go),
      ),
    );
  }
}

class TopTiles extends StatelessWidget {
  final int seg; final void Function(int) onSel;
  const TopTiles({super.key, required this.seg, required this.onSel});
  @override
  Widget build(BuildContext context) {
    final tiles = [
      {'label': 'عروضي', 'icon': Icons.local_offer},
      {'label': 'قطاعي باب عبده', 'icon': Icons.shopping_basket},
      {'label': 'جملة', 'icon': Icons.store},
    ];
    return Container(
      color: pageBg, height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: 3, separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final active = seg == i;
          return GestureDetector(
            onTap: () => onSel(i),
            child: Container(
              width: 100,
              decoration: BoxDecoration(color: active ? mBlue : Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)]),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(tiles[i]['icon'] as IconData, color: active ? Colors.white : mBlue, size: 30),
                const SizedBox(height: 4),
                Text(tiles[i]['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.black87)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  final int seg; final void Function(int) onHome;
  const BottomNav({super.key, required this.seg, required this.onHome});
  @override
  Widget build(BuildContext context) {
    final d = (Widget w) => Directionality(textDirection: TextDirection.rtl, child: w);
    List<Map<String, dynamic>> items;
    if (seg == 1) {
      items = [{'l': 'قطاعي باب عبده', 'i': Icons.shopping_basket, 'go': 1}, {'l': 'الأقسام', 'i': Icons.grid_view}, {'l': 'طلباتي', 'i': Icons.receipt_long}, {'l': 'المزيد', 'i': Icons.menu}];
    } else if (seg == 2) {
      items = [{'l': 'جملة', 'i': Icons.store, 'go': 2}, {'l': 'الأقسام', 'i': Icons.grid_view}, {'l': 'طلباتي', 'i': Icons.receipt_long}, {'l': 'المزيد', 'i': Icons.menu}];
    } else {
      items = [{'l': 'عروضي', 'i': Icons.local_offer, 'go': 0}, {'l': 'الأقسام', 'i': Icons.grid_view}, {'l': 'طلباتي', 'i': Icons.receipt_long}, {'l': 'المزيد', 'i': Icons.menu}];
    }
    void open(String l) {
      if (l == 'الأقسام') { Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const CategoriesPage()))); }
      else if (l == 'طلباتي') { Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const MyOrdersPage()))); }
      else if (l == 'المزيد') { Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const MorePage()))); }
      else {
        final it = items.firstWhere((e) => e['l'] == l);
        onHome(it['go'] as int? ?? 0);
      }
    }
    return BottomNavigationBar(
      currentIndex: 0, onTap: (i) => open(items[i]['l'] as String), type: BottomNavigationBarType.fixed,
      selectedItemColor: mBlue, unselectedItemColor: Colors.grey,
      items: items.map((e) => BottomNavigationBarItem(icon: Icon(e['i'] as IconData), label: e['l'] as String)).toList(),
    );
  }
}

Widget sectionHead(String title, VoidCallback onAll) {
  return Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8, right: 4, left: 4),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      GestureDetector(onTap: onAll, child: const Row(children: [Text('عرض الكل', style: TextStyle(color: mBlue, fontSize: 12)), Icon(Icons.chevron_left, color: mBlue, size: 16)])),
    ]),
  );
}

Widget productImage(Map o) {
  final img = (o['image'] as String?) ?? '';
  if (img.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(img, height: 96, width: double.infinity, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(catIcons[o['category']] ?? Icons.inventory_2, size: 52, color: mBlue)),
    );
  }
  return Icon(catIcons[o['category']] ?? Icons.inventory_2, size: 52, color: mBlue);
}

// ---------- Product card: bulk/piece modes + tier discounts ----------
class ProductCardM extends StatefulWidget {
  final Map<String, dynamic> offer;
  final List? allOffers;
  final String? fixedMode; // 'bulk' | 'piece' | null (both with toggle)
  const ProductCardM({super.key, required this.offer, this.allOffers, this.fixedMode});
  @override
  State<ProductCardM> createState() => _ProductCardMState();
}
class _ProductCardMState extends State<ProductCardM> {
  late String mode;
  int qty = 1;
  @override
  void initState() { super.initState(); mode = widget.fixedMode ?? 'bulk'; }
  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final bulk = (o['bulkPrice'] as num?) ?? 0;
    final piece = (o['piecePrice'] as num?) ?? 0;
    final uname = o['unitName'] ?? 'قطعة';
    final bqty = o['bulkQty'] ?? 1;
    final unit = (o['unitPrice'] as num?) ?? 0;
    final fast = o['sellingFast'] == true;
    final short = o['shortage'] == true;
    final disc = (o['discountPct'] ?? 0) as num;
    final cur = bestTier(o, qty);
    final nxt = nextTier(o, qty);
    final total = lineTotalOf(o, qty, mode);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (fast || short)
          Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: fast ? badgeOrange : Colors.red, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.flash_on, size: 12, color: Colors.white), Text(fast ? 'يتخلص بسرعة' : 'كمية محدودة', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))])),
        SizedBox(
          height: 104,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(12)),
              child: Center(child: productImage(o))),
            if (widget.allOffers != null)
              Positioned(right: 4, top: 4, child: GestureDetector(
                onTap: () => showModalBottomSheet(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: CompareSheet(productId: o['productId'], allOffers: widget.allOffers!))),
                child: const CircleAvatar(radius: 13, backgroundColor: Colors.white, child: Icon(Icons.compare_arrows, size: 15, color: mBlue)))),
          ]),
        ),
        const SizedBox(height: 6),
        if (widget.fixedMode == null)
          Row(children: [
            Expanded(
              child: SegmentedButton<String>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [ButtonSegment(value: 'bulk', label: Text('جمله', style: TextStyle(fontSize: 12))), ButtonSegment(value: 'piece', label: Text('قطاعي', style: TextStyle(fontSize: 12)))],
              selected: {mode},
              onSelectionChanged: (s) => setState(() => mode = s.first),
            ),
          ),
        ]),
        Text(mode == 'bulk' ? 'من ${egp(bulk)}' : '${egp(piece)} / لل$uname', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
        if (mode == 'bulk') Text('$bqty $uname - ${unit.toStringAsFixed(2)} ج.م لل$uname', style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
        if (cur != null) Text('خصم كمية ${cur['discountPct']}% مطبق ✓', style: const TextStyle(fontSize: 10.5, color: Colors.green, fontWeight: FontWeight.bold))
        else if (nxt != null) Text('زوّد لـ ${nxt['minQty']} ${mode == 'bulk' ? 'كراتين' : uname} لخصم ${nxt['discountPct']}%', style: TextStyle(fontSize: 10.5, color: Colors.orange.shade800)),
        Text(o['productName'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        if (disc > 0) Text('خصم $disc% لفترة محدودة', style: const TextStyle(fontSize: 10.5, color: Colors.green, fontWeight: FontWeight.bold)),
        Expanded(child: Align(alignment: Alignment.bottomCenter, child: Row(children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline, color: mBlue), onPressed: () => setState(() => qty = qty > 1 ? qty - 1 : 1)),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.add_circle_outline, color: mBlue), onPressed: () => setState(() => qty++)),
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () { cart.add(o, mode, qty); toast(context, 'اتضاف $qty ${modeLabel(mode)} — ${egp(total)}'); },
            child: const Text('أضف', style: TextStyle(fontSize: 13)))),
        ]))),
      ]),
    );
  }
}

// ---------- Retail section: بابا عبدو قطاعي (piece mode) ----------
class RetailTab extends StatefulWidget {
  const RetailTab({super.key});
  @override
  State<RetailTab> createState() => _RetailTabState();
}
class _RetailTabState extends State<RetailTab> {
  List items = [];
  List buyAgain = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await Api.get('/products');
      final all = (r['items'] as List);
      final seen = <String>{};
      setState(() { items = all.where((o) => seen.add(o['productId'] as String)).toList(); loading = false; });
    } catch (_) {
      setState(() { items = DemoData.offers; loading = false; });
    }
    try { final b = await Api.get('/orders/buy-again'); if (mounted) setState(() => buyAgain = b['items'] ?? []); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final d = (Widget w) => Directionality(textDirection: TextDirection.rtl, child: w);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFF00A651), Color(0xFF00783A)])),
          child: const Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('قطاعي باب عبده', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19)),
              Text('اشتري بالقطعة — وكل ما تزود العدد، الخصم يكبر', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            CircleAvatar(radius: 28, backgroundColor: Colors.white24, child: Icon(Icons.shopping_basket, size: 34, color: Colors.white)),
          ])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const SearchPage()))),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: const Row(children: [Icon(Icons.search, color: Colors.grey), SizedBox(width: 8), Text('دوّر على منتج بالقطعة...', style: TextStyle(color: Colors.grey))])))),
          IconButton(onPressed: () => showModalBottomSheet(context: context, builder: (_) => d(const NotifSheet())), icon: const Icon(Icons.notifications_none)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => showModalBottomSheet(context: context, builder: (_) => d(BuyAgainSheet(items: buyAgain, mode: 'piece'))),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [CircleAvatar(backgroundColor: tileBg, child: Icon(Icons.replay, color: mBlue)), SizedBox(width: 8), Text('اشتري مرة\nأخرى', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])))),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const CategoriesPage()))),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [CircleAvatar(backgroundColor: tileBg, child: Icon(Icons.grid_view, color: mBlue)), SizedBox(width: 8), Text('تسوق\nبالأقسام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])))),
        ]),
        sectionHead('تسوق بالقطعة', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const SearchPage())))),
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.56),
          itemCount: items.length,
          itemBuilder: (_, i) => ProductCardM(offer: items[i] as Map<String, dynamic>, allOffers: items, fixedMode: 'piece'),
        ),
      ]),
    );
  }
}

// ---------- Orders home ----------
class OrdersHome extends StatefulWidget {
  final void Function(int) onGo;
  const OrdersHome({super.key, required this.onGo});
  @override
  State<OrdersHome> createState() => _OrdersHomeState();
}
class _OrdersHomeState extends State<OrdersHome> {
  List recommended = []; List buyAgain = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final r = await Api.get('/products');
      final items = (r['items'] as List);
      final seen = <String>{};
      setState(() => recommended = items.where((o) => seen.add(o['productId'] as String)).take(8).toList());
    } catch (_) { setState(() => recommended = DemoData.offers); }
    try { final b = await Api.get('/orders/buy-again'); setState(() => buyAgain = b['items'] ?? []); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final d = (Widget w) => Directionality(textDirection: TextDirection.rtl, child: w);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const SearchPage()))),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: const Row(children: [Icon(Icons.search, color: Colors.grey), SizedBox(width: 8), Text('بتدور على منتج معين؟', style: TextStyle(color: Colors.grey))])))),
          IconButton(onPressed: () => showModalBottomSheet(context: context, builder: (_) => d(const NotifSheet())), icon: const Icon(Icons.notifications_none)),
        ]),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [mBlue, Color(0xFF003A8C)])),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('أصناف جديدة على بابا عبدو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: ctaYellow, foregroundColor: Colors.black),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const CategoriesPage()))), child: const Text('اطلب دلوقتي')),
            ])),
            const CircleAvatar(radius: 34, backgroundColor: Colors.white24, child: Icon(Icons.local_shipping, size: 40, color: Colors.white)),
          ])),
        const SizedBox(height: 4),
        sectionHead('اختصارات', () {}),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => showModalBottomSheet(context: context, builder: (_) => d(BuyAgainSheet(items: buyAgain))),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [CircleAvatar(backgroundColor: tileBg, child: Icon(Icons.replay, color: mBlue)), SizedBox(width: 8), Text('اشتري مرة\nأخرى', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])))),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const OffersPage()))),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [CircleAvatar(backgroundColor: tileBg, child: Icon(Icons.savings, color: mBlue)), SizedBox(width: 8), Text('باقات\nالتوفير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))])))),
        ]),
        sectionHead('تصفح الاقسام', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const CategoriesPage())))),
        const CatGridPreview(),
        sectionHead('المنتجات الموصى بها', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const SearchPage())))),
        SizedBox(height: 340, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: recommended.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(width: 172, child: ProductCardM(offer: recommended[i] as Map<String, dynamic>, allOffers: recommended)))),
      ]),
    );
  }
}

class BuyAgainSheet extends StatelessWidget {
  final List items;
  final String mode;
  const BuyAgainSheet({super.key, required this.items, this.mode = 'bulk'});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('اشتري مرة أخرى', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد طلبات سابقة بعد.', style: TextStyle(color: Colors.grey))),
      ...items.take(6).map((o) => ListTile(title: Text(o['productName'] ?? ''), subtitle: Text('${o['wholesalerName']} — ${egp(mode == 'piece' ? o['piecePrice'] : o['bulkPrice'])}'),
        trailing: ElevatedButton(onPressed: () { cart.add(o as Map<String, dynamic>, mode, 1); toast(context, 'اتضافت للسلة'); }, child: const Text('+')))),
    ]));
  }
}

class NotifSheet extends StatefulWidget {
  const NotifSheet({super.key});
  @override
  State<NotifSheet> createState() => _NotifSheetState();
}
class _NotifSheetState extends State<NotifSheet> {
  List items = [];
  @override
  void initState() { super.initState(); Api.get('/notifications').then((r) => setState(() => items = r['items'])).catchError((_) {}); }
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ...items.take(8).map((n) => ListTile(title: Text(n['title'] ?? ''), subtitle: Text(n['body'] ?? ''))),
      if (items.isEmpty) const Text('لا توجد إشعارات', style: TextStyle(color: Colors.grey)),
    ]));
  }
}

// ---------- Categories ----------
class CatGridPreview extends StatelessWidget {
  const CatGridPreview({super.key});
  @override
  Widget build(BuildContext context) {
    final cats = DemoData.categories.take(8).toList();
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.8),
      itemCount: cats.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: CategoryProducts(category: cats[i])))),
        child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(catIcons[cats[i]] ?? Icons.category, color: mBlue, size: 30)),
            const SizedBox(height: 4), Text(cats[i], textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
          ])),
      ),
    );
  }
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}
class _CategoriesPageState extends State<CategoriesPage> {
  List cats = [];
  @override
  void initState() {
    super.initState();
    Api.get('/products').then((r) => setState(() => cats = r['categories'])).catchError((_) => setState(() => cats = DemoData.categories));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأقسام'), centerTitle: true),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9),
        itemCount: cats.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: CategoryProducts(category: cats[i])))),
          child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(14)),
                child: Icon(catIcons[cats[i]] ?? Icons.category, color: mBlue, size: 44)),
              const SizedBox(height: 8), Text(cats[i], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ])),
        ),
      ),
    );
  }
}

class CategoryProducts extends StatefulWidget {
  final String category;
  const CategoryProducts({super.key, required this.category});
  @override
  State<CategoryProducts> createState() => _CategoryProductsState();
}
class _CategoryProductsState extends State<CategoryProducts> {
  List items = [];
  @override
  void initState() {
    super.initState();
    Api.get('/products?category=${Uri.encodeComponent(widget.category)}').then((r) => setState(() => items = r['items'])).catchError((_) {
      setState(() => items = DemoData.offers.where((o) => o['category'] == widget.category).toList());
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category), centerTitle: true),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.58),
        itemCount: items.length,
        itemBuilder: (_, i) => ProductCardM(offer: items[i] as Map<String, dynamic>, allOffers: items),
      ),
    );
  }
}

// ---------- Search ----------
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}
class _SearchPageState extends State<SearchPage> {
  String query = ''; String cat = 'الكل'; String source = '';
  List offers = []; List cats = ['الكل', ...DemoData.categories];
  bool loading = true; Timer? deb;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await Api.get('/products?search=${Uri.encodeComponent(query)}${source.isEmpty ? '' : '&source=$source'}');
      offers = r['items'] as List;
      cats = ['الكل', ...((r['categories'] as List).map((e) => e.toString()))];
    } catch (_) { offers = DemoData.offers; }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  void dispose() { deb?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final filtered = offers.where((o) => cat == 'الكل' || o['category'] == cat).toList();
    final seen = <String>{};
    final grid = filtered.where((o) => seen.add(o['productId'] as String)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('البحث'), centerTitle: true),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(autofocus: true,
          decoration: InputDecoration(hintText: 'بتدور على منتج معين؟', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
          onChanged: (v) { deb?.cancel(); deb = Timer(const Duration(milliseconds: 400), () { setState(() => query = v); load(); }); })),
        SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final s in ['', 'direct', 'marketplace', 'exclusive'])
              Padding(padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(label: Text(s.isEmpty ? 'كل المصادر' : (s == 'direct' ? 'مباشر' : s == 'exclusive' ? 'حصري' : 'سوق الجملة')), selected: source == s,
                  onSelected: (_) { setState(() => source = s); load(); })),
          ])),
        const SizedBox(height: 6),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator())
          : grid.isEmpty ? const Center(child: Text('لا نتائج — جرّب كلمة أخرى'))
          : GridView.builder(padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.58),
            itemCount: grid.length, itemBuilder: (_, i) => ProductCardM(offer: grid[i] as Map<String, dynamic>, allOffers: grid))),
      ]),
    );
  }
}

// ---------- Compare ----------
class CompareSheet extends StatefulWidget {
  final String productId; final List allOffers;
  const CompareSheet({super.key, required this.productId, required this.allOffers});
  @override
  State<CompareSheet> createState() => _CompareSheetState();
}
class _CompareSheetState extends State<CompareSheet> {
  List offers = [];
  @override
  void initState() {
    super.initState();
    Api.get('/products/${widget.productId}/offers').then((r) => setState(() => offers = r['offers'])).catchError((_) {
      setState(() => offers = widget.allOffers.where((o) => o['productId'] == widget.productId).toList());
    });
  }
  @override
  Widget build(BuildContext context) {
    final list = [...offers]..sort((a, b) => (a['bulkPrice'] as num).compareTo(b['bulkPrice'] as num));
    final min = list.isEmpty ? 0 : list.first['bulkPrice'];
    return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('قارن بين البائعين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
      ...list.map((o) {
        final diff = ((o['bulkPrice'] as num) - (min as num)).toStringAsFixed(2);
        return ListTile(title: Text(o['wholesalerName'] ?? ''),
          subtitle: Text('${egp(o['bulkPrice'])} / ${o['bulkUnit'] ?? ''} • قطاعي ${egp(o['piecePrice'])}${(o['bulkPrice'] as num) > (min as num) ? ' — أغلى بـ $diff ج.م' : ' — الأرخص ✓'}'),
          trailing: ElevatedButton(onPressed: () { cart.add(o as Map<String, dynamic>, 'bulk', 1); Navigator.pop(context); }, child: const Text('اختر')));
      }),
    ]));
  }
}

// ---------- Multi-cart ----------
class MultiCartSheet extends StatefulWidget {
  const MultiCartSheet({super.key});
  @override
  State<MultiCartSheet> createState() => _MultiCartSheetState();
}
class _MultiCartSheetState extends State<MultiCartSheet> {
  final couponCtrl = TextEditingController();
  String msg = '';
  Future<void> checkout(String wsId) async {
    final c = cart.carts[wsId];
    if (c == null) return;
    final lines = c['lines'] as Map<String, dynamic>;
    try {
      final r = await Api.post('/cart/checkout', {
        'items': lines.entries.map((e) => {'offerId': (e.value['offer'] as Map)['id'], 'qty': e.value['qty'], 'mode': e.value['mode']}).toList(),
        'coupon': couponCtrl.text.isEmpty ? null : couponCtrl.text,
      });
      final saved = r['order']['tierSavings'] ?? 0;
      cart.clearWs(wsId);
      if (!mounted) return;
      toast(context, 'تم تأكيد طلب ${c['wsName']}! الإجمالي ${egp(r['order']['total'])} (وفّرت ${egp(saved)} بالكمية)');
      if (cart.cartCount == 0 && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => msg = 'خطأ: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (_, __) => DraggableScrollableSheet(expand: false, initialChildSize: 0.88, builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(controller: ctrl, children: [
          const Text('سلة مشترياتك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('اختار جملة أو قطاعي لكل صنف — والخصم بيكبر مع العدد', style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 8),
          ...cart.carts.entries.map((ws) {
            final lines = ws.value['lines'] as Map<String, dynamic>;
            return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(ws.value['wsName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(egp(cart.wsTotal(ws.key)), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (cart.wsSavings(ws.key) > 0) Text('وفّرت ${egp(cart.wsSavings(ws.key))}', style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ]),
              ...lines.entries.map((e) {
                final o = e.value['offer'] as Map;
                final m = e.value['mode'] as String;
                final b = bestTier(o, e.value['qty'] as int);
                return ListTile(dense: true,
                  title: Text(o['productName'], style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${modeLabel(m)} • ${egp(unitOf(o, m))} ${m == 'bulk' ? '/ كرتونة' : '/ قطعة'}${b != null ? ' • خصم ${b['discountPct']}%' : ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: () => cart.setQty(ws.key, e.key, (e.value['qty'] as int) - 1)),
                    Text('${e.value['qty']}'),
                    IconButton(icon: const Icon(Icons.add, size: 18), onPressed: () => cart.setQty(ws.key, e.key, (e.value['qty'] as int) + 1)),
                  ]));
              }),
              ElevatedButton(onPressed: () => checkout(ws.key), child: const Text('تأكيد الطلب')),
            ])));
          }),
          TextField(controller: couponCtrl, decoration: const InputDecoration(labelText: 'كوبون (جرّب AHLAN100)', border: OutlineInputBorder())), Text(msg, style: const TextStyle(color: Colors.red)),
        ]),
      )),
    );
  }
}

// ---------- Wholesale tab ----------
class WholesaleTab extends StatefulWidget {
  final void Function(int) onGo;
  const WholesaleTab({super.key, required this.onGo});
  @override
  State<WholesaleTab> createState() => _WholesaleTabState();
}
class _WholesaleTabState extends State<WholesaleTab> {
  Map? lastOrder;
  List bulkOffers = [];
  @override
  void initState() {
    super.initState();
    Api.get('/orders').then((r) { final l = (r['items'] as List); if (l.isNotEmpty) setState(() => lastOrder = l.first); }).catchError((_) {});
    Api.get('/products').then((r) {
      final all = (r['items'] as List);
      final seen = <String>{};
      setState(() => bulkOffers = all.where((o) => seen.add(o['productId'] as String)).take(6).toList());
    }).catchError((_) { setState(() => bulkOffers = DemoData.offers.take(6).toList()); });
  }
  @override
  Widget build(BuildContext context) {
    final d = (Widget w) => Directionality(textDirection: TextDirection.rtl, child: w);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const SearchPage()))),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: const Row(children: [Icon(Icons.search, color: Colors.grey), SizedBox(width: 8), Text('بتدور على منتج معين؟', style: TextStyle(color: Colors.grey))])))),
        IconButton(onPressed: () => showModalBottomSheet(context: context, builder: (_) => d(const NotifSheet())), icon: const Icon(Icons.notifications_none)),
      ]),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [mBlue, Color(0xFF003A8C)])),
        child: const Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('بابا عبدو جملة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19)),
            Text('اشتري بالكرتونة بسعر الجملة — وزوّد الكراتين والخصم يكبر', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          CircleAvatar(radius: 28, backgroundColor: Colors.white24, child: Icon(Icons.store, size: 34, color: Colors.white)),
        ])),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFD6E9FF), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('جملة بابا عبدو ✨', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: mBlue)),
            Text('اشتري بالكرتونة بسعر الجملة — اللي تتاجر بيه', style: TextStyle(color: Colors.black54, fontSize: 12)),
          ])),
          const CircleAvatar(radius: 32, backgroundColor: Colors.white, child: Icon(Icons.store, size: 38, color: Colors.green)),
        ])),
      const SizedBox(height: 6),
      ElevatedButton(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => d(const GuideModal())), child: const Text('اعرف أكتر — ازاي تطلب؟')),
      sectionHead('اقوي عروض بابا عبدو', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const OffersPage())))),
      GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const OffersPage()))),
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: bannerGreenBg, borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [
            CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.store, color: Colors.green)), SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('خصومات منتجات التجار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text('العروض متاحة لمدة محدودة', style: TextStyle(color: Colors.grey, fontSize: 12))])),
            CircleAvatar(backgroundColor: Colors.red, child: Text('%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ]))),
      sectionHead('تابع طلباتك', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const MyOrdersPage())))),
      GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const MyOrdersPage()))),
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Expanded(child: Text('طلباتك', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            if (lastOrder != null) Text(egp(lastOrder!['total']), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(width: 8), const CircleAvatar(backgroundColor: tileBg, child: Icon(Icons.shopping_cart, color: mBlue)),
          ]))),
      if (lastOrder != null)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('تتبع آخر طلب: ${lastOrder!['id'].toString().substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8), OrderTrackBar(stage: orderStage(lastOrder!['status'] as String?), cancelled: lastOrder!['status'] == 'cancelled'),
        ]))),
      sectionHead('تسوّق بالجملة', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const SearchPage())))),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.56),
        itemCount: bulkOffers.length,
        itemBuilder: (_, i) => ProductCardM(offer: bulkOffers[i] as Map<String, dynamic>, allOffers: bulkOffers, fixedMode: 'bulk'),
      ),
      sectionHead('تصفح الأقسام', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const CategoriesPage())))),
      const CatGridPreview(),
    ]);
  }
}

int orderStage(String? s) {
  switch (s) {
    case 'confirmed': return 0;
    case 'preparing': return 1;
    case 'shipping': return 2;
    case 'delivered': return 3;
    default: return 0;
  }
}

class OrderTrackBar extends StatelessWidget {
  final int stage;
  final bool cancelled;
  const OrderTrackBar({super.key, required this.stage, this.cancelled = false});
  @override
  Widget build(BuildContext context) {
    const steps = ['تأكيد', 'تجهيز', 'شحن', 'توصيل'];
    if (cancelled) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
        Icon(Icons.cancel, color: Colors.red, size: 18),
        SizedBox(width: 6),
        Text('تم إلغاء الطلب', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ]);
    }
    return Row(children: List.generate(steps.length * 2 - 1, (i) {
      if (i.isOdd) return Expanded(child: Container(height: 3, color: (i ~/ 2) < stage ? Colors.green : Colors.grey.shade300));
      final idx = i ~/ 2; final done = idx <= stage;
      return Column(children: [
        CircleAvatar(radius: 13, backgroundColor: done ? Colors.green : Colors.grey.shade300, child: Icon(done ? Icons.check : Icons.circle, size: 14, color: Colors.white)),
        Text(steps[idx], style: const TextStyle(fontSize: 10)),
      ]);
    }));
  }
}

class GuideModal extends StatefulWidget {
  const GuideModal({super.key});
  @override
  State<GuideModal> createState() => _GuideModalState();
}
class _GuideModalState extends State<GuideModal> {
  final steps = [
    'ابدأ من أقسام بابا عبدو واختار المنتجات اللي بتحتاجها 🔥',
    'لو عايز تشتري بالجملة اختار وضع جملة، ولو بالقطعة اختار قطاعي 🤩',
    'شوف سلاتك واكتب اسم المحل وعنوانك وخلص الطلب 🤑',
  ];
  Future<void> speakAll() async {
    try {
      final tts = FlutterTts();
      await tts.setLanguage('ar-EG');
      await tts.speak('ازاي تطلب من بابا عبدو؟ ${steps.join('. ')}');
    } catch (_) { if (mounted) toast(context, 'الصوت غير متاح على هذا الجهاز'); }
  }
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.9,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(controller: ctrl, children: [
          Row(children: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)), const Expanded(child: Text('ازاي تطلب من بابا عبدو؟', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), const SizedBox(width: 40)]),
          Center(child: ElevatedButton.icon(icon: const Icon(Icons.volume_up), label: const Text('اسمع الشرح'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black87), onPressed: speakAll)),
          const SizedBox(height: 8),
          ...steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14))),
              const SizedBox(width: 10),
              CircleAvatar(backgroundColor: Colors.grey.shade200, child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
          )),
          const SizedBox(height: 12),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: mBlue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.pop(context), child: const Text('تمام', style: TextStyle(fontSize: 17))),
        ]),
      ),
    );
  }
}

// ---------- Offers / orders ----------
class OffersPage extends StatefulWidget {
  const OffersPage({super.key});
  @override
  State<OffersPage> createState() => _OffersPageState();
}
class _OffersPageState extends State<OffersPage> {
  List hot = []; bool loading = true;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final r = await Api.get('/products?hot=1'); setState(() { hot = r['items']; loading = false; }); }
    catch (_) { setState(() { hot = DemoData.offers.where((o) => o['oldPrice'] != null).toList(); loading = false; }); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العروض'), centerTitle: true),
      body: const OffersGrid(),
    );
  }
}

// Offers grid body (also used as الرئيسية section content)
class OffersGrid extends StatefulWidget {
  const OffersGrid({super.key});
  @override
  State<OffersGrid> createState() => _OffersGridState();
}
class _OffersGridState extends State<OffersGrid> {
  List hot = []; List cats = []; List fallback = []; bool loading = true;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final h = await Api.get('/products?hot=1');
      final p = await Api.get('/products');
      final all = (p['items'] as List);
      final seen = <String>{};
      if (mounted) setState(() {
        hot = h['items'];
        cats = (p['categories'] as List).map((e) => e.toString()).toList();
        fallback = all.where((o) => seen.add(o['productId'] as String)).take(8).toList();
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        hot = DemoData.offers.where((o) => o['oldPrice'] != null).toList();
        cats = DemoData.categories;
        fallback = DemoData.offers;
        loading = false;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final d = (Widget w) => Directionality(textDirection: TextDirection.rtl, child: w);
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        // Colorful promo banner (old-app style)
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFFFF8A00), Color(0xFFE8321E)])),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🔥 عروض الأسبوع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              Text('خصومات الجملة والقطاعي — الكمية محدودة', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Text('%', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.red))),
          ])),
        sectionHead('🗂️ الأقسام', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const CategoriesPage())))),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.82),
          itemCount: cats.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(CategoryProducts(category: cats[i])))),
            child: Container(decoration: BoxDecoration(
                gradient: LinearGradient(colors: [tileBg, Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(14), border: Border.all(color: mBlue.withOpacity(0.15))),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(catIcons[cats[i]] ?? Icons.category, color: mBlue, size: 30),
                const SizedBox(height: 4), Text(cats[i], textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              ])),
          ),
        ),
        if (hot.isNotEmpty) ...[
          sectionHead('🎁 العروض المتوفرة', () {}),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: [Colors.orange.shade50, Colors.white])),
            child: GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.56),
              itemCount: hot.length, itemBuilder: (_, i) => ProductCardM(offer: hot[i] as Map<String, dynamic>, allOffers: hot)),
          ),
        ] else ...[
          // No offers? Still show products attractively
          Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [navy, Color(0xFF0B63E5)])),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✨ تشكيلة مختارة لك', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
              Text('أحسن الأصناف جملة وقطاعي — اطلب دلوقتي', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.56),
            itemCount: fallback.length, itemBuilder: (_, i) => ProductCardM(offer: fallback[i] as Map<String, dynamic>, allOffers: fallback)),
        ],
      ]),
    );
  }
}

class MyOrdersPage extends StatefulWidget {
  const MyOrdersPage({super.key});
  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}
class _MyOrdersPageState extends State<MyOrdersPage> {
  List orders = [];
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try { final r = await Api.get('/orders'); setState(() => orders = r['items'] ?? []); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتك'), centerTitle: true),
      body: RefreshIndicator(onRefresh: refresh, child: orders.isEmpty
        ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد طلبات بعد')))])
        : ListView.builder(padding: const EdgeInsets.all(12), itemCount: orders.length, itemBuilder: (_, i) {
            final o = orders[i];
            return Card(child: ExpansionTile(
              title: Text('طلب ${o['id'].toString().substring(0, 8)} — ${egp(o['total'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${o['createdAt'].toString().substring(0, 10)} — ${orderStatusAr(o['status'])}${(o['tierSavings'] ?? 0) > 0 ? ' — وفّرت ${egp(o['tierSavings'])}' : ''}'),
              children: [
                Padding(padding: const EdgeInsets.all(8), child: OrderTrackBar(stage: orderStage(o['status'] as String?), cancelled: o['status'] == 'cancelled')),
                ...((o['lines'] as List? ?? []).map((l) => ListTile(dense: true,
                  title: Text(l['productId']),
                  subtitle: Text('${modeLabel(l['mode'] ?? 'bulk')} • الكمية: ${l['qty']} × ${egp(l['price'])}${l['tier'] != null ? ' • خصم ${l['tier']['discountPct']}%' : ''}'),
                  trailing: Text(egp(l['lineTotal']))))),
              ]));
          })),
    );
  }
}

// ---------- More (no wallet; admin dashboard entry) ----------
class MorePage extends StatefulWidget {
  const MorePage({super.key});
  @override
  State<MorePage> createState() => _MorePageState();
}
class _MorePageState extends State<MorePage> {
  Map? me; List coupons = []; List myOrders = [];
  final complaintCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    Api.get('/auth/me').then((r) => setState(() => me = r)).catchError((_) {});
    Api.get('/coupons').then((r) => setState(() => coupons = r['items'])).catchError((_) => setState(() => coupons = [{'code': 'AHLAN100', 'discount': 100, 'minOrder': 1000}]));
    Api.get('/orders').then((r) => setState(() => myOrders = (r['items'] as List).take(5).toList())).catchError((_) {});
  }
  @override
  Widget build(BuildContext context) {
    final d = (Widget w) => Directionality(textDirection: TextDirection.rtl, child: w);
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text(me?['shopName'] ?? 'تاجر بابا عبدو', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          const Chip(label: Text('🇪🇬 مصر')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => d(const MyOrdersPage()))),
            child: moreTile(Icons.shopping_cart, 'طلباتك (${myOrders.length})'))),
          const SizedBox(width: 10),
          Expanded(child: moreTile(Icons.confirmation_number, 'كوبونات خصم (${coupons.length})')),
        ]),
        const SizedBox(height: 10),
        menuRow(Icons.track_changes, 'أهدافك', onTap: () => showDialog(context: context, builder: (_) => d(AlertDialog(title: const Text('أهدافك'),
          content: Text('طلباتك: ${me?['stats']?['orderCount'] ?? 0} — نقاطك: ${me?['points'] ?? 0}\nاطلب 5 مرات أسبوعياً واكسب 100 نقطة'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('تمام'))])))),
        menuRow(Icons.forum, 'الشكاوي والاقتراحات', onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => d(ComplaintSheet()))),
        menuRow(Icons.settings, 'الإعدادات', onTap: () => showModalBottomSheet(context: context, builder: (_) => d(const SettingsSheet()))),
        const SizedBox(height: 8),
        const Text('الكوبونات', style: TextStyle(fontWeight: FontWeight.bold)),
        ...coupons.map((c) => ListTile(dense: true, title: SelectableText(c['code']), subtitle: Text('خصم ${c['discount'] ?? '${c['discountPct']}%'} — حد أدنى ${c['minOrder']}'))),
        const SizedBox(height: 24),
        const Center(child: Text('1.0.0', style: TextStyle(color: Colors.grey))),
      ]),
    );
  }
  Widget moreTile(IconData icon, String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        CircleAvatar(backgroundColor: tileBg, child: Icon(icon, color: mBlue)),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
  }
  Widget menuRow(IconData icon, String title, {Widget? trailing, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))), if (trailing != null) trailing, const SizedBox(width: 8), Icon(icon, color: Colors.black87)])),
    );
  }
}

class ComplaintSheet extends StatefulWidget {
  const ComplaintSheet({super.key});
  @override
  State<ComplaintSheet> createState() => _ComplaintSheetState();
}
class _ComplaintSheetState extends State<ComplaintSheet> {
  final ctrl = TextEditingController();
  List history = [];
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    Api.get('/complaints').then((r) {
      if (mounted) setState(() { history = r['items'] ?? []; loaded = true; });
    }).catchError((_) { if (mounted) setState(() => loaded = true); });
  }
  Future<void> send() async {
    if (ctrl.text.trim().isEmpty) return;
    try {
      await Api.post('/complaints', {'subject': 'شكوى', 'message': ctrl.text});
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'تم الإرسال — هنتواصل معاك قريب');
    } catch (e) { if (mounted) toast(context, 'تعذر الإرسال: $e'); }
  }
  @override
  Widget build(BuildContext context) {
    return Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('الشكاوي والاقتراحات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (history.isNotEmpty) ...[
          const Text('شكاياتك السابقة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: mBlue)),
          const SizedBox(height: 4),
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: 180), child: ListView(
            shrinkWrap: true,
            children: history.take(10).map((c) => Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text((c['message'] ?? ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                Chip(label: Text(c['status'] == 'open' ? 'مفتوحة' : 'تم الرد', style: const TextStyle(fontSize: 10)),
                  backgroundColor: c['status'] == 'open' ? Colors.orange.shade100 : Colors.green.shade100, padding: EdgeInsets.zero, labelPadding: const EdgeInsets.symmetric(horizontal: 6)),
              ]),
              if (c['adminReply'] != null) ...[
                const SizedBox(height: 4),
                Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: bannerGreenBg, borderRadius: BorderRadius.circular(10)),
                  child: Text('رد البائع: ${c['adminReply']}', style: const TextStyle(fontSize: 12, color: Colors.black87))),
              ],
              Text((c['createdAt'] ?? '').toString().substring(0, 10), style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ])))).toList(),
          )),
          const SizedBox(height: 8),
        ],
        TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اكتب شكواك أو اقتراحك...')),
        const SizedBox(height: 8),
        ElevatedButton(child: const Text('إرسال'), onPressed: send),
      ]));
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}
class _SettingsSheetState extends State<SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('الإعدادات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const ListTile(dense: true, title: Text('الدولة / المنطقة'), subtitle: Text('مصر (EGP ج.م)'), trailing: Text('🇪🇬')),
      const ListTile(dense: true, title: Text('متجر المورد'), subtitle: Text('بابا عبدو — جملة وقطاعي')),
      ElevatedButton(child: const Text('تم'), onPressed: () {
        if (mounted) Navigator.pop(context);
      }),
    ]));
  }
}
