import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class ApiService {
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
    dynamic x;try{x=jsonDecode(utf8.decode(r.bodyBytes));}catch(_){x={};}
    if(r.statusCode>=200&&r.statusCode<300)return x;
    if(x is Map&&x['detail']!=null)throw Exception(x['detail'].toString());
    if(x is Map&&x['error']!=null)throw Exception(x['error'].toString());
    throw Exception('تعذر الاتصال بالخادم');
  }
  Future<dynamic> get(String p,{Map<String,String>? q})async=>decode(await http.get(Uri.parse(baseUrl+p).replace(queryParameters:q),headers:headers()));
  Future<dynamic> post(String p,Map<String,dynamic> b)async=>decode(await http.post(Uri.parse(baseUrl+p),headers:{...headers(),'Content-Type':'application/json'},body:jsonEncode(b)));
  Future<dynamic> patch(String p,Map<String,dynamic> b)async=>decode(await http.patch(Uri.parse(baseUrl+p),headers:{...headers(),'Content-Type':'application/json'},body:jsonEncode(b)));
  Future<dynamic> delete(String p)async=>decode(await http.delete(Uri.parse(baseUrl+p),headers:headers()));

  Future<List<CategoryModel>> roots()async{
    final d=await get('/catalog/categories');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>CategoryModel.fromJson(Map<String,dynamic>.from(e))).where((x)=>x.parentId==null).toList();
  }
  Future<List<CategoryModel>> allCategories()async{
    final d=await get('/catalog/categories');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>CategoryModel.fromJson(Map<String,dynamic>.from(e))).toList();
  }
  Future<Map<String,dynamic>> home()async=>Map<String,dynamic>.from(await get('/storefront/home'));
  Future<List<Map<String,dynamic>>> sideCategories({int? rootId})async{
    final d=await get('/storefront/home');
    final rows=((d['side_categories'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(rootId==null)return rows;
    return rows.where((e)=>int.tryParse((e['root_category_id']??'').toString())==rootId).toList();
  }
  Future<List<Map<String,dynamic>>> categoryFilters(int categoryId)async{
    final d=await get('/catalog/categories/'+categoryId.toString()+'/filters');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> productReference(int productId)async{
    final d=await get('/catalog/reference/product-config',q:{'product_id':productId.toString()});
    return d['item'] is Map?Map<String,dynamic>.from(d['item']):Map<String,dynamic>.from(d);
  }
  Future<List<ProductModel>> feed({
    int? category,
    int? circleId,
    String q='',
    List<int>? filterValueIds,
    String sort='recommended',
    String? minPrice,
    String? maxPrice,
    int? currencyId,
  })async{
    final qp=<String,String>{'limit':'100','sort':sort};
    if(category!=null)qp['category_id']=category.toString();
    if(circleId!=null)qp['circle_id']=circleId.toString();
    if(q.trim().isNotEmpty)qp['q']=q.trim();
    if(filterValueIds!=null&&filterValueIds.isNotEmpty)qp['filter_value_ids']=filterValueIds.join(',');
    if(minPrice!=null&&minPrice.trim().isNotEmpty)qp['min_price']=minPrice.trim();
    if(maxPrice!=null&&maxPrice.trim().isNotEmpty)qp['max_price']=maxPrice.trim();
    if(currencyId!=null)qp['currency_id']=currencyId.toString();
    final d=await get('/catalog/products/feed',q:qp);
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e){
      final m=Map<String,dynamic>.from(e);
      if(m['image_url']!=null)m['image_url']=url(m['image_url'].toString());
      return ProductModel.fromJson(m);
    }).toList();
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
  Future<Map<String,dynamic>> requestOtp(String phone)async{
    final d=Map<String,dynamic>.from(await post('/customer/auth/request-otp',{'phone':phone,'purpose':'login'}));
    final item=d['item'];
    if(item is Map)return Map<String,dynamic>.from(item);
    return d;
  }
  Future<Map<String,dynamic>> verifyOtp(int id,String code,{String? phone})async{
    final d=Map<String,dynamic>.from(await post('/customer/auth/verify-otp',{
      'otp_request_id':id,
      'code':code,
      if(phone!=null&&phone.trim().isNotEmpty)'phone':phone.trim(),
      'device_id':'flutter-client',
    }));
    final item=d['item'] is Map?Map<String,dynamic>.from(d['item']):d;
    token=item['access_token']?.toString()??'';
    final p=await SharedPreferences.getInstance();
    if(token.isNotEmpty)await p.setString('access_token',token);
    return d;
  }
  Future<Map<String,dynamic>> me()async=>Map<String,dynamic>.from(await get('/customer/me'));
  Future<Map<String,dynamic>> updateMe(Map<String,dynamic> body)async=>Map<String,dynamic>.from(await patch('/customer/me',body));
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
  Future<void> addCart(int variant)async{await post('/commerce/me/cart/items',{'variant_id':variant,'qty':1});}
  Future<void> cartQty(int id,int qty)async{await patch('/commerce/me/cart/items/'+id.toString(),{'qty':qty});}
  Future<void> removeCart(int id)async{await delete('/commerce/me/cart/items/'+id.toString());}
  Future<List<Map<String,dynamic>>> orders()async{
    final d=await get('/commerce/me/orders');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> order(int id)async=>Map<String,dynamic>.from(await get('/commerce/me/orders/'+id.toString()+'/detail'));
  Future<Map<String,dynamic>> createOrder(int addressId,List<Map<String,dynamic>> items,{int? shippingMethodId,int? paymentMethodId})async=>Map<String,dynamic>.from(await post('/commerce/orders',{
    'address_id':addressId,
    'items':items,
    if(shippingMethodId!=null)'shipping_method_id':shippingMethodId,
    if(paymentMethodId!=null)'payment_method_id':paymentMethodId,
  }));
  Future<List<Map<String,dynamic>>> shippingMethods()async{
    final d=await get('/commerce/shipping-methods');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> paymentMethods()async{
    final d=await get('/commerce/payment-methods');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> shippingQuote({int? cityId,int? cityAreaId,int? currencyId,String? subtotal})async=>Map<String,dynamic>.from(await post('/commerce/shipping/quote',{
    if(cityId!=null)'city_id':cityId,
    if(cityAreaId!=null)'city_area_id':cityAreaId,
    if(currencyId!=null)'currency_id':currencyId,
    if(subtotal!=null)'subtotal_sar':subtotal,
  }));
  Future<List<int>> wishlistIds()async{
    final d=await get('/customer/me/wishlist');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>int.tryParse(e['product_id'].toString())).whereType<int>().toList();
  }
  Future<void> wishlistAdd(int id)async{await post('/customer/me/wishlist/'+id.toString(),{});}
  Future<void> wishlistRemove(int id)async{await delete('/customer/me/wishlist/'+id.toString());}
  Future<List<Map<String,dynamic>>> notifications(int customerId)async{
    final d=await get('/notifications/notifications/'+customerId.toString());
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<void> markNotificationRead(int customerId,int notificationId)async{
    await post('/notifications/notifications/'+customerId.toString()+'/'+notificationId.toString()+'/read',{});
  }
  Future<List<Map<String,dynamic>>> conversations()async{
    final d=await get('/support/conversations');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<List<Map<String,dynamic>>> messages(int id)async{
    final d=await get('/support/conversations/'+id.toString()+'/messages');
    return ((d['items'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<Map<String,dynamic>> newConversation()async=>Map<String,dynamic>.from(await post('/support/conversations',{'type':'customer_service'}));
  Future<void> sendMessage(int id,String body)async{await post('/support/conversations/'+id.toString()+'/messages',{'body':body});}
  Future<void> logout()async{token='';final p=await SharedPreferences.getInstance();await p.remove('access_token');}
}
