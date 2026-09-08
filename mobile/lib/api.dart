import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Api {
  // Production backend on Render. For local testing change to your PC's IP (or in-app: المزيد -> الإعدادات).
  static String base = 'https://babaabdo-backend.onrender.com/api/v1';
  static String? token;

  static Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    final b = p.getString('base');
    if (b != null && b.isNotEmpty) base = b;
  }

  static Future<void> saveToken(String t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
  }

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        'Idempotency-Key': DateTime.now().microsecondsSinceEpoch.toString(),
      };

  static Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: headers);
    if (r.statusCode >= 400) throw Exception('${r.statusCode}: ${r.body}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(Uri.parse('$base$path'), headers: headers, body: jsonEncode(body));
    if (r.statusCode >= 400) throw Exception('${r.statusCode}: ${r.body}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }
}

// Demo fallback so the app is browsable offline / without backend (spec: offline mode).
class DemoData {
  static final categories = ['مشروبات', 'مبردات ومجمدات', 'بقالة', 'منظفات ومطهرات', 'صابون', 'حلويات وشوكولاتة', 'سايب', 'مأكولات أساسية', 'شيبسي ومقرمشات', 'ورقيات وحفاضات', 'مستهلكات وبطاريات', 'عناية شخصية', 'جبن والبان', 'مياه معدنية', 'ياميش رمضان', 'ألبان'];
  static const demoTiers = [{'minQty': 5, 'discountPct': 3}, {'minQty': 12, 'discountPct': 7}, {'minQty': 24, 'discountPct': 12}];
  static final offers = [
    {'id': 'o01', 'productId': 'p01', 'productName': 'بيبسي كانز - 355 مل', 'category': 'مشروبات', 'brand': 'بيبسي', 'unitName': 'كانز', 'bulkUnit': 'كرتونة (24)', 'bulkQty': 24, 'bulkPrice': 325, 'piecePrice': 15.56, 'tiers': demoTiers, 'oldPrice': 350, 'discountPct': 7, 'unitPrice': 13.54, 'sellingFast': true, 'shortage': false, 'source': 'direct', 'wholesalerName': 'بابا عبدو', 'wholesalerId': 'ws0', 'stock': 800},
    {'id': 'o03', 'productId': 'p02', 'productName': 'بيبسي - 2.43 لتر', 'category': 'مشروبات', 'brand': 'بيبسي', 'unitName': 'ازازة', 'bulkUnit': 'كرتونة (6)', 'bulkQty': 6, 'bulkPrice': 245, 'piecePrice': 46.96, 'tiers': demoTiers, 'oldPrice': 260, 'discountPct': 6, 'unitPrice': 40.83, 'sellingFast': true, 'shortage': false, 'source': 'direct', 'wholesalerName': 'بابا عبدو', 'wholesalerId': 'ws0', 'stock': 600},
    {'id': 'o11', 'productId': 'p10', 'productName': 'لبن بخيره - 500 مل', 'category': 'ألبان', 'brand': 'بخيره', 'unitName': 'كيس', 'bulkUnit': 'كرتونة (24)', 'bulkQty': 24, 'bulkPrice': 514.25, 'piecePrice': 24.64, 'tiers': demoTiers, 'unitPrice': 21.43, 'sellingFast': true, 'shortage': false, 'source': 'direct', 'wholesalerName': 'بابا عبدو', 'wholesalerId': 'ws0', 'stock': 900},
    {'id': 'o13', 'productId': 'p11', 'productName': 'لبن بخيره - 1 لتر', 'category': 'ألبان', 'brand': 'بخيره', 'unitName': 'كيس', 'bulkUnit': 'كرتونة (12)', 'bulkQty': 12, 'bulkPrice': 460.75, 'piecePrice': 44.16, 'tiers': demoTiers, 'unitPrice': 38.40, 'sellingFast': true, 'shortage': false, 'source': 'direct', 'wholesalerName': 'بابا عبدو', 'wholesalerId': 'ws0', 'stock': 850},
    {'id': 'o44', 'productId': 'p40', 'productName': 'حفاضات بيبي لاند مقاس 2 - 40 حفاضة', 'category': 'ورقيات وحفاضات', 'brand': 'بيبي لاند', 'unitName': 'باكت', 'bulkUnit': 'باكت (40)', 'bulkQty': 40, 'bulkPrice': 145, 'piecePrice': 4.17, 'tiers': demoTiers, 'unitPrice': 3.63, 'sellingFast': true, 'shortage': false, 'source': 'exclusive', 'wholesalerName': 'أصناف حصرية', 'wholesalerId': 'ws4', 'stock': 500},
    {'id': 'o45', 'productId': 'p41', 'productName': 'حفاضات بيبي لاند مقاس 3 - 40 حفاضة', 'category': 'ورقيات وحفاضات', 'brand': 'بيبي لاند', 'unitName': 'باكت', 'bulkUnit': 'باكت (40)', 'bulkQty': 40, 'bulkPrice': 168, 'piecePrice': 4.83, 'tiers': demoTiers, 'unitPrice': 4.2, 'sellingFast': true, 'shortage': false, 'source': 'exclusive', 'wholesalerName': 'أصناف حصرية', 'wholesalerId': 'ws4', 'stock': 450},
    {'id': 'o38', 'productId': 'p35', 'productName': 'اريال - 2.5 كجم', 'category': 'منظفات ومطهرات', 'brand': 'اريال', 'unitName': 'كيس', 'bulkUnit': 'كرتونة (4)', 'bulkQty': 4, 'bulkPrice': 770, 'piecePrice': 221.38, 'tiers': demoTiers, 'oldPrice': 860, 'discountPct': 10, 'unitPrice': 192.5, 'sellingFast': true, 'shortage': false, 'source': 'direct', 'wholesalerName': 'بابا عبدو', 'wholesalerId': 'ws0', 'stock': 400},
    {'id': 'o16', 'productId': 'p12', 'productName': 'لبن جهينة - 1 لتر', 'category': 'ألبان', 'brand': 'جهينة', 'unitName': 'علبة', 'bulkUnit': 'شرينك (12)', 'bulkQty': 12, 'bulkPrice': 555, 'piecePrice': 53.19, 'tiers': demoTiers, 'unitPrice': 46.25, 'sellingFast': true, 'shortage': true, 'source': 'marketplace', 'wholesalerName': 'مؤسسة البركة', 'wholesalerId': 'ws2', 'stock': 25},
  ];
  static final wholesalers = [
    {'id': 'ws0', 'name': 'بابا عبدو', 'type': 'direct', 'minOrderValue': 0, 'deliveryEta': 'نفس اليوم', 'rating': 4.9, 'zone': 'كل المناطق'},
    {'id': 'ws1', 'name': 'شركة النور للجملة', 'type': 'marketplace', 'minOrderValue': 1000, 'deliveryEta': '24-48 ساعة', 'rating': 4.7, 'zone': 'القاهرة'},
    {'id': 'ws2', 'name': 'مؤسسة البركة', 'type': 'marketplace', 'minOrderValue': 500, 'deliveryEta': 'نفس اليوم', 'rating': 4.5, 'zone': 'الجيزة'},
    {'id': 'ws3', 'name': 'الشركة المتحدة للتوريدات', 'type': 'marketplace', 'minOrderValue': 2000, 'deliveryEta': '48-72 ساعة', 'rating': 4.8, 'zone': 'القاهرة الكبرى'},
    {'id': 'ws4', 'name': 'أصناف حصرية', 'type': 'exclusive', 'minOrderValue': 0, 'deliveryEta': '24 ساعة', 'rating': 5.0, 'zone': 'كل المناطق'},
  ];
}
