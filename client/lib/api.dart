import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class ApiService {
  static void Function(String message)? onOfflineToast;
  static DateTime? _lastOfflineFeedbackAt;

  static const _homeCachePrefix = 'storefront_home_v5_';
  // v6 invalidates older result caches after the circle-result filtering fixes.
  // v7 includes trend/hashtag/meta payloads used by the product-card renderer.
  static const _feedCachePrefix = 'storefront_feed_v8_';
  String token='';
  final String baseUrl;
  ApiService():baseUrl=(const String.fromEnvironment('API_BASE_URL',defaultValue:'https://takhfidsh.alattab.site/api/v1')).replaceAll(RegExp(r'/$'),'');
  Future<void> restore() async { final p=await SharedPreferences.getInstance(); token=p.getString('access_token')??''; }
  String url(String? value){
    if(value==null||value.isEmpty)return '';
    if(value.startsWith('http://')||value.startsWith('https://'))return value;
    final u=Uri.parse(baseUrl);
    if(value.startsWith('/'))return u.scheme+'://'+u.authority+value;
    return baseUrl+'/'+value;
  }
  Map<String,String> headers()=>{'Accept':'application/json',if(token.isNotEmpty)'Authorization':'Bearer '+token};
  dynamic decode(http.Response r){
    dynamic x;
    try { x=jsonDecode(utf8.decode(r.bodyBytes)); } catch (_) { x={}; }
    if(r.statusCode>=200&&r.statusCode<300)return x;
    if(x is Map&&x['detail']!=null)throw Exception(x['detail'].toString());
    if(x is Map&&x['error']!=null)throw Exception(x['error'].toString());
    throw Exception('تعذر تنفيذ الطلب (undefined)');
  }

  bool _isNetworkFailure(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('websocketexception') ||
        s.contains('clientexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('network is unreachable') ||
        s.contains('handshakeexception') ||
        s.contains('httpexception') ||
        s.contains('connection closed') ||
        s.contains('connection terminated') ||
        s.contains('timed out') ||
        s.contains('timeout');
  }

  Exception _offlineException() {
    const message = 'أنت غير متصل بالإنترنت حاليًا. حاول مرة أخرى عند عودة الاتصال.';
    final now = DateTime.now();
    final last = _lastOfflineFeedbackAt;
    if (last == null || now.difference(last) > const Duration(seconds: 4)) {
      _lastOfflineFeedbackAt = now;
      onOfflineToast?.call(message);
    }
    return Exception(message);
  }
  Future<dynamic> get(String p,{Map<String,String>? q}) async {
    try {
      return decode(await http.get(
        Uri.parse(baseUrl+p).replace(queryParameters:q),
        headers:headers(),
      ).timeout(const Duration(seconds:25)));
    } catch(e) {
      if (_isNetworkFailure(e)) throw _offlineException();
      rethrow;
    }
  }
  Future<dynamic> post(String p,Map<String,dynamic> b) async {
    try {
      return decode(await http.post(
        Uri.parse(baseUrl+p),
        headers:{...headers(),'Content-Type':'application/json'},
        body:jsonEncode(b),
      ).timeout(const Duration(seconds:25)));
    } catch(e) {
      if (_isNetworkFailure(e)) throw _offlineException();
      rethrow;
    }
  }
  Future<dynamic> patch(String p,Map<String,dynamic> b) async {
    try {
      return decode(await http.patch(
        Uri.parse(baseUrl+p),
        headers:{...headers(),'Content-Type':'application/json'},
        body:jsonEncode(b),
      ).timeout(const Duration(seconds:25)));
    } catch(e) {
      if (_isNetworkFailure(e)) throw _offlineException();
      rethrow;
    }
  }
  Future<dynamic> delete(String p) async {
    try {
      return decode(await http.delete(
        Uri.parse(baseUrl+p),
        headers:headers(),
      ).timeout(const Duration(seconds:25)));
    } catch(e) {
      if (_isNetworkFailure(e)) throw _offlineException();
      rethrow;
    }
  }

  String _scopeCacheKey(int? rootCategoryId) =>
      (rootCategoryId ?? -1).toString();

  String _feedCacheKey({
    int? category,
    List<int>? categoryIds,
    int? circleId,
    int? hashtagId,
    List<int>? hashtagIds,
    int? sideCategoryId,
    String q='',
    List<int>? filterValueIds,
    String sort='recommended',
    String? minPrice,
    String? maxPrice,
    int? currencyId,
    String? discoveryTab,
    String? minRating,
  }) {
    final categories = <int>{
      if (category != null && category > 0) category,
      ...?categoryIds?.where((id) => id > 0),
    }.toList()..sort();
    final hashtags = <int>{
      if (hashtagId != null && hashtagId > 0) hashtagId,
      ...?hashtagIds?.where((id) => id > 0),
    }.toList()..sort();
    final filters = filterValueIds == null
        ? <int>[]
        : List<int>.from(filterValueIds)..sort();
    return [
      category ?? 0,
      categories.join(','),
      circleId ?? 0,
      hashtagId ?? 0,
      hashtags.join(','),
      sideCategoryId ?? 0,
      q.trim(),
      filters.join(','),
      sort,
      minPrice?.trim() ?? '',
      maxPrice?.trim() ?? '',
      currencyId ?? 0,
      discoveryTab?.trim() ?? '',
      minRating?.trim() ?? '',
    ].join('|');
  }

  Future<void> _saveJson(String key, dynamic value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(value));
    } catch (_) {}
  }

  Future<dynamic> _readJson(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<ProductModel>> _decodeProducts(dynamic value) async {
    if (value is! List) return <ProductModel>[];
    return value.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      if (m['image_url'] != null) {
        m['image_url'] = url(m['image_url'].toString());
      }
      if (m['images'] is List) {
        m['images'] = (m['images'] as List)
            .whereType<String>()
            .where((x) => x.isNotEmpty)
            .map(url)
            .toList();
      }
      return ProductModel.fromJson(m);
    }).toList();
  }

  Future<List<CategoryModel>> roots()async{
    final d=await get('/catalog/categories');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>CategoryModel.fromJson(Map<String,dynamic>.from(e))).where((x)=>x.parentId==null).toList();
  }
  Future<List<CategoryModel>> allCategories()async{
    final d=await get('/catalog/categories');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>CategoryModel.fromJson(Map<String,dynamic>.from(e))).toList();
  }
  Future<Map<String,dynamic>> trendsPage() async {
    final d = Map<String, dynamic>.from(
      await get(
        '/catalog/trends',
        q: {'_trends_ts': DateTime.now().millisecondsSinceEpoch.toString()},
      ),
    );
    return d;
  }

  Future<Map<String, dynamic>?> cachedHome({int? rootCategoryId}) async {
    final value = await _readJson(
      _homeCachePrefix + _scopeCacheKey(rootCategoryId),
    );
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<List<ProductModel>> cachedFeed({
    int? category,
    List<int>? categoryIds,
    int? circleId,
    int? hashtagId,
    List<int>? hashtagIds,
    int? sideCategoryId,
    String q='',
    List<int>? filterValueIds,
    String sort='recommended',
    String? minPrice,
    String? maxPrice,
    int? currencyId,
    String? discoveryTab,
    String? minRating,
  }) async {
    final cacheKey = _feedCachePrefix + _feedCacheKey(
      category: category,
      categoryIds: categoryIds,
      circleId: circleId,
      hashtagId: hashtagId,
      hashtagIds: hashtagIds,
      sideCategoryId: sideCategoryId,
      q: q,
      filterValueIds: filterValueIds,
      sort: sort,
      minPrice: minPrice,
      maxPrice: maxPrice,
      currencyId: currencyId,
      discoveryTab: discoveryTab,
      minRating: minRating,
    );
    return _decodeProducts(await _readJson(cacheKey));
  }

  Future<Map<String,dynamic>> home({int? rootCategoryId}) async {
    final q = <String,String>{
      '_home_ts': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    if (rootCategoryId != null) {
      q['root_category_id'] = rootCategoryId.toString();
    }
    final cacheKey = _homeCachePrefix + _scopeCacheKey(rootCategoryId);
    try {
      final result = Map<String,dynamic>.from(
        await get('/storefront/home', q: q),
      );
      await _saveJson(cacheKey, result);
      return result;
    } catch (_) {
      final cached = await _readJson(cacheKey);
      if (cached is Map) {
        return Map<String,dynamic>.from(cached);
      }
      rethrow;
    }
  }
  Future<List<Map<String,dynamic>>> sideCategories({int? rootId})async{
    final d=await get('/storefront/home');
    final rows=((d['side_categories'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(rootId==null)return rows;
    return rows.where((e)=>int.tryParse((e['root_category_id']??'').toString())==rootId).toList();
  }
  Future<List<Map<String,dynamic>>> categoryFilters(
    int categoryId, {
    bool includeDescendants = false,
  }) async {
    final d=await get(
      '/catalog/categories/'+categoryId.toString()+'/filters',
      q: includeDescendants ? {'include_descendants':'1'} : null,
    );
    return ((d['items'] as List?)??const[])
        .whereType<Map>()
        .map((e)=>Map<String,dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String,dynamic>>> scopedFilters({
    List<int>? categoryIds,
    int? circleId,
    List<int>? hashtagIds,
    int? sideCategoryId,
  }) async {
    final q = <String,String>{};
    final categories = <int>{
      ...?categoryIds?.where((id) => id > 0),
    }.toList()..sort();
    final hashtags = <int>{
      ...?hashtagIds?.where((id) => id > 0),
    }.toList()..sort();

    if (categories.isNotEmpty) q['category_ids'] = categories.join(',');
    if (circleId != null && circleId > 0) q['circle_id'] = circleId.toString();
    if (hashtags.isNotEmpty) q['hashtag_ids'] = hashtags.join(',');
    if (sideCategoryId != null && sideCategoryId > 0) {
      q['side_category_id'] = sideCategoryId.toString();
    }
    // Avoid stale intermediary/proxy responses when the result scope changes
    // (especially between sibling circles).
    q['_filters_ts'] = DateTime.now().millisecondsSinceEpoch.toString();

    final d = await get('/catalog/products/filters', q: q);
    return ((d['items'] as List?)??const[])
        .whereType<Map>()
        .map((e)=>Map<String,dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String,dynamic>>> categoryFiltersForCategories(
    List<int> categoryIds, {
    bool includeDescendants = true,
  }) async {
    final ids = <int>{
      ...categoryIds.where((id) => id > 0),
    }.toList()..sort();
    if (ids.isEmpty) return <Map<String,dynamic>>[];

    final responses = await Future.wait(
      ids.map(
        (id) => categoryFilters(
          id,
          includeDescendants: includeDescendants,
        ),
      ),
    );

    final merged = <String, Map<String,dynamic>>{};
    for (final filters in responses) {
      for (final filter in filters) {
        final name = (filter['name'] ?? '').toString().trim();
        final type = (filter['filter_type'] ?? '').toString().trim();
        final key = (name.toLowerCase()+'|'+type.toLowerCase());
        final target = merged.putIfAbsent(
          key,
          () => <String,dynamic>{
            'id': filter['id'],
            'name': filter['name'],
            'filter_type': filter['filter_type'],
            'values': <Map<String,dynamic>>[],
          },
        );
        final existing = <int>{
          for (final value in (target['values'] as List))
            if (value is Map) int.tryParse((value['id'] ?? '').toString()) ?? 0,
        };
        for (final value in ((filter['values'] as List?) ?? const [])) {
          if (value is! Map) continue;
          final id = int.tryParse((value['id'] ?? '').toString()) ?? 0;
          if (id <= 0 || existing.contains(id)) continue;
          (target['values'] as List).add(Map<String,dynamic>.from(value));
          existing.add(id);
        }
      }
    }
    return merged.values.toList();
  }
  Future<Map<String,dynamic>> productReference(int productId)async{
    final d=await get('/catalog/reference/product-config',q:{'product_id':productId.toString()});
    return d['item'] is Map?Map<String,dynamic>.from(d['item']):Map<String,dynamic>.from(d);
  }
  Future<List<ProductModel>> feed({
    int? category,
    List<int>? categoryIds,
    int? circleId,
    int? hashtagId,
    List<int>? hashtagIds,
    int? sideCategoryId,
    String q='',
    List<int>? filterValueIds,
    String sort='recommended',
    String? minPrice,
    String? maxPrice,
    int? currencyId,
    String? discoveryTab,
    String? minRating,
  }) async {
    final forceFreshRandom = sort == 'random' || sort == 'shuffle';
    final qp=<String,String>{
      'limit':'100',
      'sort':sort,
      if (forceFreshRandom)
        '_random_ts': DateTime.now().microsecondsSinceEpoch.toString(),
    };
    if(category!=null)qp['category_id']=category.toString();
    if(categoryIds!=null&&categoryIds.isNotEmpty)qp['category_ids']=categoryIds.join(',');
    if(circleId!=null)qp['circle_id']=circleId.toString();
    if(hashtagId!=null)qp['hashtag_id']=hashtagId.toString();
    if(hashtagIds!=null&&hashtagIds.isNotEmpty)qp['hashtag_ids']=hashtagIds.join(',');
    if(sideCategoryId!=null)qp['side_category_id']=sideCategoryId.toString();
    if(q.trim().isNotEmpty)qp['q']=q.trim();
    if(filterValueIds!=null&&filterValueIds.isNotEmpty)qp['filter_value_ids']=filterValueIds.join(',');
    if(minPrice!=null&&minPrice.trim().isNotEmpty)qp['min_price']=minPrice.trim();
    if(maxPrice!=null&&maxPrice.trim().isNotEmpty)qp['max_price']=maxPrice.trim();
    if(currencyId!=null)qp['currency_id']=currencyId.toString();
    if(discoveryTab!=null&&discoveryTab.trim().isNotEmpty)qp['discovery_tab']=discoveryTab.trim();
    if(minRating!=null&&minRating.trim().isNotEmpty)qp['min_rating']=minRating.trim();

    final cacheKey = _feedCachePrefix + _feedCacheKey(
      category: category,
      categoryIds: categoryIds,
      circleId: circleId,
      hashtagId: hashtagId,
      hashtagIds: hashtagIds,
      sideCategoryId: sideCategoryId,
      q: q,
      filterValueIds: filterValueIds,
      sort: sort,
      minPrice: minPrice,
      maxPrice: maxPrice,
      currencyId: currencyId,
      discoveryTab: discoveryTab,
      minRating: minRating,
    );

    try {
      final d=Map<String,dynamic>.from(
        await get('/catalog/products/feed',q:qp),
      );
      final items = ((d['items'] as List?)??const[])
          .whereType<Map>()
          .map((e)=>Map<String,dynamic>.from(e))
          .toList();
      await _saveJson(cacheKey, items);
      return _decodeProducts(items);
    } catch (_) {
      final cached = await _readJson(cacheKey);
      return _decodeProducts(cached);
    }
  }

  Future<Map<String,dynamic>> product(int id,{int? currencyId})async{
    final d=Map<String,dynamic>.from(await get('/catalog/products/'+id.toString(),q:currencyId==null?null:{'currency_id':currencyId.toString()}));
    if(d['item'] is Map){
      final m=Map<String,dynamic>.from(d['item']);
      if(m['media'] is List)m['media']=(m['media'] as List).whereType<Map>().map((e){
        final x=Map<String,dynamic>.from(e);if(x['url']!=null)x['url']=url(x['url'].toString());return x;
      }).toList();
      d['item']=m;
    }
    return d;
  }
  Future<Map<String,dynamic>> checkPhone(String phone) async {
    final d = Map<String, dynamic>.from(
      await post('/customer/auth/check-phone', {'phone': phone}),
    );
    final item = d['item'];
    return item is Map ? Map<String, dynamic>.from(item) : d;
  }

  Future<Map<String,dynamic>> passwordLogin(String phone, String password) async {
    final d=Map<String,dynamic>.from(await post('/customer/auth/password/login',{
      'phone':phone,'password':password,'device_id':'flutter-client',
    }));
    final item=d['item'] is Map?Map<String,dynamic>.from(d['item']):d;
    token=item['access_token']?.toString()??'';
    final p=await SharedPreferences.getInstance();
    if(token.isNotEmpty) await p.setString('access_token',token);
    return d;
  }

  Future<Map<String,dynamic>> requestOtp(String phone,{String purpose='login'})async{
    final d=Map<String,dynamic>.from(await post('/customer/auth/request-otp',{'phone':phone,'purpose':purpose}));
    final item=d['item'];
    if(item is Map)return Map<String,dynamic>.from(item);
    return d;
  }
  Future<Map<String,dynamic>> verifyOtp(int id,String code,{String? phone,Map<String,dynamic>? registration})async{
    final d=Map<String,dynamic>.from(await post('/customer/auth/verify-otp',{
      'otp_request_id':id,
      'code':code,
      if(phone!=null&&phone.trim().isNotEmpty)'phone':phone.trim(),
      if(registration!=null)'registration':registration,
      'device_id':'flutter-client',
    }));
    final item=d['item'] is Map?Map<String,dynamic>.from(d['item']):d;
    token=item['access_token']?.toString()??'';
    final p=await SharedPreferences.getInstance();
    if(token.isNotEmpty)await p.setString('access_token',token);
    return d;
  }
  Future<Map<String,dynamic>> setMyPassword(
    String password, {
    String? currentPassword,
  }) async =>
      Map<String,dynamic>.from(
        await post('/customer/me/password', {
          'new_password': password,
          if (currentPassword != null && currentPassword.trim().isNotEmpty)
            'current_password': currentPassword.trim(),
        }),
      );

  Future<Map<String,dynamic>> passwordResetRequest(String phone) async {
    final d=Map<String,dynamic>.from(await post('/customer/auth/password/request-reset',{'phone':phone}));
    final item=d['item'];
    return item is Map?Map<String,dynamic>.from(item):d;
  }

  Future<Map<String,dynamic>> passwordReset(int requestId,String code,String newPassword) async =>
      Map<String,dynamic>.from(await post('/customer/auth/password/reset',{
        'otp_request_id':requestId,'code':code,'new_password':newPassword,
      }));

  Future<Map<String,dynamic>> me()async=>Map<String,dynamic>.from(await get('/customer/me'));
  Future<Map<String,dynamic>> updateMe(Map<String,dynamic> body)async=>Map<String,dynamic>.from(await patch('/customer/me',body));

  Future<Map<String,dynamic>> requestPhoneChange({required String phone,required String password})async=>
      Map<String,dynamic>.from(await post('/customer/me/phone/change-request',{'phone':phone,'password':password}));

  Future<Map<String,dynamic>> verifyPhoneChange(int otpRequestId,String code,{String? phone})async=>
      Map<String,dynamic>.from(await post('/customer/me/phone/verify-change',{
        'otp_request_id':otpRequestId,
        'code':code,
        if(phone!=null&&phone.trim().isNotEmpty)'phone':phone.trim(),
      }));

  Future<Map<String,dynamic>> applyReferral(String code)async=>
      Map<String,dynamic>.from(await post('/customer/me/referral',{'code':code}));

  Future<Map<String,dynamic>> referrals()async=>
      Map<String,dynamic>.from(await get('/customer/me/referrals'));
  Future<Map<String,dynamic>> acceptPrivacy()async=>Map<String,dynamic>.from(await post('/customer/me/privacy-acceptance',{}));
  Future<List<Map<String,dynamic>>> addresses()async{
    final d=await get('/customer/me/addresses');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> addAddress(Map<String,dynamic> b)async=>Map<String,dynamic>.from(await post('/customer/me/addresses',b));
  Future<Map<String,dynamic>> updateAddress(int id,Map<String,dynamic> b)async=>Map<String,dynamic>.from(await patch('/customer/me/addresses/'+id.toString(),b));
  Future<void> deleteAddress(int id)async{await delete('/customer/me/addresses/'+id.toString());}
  Future<List<Map<String,dynamic>>> countries()async{
    final d=await get('/geo/countries');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> regions({int? countryId})async{
    final d=await get('/geo/regions',q:countryId==null?null:{'country_id':countryId.toString()});
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> cities({int? regionId})async{
    final d=await get('/geo/cities',q:regionId==null?null:{'region_id':regionId.toString()});
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> cityAreas({int? cityId})async{
    final d=await get('/geo/city-areas',q:cityId==null?null:{'city_id':cityId.toString()});
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> currencies()async{
    final d=await get('/pricing/currencies');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> pricingContext({int? cityId,int? areaId,int? currencyId})async{
    final q=<String,String>{};
    if(cityId!=null)q['city_id']=cityId.toString();
    if(areaId!=null)q['area_id']=areaId.toString();
    if(currencyId!=null)q['currency_id']=currencyId.toString();
    return Map<String,dynamic>.from(await get('/pricing/context',q:q.isEmpty?null:q));
  }
  Future<Map<String,dynamic>> cart({int? currencyId})async{
    final d=Map<String,dynamic>.from(await get('/commerce/me/cart',q:currencyId==null?null:{'currency_id':currencyId.toString()}));
    if(d['item'] is Map){
      final m=Map<String,dynamic>.from(d['item']);
      if(m['items'] is List)m['items']=(m['items'] as List).whereType<Map>().map((e){
        final x=Map<String,dynamic>.from(e);if(x['image_url']!=null)x['image_url']=url(x['image_url'].toString());return x;
      }).toList();
      d['item']=m;
    }
    return d;
  }
  Future<void> addCart(int variant,[int qty=1,Map<String,dynamic>? selectedOptions])async{
    await post('/commerce/me/cart/items',{
      'variant_id':variant,'qty':qty,
      if(selectedOptions!=null)'selected_options':selectedOptions,
    });
  }
  Future<void> cartQty(int id,int qty)async{await patch('/commerce/me/cart/items/'+id.toString(),{'qty':qty});}
  Future<void> removeCart(int id) async {
    await delete('/commerce/me/cart/items/' + id.toString());
  }
  Future<void> clearCart() async { await delete('/commerce/me/cart'); }
  Future<List<Map<String,dynamic>>> orders()async{
    final d=await get('/commerce/me/orders');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> order(int id)async=>Map<String,dynamic>.from(await get('/commerce/me/orders/'+id.toString()+'/detail'));
  Future<Map<String,dynamic>> updateOrder(int id,Map<String,dynamic> body)async=>Map<String,dynamic>.from(await patch('/commerce/me/orders/'+id.toString(),body));
  Future<Map<String,dynamic>> cancelOrder(int id) async =>
      Map<String,dynamic>.from(await post('/commerce/me/orders/'+id.toString()+'/cancel',{}));
  Future<Map<String,dynamic>> recordOrderPayment(
    int orderId, {
    required int methodId,
    String? amount,
    int? currencyId,
  }) async => Map<String,dynamic>.from(
    await post('/commerce/me/orders/'+orderId.toString()+'/payment',{
      'method_id':methodId,
      if(amount!=null&&amount.trim().isNotEmpty)'amount':amount.trim(),
      if(currencyId!=null)'currency_id':currencyId,
    }),
  );
  Future<Map<String,dynamic>> createOrder(int addressId,List<Map<String,dynamic>> items,{int? shippingMethodId,int? currencyId,String? customerNote}) async =>
      Map<String,dynamic>.from(await post('/commerce/orders',{
        'address_id':addressId,'items':items,
        if(shippingMethodId!=null)'shipping_method_id':shippingMethodId,
        if(currencyId!=null)'currency_id':currencyId,
        if(customerNote!=null&&customerNote.trim().isNotEmpty)'customer_note':customerNote.trim(),
      }));
  Future<List<Map<String,dynamic>>> shippingMethods()async{
    final d=await get('/commerce/shipping-methods');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> wallet({int? currencyId}) async {
    final d=await get('/commerce/me/wallet',q:currencyId==null?null:{'currency_id':currencyId.toString()});
    return d['item'] is Map?Map<String,dynamic>.from(d['item']):Map<String,dynamic>.from(d);
  }
  Future<Map<String,dynamic>> payFromWallet(int orderId) async {
    final d=await post('/commerce/me/orders/'+orderId.toString()+'/pay-with-wallet',{});
    return d['item'] is Map?Map<String,dynamic>.from(d['item']):Map<String,dynamic>.from(d);
  }
  Future<Map<String,dynamic>> submitOrderFeedback(int orderId,{int? rating,String? feedback}) async {
    final d=await post('/commerce/me/orders/'+orderId.toString()+'/feedback',{
      if(rating!=null)'rating':rating,
      if(feedback!=null)'feedback':feedback,
    });
    return d['item'] is Map?Map<String,dynamic>.from(d['item']):Map<String,dynamic>.from(d);
  }

  Future<List<Map<String,dynamic>>> paymentMethods()async{
    final d=await get('/commerce/payment-methods');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> shippingQuote({
    int? cityId,
    int? cityAreaId,
    int? currencyId,
    int? shippingMethodId,
    String? subtotal,
  }) async => Map<String,dynamic>.from(await post('/commerce/shipping/quote',{
    if(cityId!=null)'city_id':cityId,
    if(cityAreaId!=null)'city_area_id':cityAreaId,
    if(currencyId!=null)'currency_id':currencyId,
    if(shippingMethodId!=null)'shipping_method_id':shippingMethodId,
    if(subtotal!=null)'subtotal_sar':subtotal,
  }));
  Future<List<int>> wishlistIds()async{
    final d=await get('/customer/me/wishlist');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>int.tryParse(e['product_id'].toString())).whereType<int>().toList();
  }
  Future<Map<String,dynamic>> submitProductReview(
    int productId, {
    required int rating,
    String? title,
    String? body,
  }) async {
    final d = await post(
      '/customer/me/products/' + productId.toString() + '/reviews',
      {
        'rating': rating,
        'title': title?.trim() ?? '',
        'body': body?.trim() ?? '',
      },
    );
    return d is Map ? Map<String,dynamic>.from(d) : <String,dynamic>{};
  }
  Future<void> wishlistAdd(int id)async{await post('/customer/me/wishlist/'+id.toString(),{});}
  Future<void> wishlistRemove(int id)async{await delete('/customer/me/wishlist/'+id.toString());}
  Future<Map<String,dynamic>> notificationSummary() async {
    final d = await get('/notifications/notifications/me');
    return Map<String,dynamic>.from(d);
  }
  Future<List<Map<String,dynamic>>> notifications(int customerId)async{
    final d=await get('/notifications/notifications/'+customerId.toString());
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<void> markAllNotificationsRead() async {
    await post('/notifications/notifications/me/read-all',{});
  }
  Future<void> markNotificationRead(int customerId,int notificationId)async{
    await post('/notifications/notifications/'+customerId.toString()+'/'+notificationId.toString()+'/read',{});
  }
  Future<Map<String,dynamic>> registerPushToken({
    required String deviceId,
    required String pushToken,
    String platform = 'android',
  }) async =>
      Map<String,dynamic>.from(
        await post('/customer/me/push-token', {
          'device_id': deviceId,
          'push_token': pushToken,
          'platform': platform,
        }),
      );

  Future<void> unregisterPushToken({required String deviceId}) async {
    await post('/customer/me/push-token/unregister', {
      'device_id': deviceId,
    });
  }

  Future<List<Map<String,dynamic>>> conversations()async{
    final d=await get('/support/conversations');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> messages(int id)async{
    final d=await get('/support/conversations/'+id.toString()+'/messages');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> newConversation({
    String type='customer_service',
    int? orderId,
    String? subject,
  }) async => Map<String,dynamic>.from(
    await post('/support/conversations',{
      'type': type,
      if(orderId!=null) 'order_id': orderId,
      if(subject!=null&&subject.trim().isNotEmpty) 'subject': subject.trim(),
    }),
  );
  Future<void> sendMessage(int id,String body)async{await post('/support/conversations/'+id.toString()+'/messages',{'body':body});}
  Future<void> markConversationRead(int id) async {
    await post('/support/conversations/'+id.toString()+'/read',{});
  }
  Future<List<Map<String,dynamic>>> pickAndSendMessageWithFile(int id,{String body='',bool paymentProof=false}) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg','jpeg','png','webp','pdf'],
    );
    if (picked.isEmpty) {
      throw Exception('لم يتم اختيار ملف.');
    }
    return sendMessageWithFiles(id, body, [picked.first], paymentProof: paymentProof);
  }

  Future<List<Map<String,dynamic>>> pickAndUploadPaymentProof(int orderId) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg','jpeg','png','webp','pdf'],
    );
    if (picked.isEmpty) {
      throw Exception('لم يتم اختيار ملف.');
    }
    return uploadPaymentProof(orderId, [picked.first]);
  }

  Future<List<Map<String,dynamic>>> sendMessageWithFiles(int id,String body,List<PlatformFile> files,{bool paymentProof=false})async{
    final req=http.MultipartRequest('POST',Uri.parse(baseUrl+'/support/conversations/'+id.toString()+'/attachments'));
    req.headers.addAll(headers());
    if(body.trim().isNotEmpty)req.fields['body']=body.trim();
    if(paymentProof)req.fields['payment_proof']='1';
    for(final f in files){
      final bytes = await f.readAsBytes();
      req.files.add(http.MultipartFile.fromBytes('files',bytes,filename:f.name));
    }
    final response=await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds:25)),
    );
    final data=decode(response);
    final item=data['item']; return [item is Map?Map<String,dynamic>.from(item):<String,dynamic>{}];
  }
  Future<List<Map<String,dynamic>>> uploadPaymentProof(int orderId,List<PlatformFile> files)async{
    final req=http.MultipartRequest('POST',Uri.parse(baseUrl+'/commerce/me/payment-proofs/upload'));
    req.headers.addAll(headers());req.fields['order_id']=orderId.toString();
    for(final f in files){
      final bytes=await f.readAsBytes();
      req.files.add(http.MultipartFile.fromBytes('files',bytes,filename:f.name));
    }
    final response=await http.Response.fromStream(await req.send());
    final data=decode(response);
    return ((data['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> policies()async=>Map<String,dynamic>.from(await get('/system/policies'));
  Future<Map<String,dynamic>> storeInfo() async {
    final d = Map<String, dynamic>.from(await get('/system/store-info'));
    final item = d['item'];
    return item is Map ? Map<String, dynamic>.from(item) : d;
  }

  Future<List<Map<String,dynamic>>> storeLocations() async {
    final d = await get('/storefront/store-locations');
    return ((d['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) {
          final item = Map<String,dynamic>.from(e);
          final images = item['images'];
          if (images is List) {
            item['images'] = images.whereType<Map>().map((image) {
              final normalized = Map<String,dynamic>.from(image);
              final rawUrl = normalized['url']?.toString() ?? '';
              if (rawUrl.isNotEmpty) {
                normalized['url'] = url(rawUrl);
              }
              return normalized;
            }).toList();
          }
          return item;
        })
        .toList();
  }
  Future<void> deleteMyAccount({String? password}) async {
    await post('/customer/me/delete', {
      'confirmation': 'DELETE',
      if (password != null && password.trim().isNotEmpty)
        'password': password.trim(),
    });
    token = '';
    final p = await SharedPreferences.getInstance();
    await p.remove('access_token');
  }
  Future<void> logout() async {
    final oldToken = token;
    if (oldToken.isNotEmpty) {
      try {
        await post('/customer/auth/logout', {});
      } catch (_) {
        // Local sign-out must still complete if the network is unavailable.
      }
    }
    token='';
    final p=await SharedPreferences.getInstance();
    await p.remove('access_token');
  }
}
