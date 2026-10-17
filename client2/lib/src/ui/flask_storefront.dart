import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String _configuredApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://takhfidsh.alattab.site/api/v1',
);

// An explicitly supplied but empty --dart-define must not turn API requests
// into relative GitHub Pages URLs.
String get _apiBase {
  final configured = _configuredApiBase.trim();
  final value = configured.isEmpty
      ? 'https://takhfidsh.alattab.site/api/v1'
      : configured;
  return value.replaceFirst(RegExp(r'/+$'), '');
}

class FlaskStorefront extends StatefulWidget {
  @override
  _FlaskStorefrontState createState() => _FlaskStorefrontState();
}

class _FlaskStorefrontState extends State<FlaskStorefront> {
  bool _loading = true;
  String _error;
  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  int _selectedCategoryId;
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Uri _uri(String path) {
    final base = _apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse(base + (path.startsWith('/') ? path : '/' + path));
  }

  Future<List<dynamic>> _getItems(String path) async {
    final response = await http.get(
      _uri(path),
      headers: <String, String>{'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ' + response.statusCode.toString() + ' عند طلب ' + path);
    }
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is Map && decoded['items'] is List) {
      return List<dynamic>.from(decoded['items']);
    }
    throw Exception('استجابة غير متوقعة من ' + path);
  }

  Future<void> _loadStore() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    String categoriesError;
    String productsError;
    List<dynamic> categories = [];
    List<dynamic> products = [];

    try {
      categories = await _getItems('/catalog/categories');
    } catch (error) {
      categoriesError = error.toString();
      debugPrint('Flask categories request failed: ' + error.toString());
    }

    try {
      final categoryQuery = _selectedCategoryId == null
          ? '?limit=60'
          : '?category_id=' + _selectedCategoryId.toString() + '&limit=60';
      products = await _getItems('/catalog/products/feed' + categoryQuery);
    } catch (error) {
      productsError = error.toString();
      debugPrint('Flask products request failed: ' + error.toString());
    }

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _products = products;
      _loading = false;
      _error = categoriesError != null && productsError != null
          ? 'تعذر تحميل بيانات المتجر من خادم التخفيض الصح.\\nالتصنيفات: ' +
              categoriesError + '\\nالمنتجات: ' + productsError
          : null;
    });
  }

  void _selectCategory(dynamic category) {
    final id = category == null ? null : int.tryParse(category['id'].toString());
    setState(() {
      _selectedCategoryId = id;
    });
    _loadStore();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _imageUrl(dynamic product) {
    dynamic candidate;
    if (product is Map) {
      candidate = product['image_url'] ?? product['thumbnail_url'];
      if ((candidate == null || candidate.toString().isEmpty) &&
          product['images'] is List &&
          (product['images'] as List).isNotEmpty) {
        candidate = (product['images'] as List).first;
        if (candidate is Map) candidate = candidate['url'] ?? candidate['src'];
      }
      if ((candidate == null || candidate.toString().isEmpty) &&
          product['media'] is List &&
          (product['media'] as List).isNotEmpty) {
        final first = (product['media'] as List).first;
        if (first is Map) candidate = first['url'];
      }
    }
    final value = _text(candidate);
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final origin = Uri.parse(_apiBase).origin;
    return value.startsWith('/') ? origin + value : origin + '/' + value;
  }

  List<dynamic> get _visibleProducts {
    final needle = _search.trim().toLowerCase();
    if (needle.isEmpty) return _products;
    return _products.where((product) {
      if (product is! Map) return false;
      final name = _text(product['name'] ?? product['title']).toLowerCase();
      return name.contains(needle);
    }).toList();
  }

  Widget _categoryChip(dynamic category, {bool all = false}) {
    final id = all ? null : int.tryParse(category['id'].toString());
    final selected = id == _selectedCategoryId;
    final label = all ? 'الكل' : _text(category['name'], 'تصنيف');
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _selectCategory(all ? null : category),
        selectedColor: Colors.black,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
        shape: StadiumBorder(side: BorderSide(color: selected ? Colors.black : Colors.black12)),
      ),
    );
  }

  Widget _productCard(dynamic product) {
    final name = _text(product is Map ? (product['name'] ?? product['title']) : null, 'منتج');
    final price = _text(product is Map ? product['price'] : null);
    final currency = _text(product is Map ? product['currency_code'] : null, 'SAR');
    final image = _imageUrl(product);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withOpacity(.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: image.isEmpty
                ? Container(color: Color(0xfff5f5f5), child: Icon(Icons.shopping_bag_outlined, size: 42, color: Colors.black26))
                : Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Color(0xfff5f5f5),
                      child: Icon(Icons.image_not_supported_outlined, size: 38, color: Colors.black26),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black87)),
                SizedBox(height: 6),
                if (price.isNotEmpty)
                  Text(price + ' ' + currency,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          title: Text('التخفيض الصح', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          centerTitle: false,
          actions: [
            IconButton(icon: Icon(Icons.refresh), tooltip: 'تحديث المتجر', onPressed: _loadStore),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن المنتجات',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: Color(0xfff5f5f5),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              if (_categories.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _categoryChip(null, all: true),
                      ..._categories.where((c) => c is Map && (c['parent_id'] == null || c['parent_id'] == 0))
                          .map((c) => _categoryChip(c)).toList(),
                    ],
                  ),
                ),
              if (_loading)
                Expanded(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
                      SizedBox(height: 14),
                      Text('جاري تحميل المتجر', style: TextStyle(color: Colors.black87)),
                    ]),
                  ),
                )
              else if (_error != null && _categories.isEmpty && _products.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_off_outlined, size: 52, color: Colors.black45),
                        SizedBox(height: 12),
                        Text(_error, textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
                        SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(primary: Colors.black, onPrimary: Colors.white),
                          onPressed: _loadStore,
                          child: Text('إعادة المحاولة'),
                        ),
                      ]),
                    ),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadStore,
                    color: Colors.black,
                    child: products.isEmpty
                        ? ListView(
                            physics: AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: 90),
                              Center(child: Text(_error ?? 'لا توجد منتجات متاحة حاليًا',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))),
                            ],
                          )
                        : GridView.builder(
                            padding: EdgeInsets.all(10),
                            physics: AlwaysScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: MediaQuery.of(context).size.width >= 900
                                  ? 5
                                  : MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                              crossAxisSpacing: 9,
                              mainAxisSpacing: 9,
                              childAspectRatio: .57,
                            ),
                            itemCount: products.length,
                            itemBuilder: (context, index) => _productCard(products[index]),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
), '');
}

class FlaskStorefront extends StatefulWidget {
  @override
  _FlaskStorefrontState createState() => _FlaskStorefrontState();
}

class _FlaskStorefrontState extends State<FlaskStorefront> {
  bool _loading = true;
  String _error;
  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  int _selectedCategoryId;
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Uri _uri(String path) {
    final base = _apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse(base + path);
  }

  Future<List<dynamic>> _getItems(String path) async {
    final response = await http.get(
      _uri(path),
      headers: <String, String>{'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ' + response.statusCode.toString() + ' عند طلب ' + path);
    }
    final decoded = json.decode(utf8.decode(response.bodyBytes));
    if (decoded is Map && decoded['items'] is List) {
      return List<dynamic>.from(decoded['items']);
    }
    throw Exception('استجابة غير متوقعة من ' + path);
  }

  Future<void> _loadStore() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    String categoriesError;
    String productsError;
    List<dynamic> categories = [];
    List<dynamic> products = [];

    try {
      categories = await _getItems('/categories');
    } catch (error) {
      categoriesError = error.toString();
      debugPrint('Flask categories request failed: ' + error.toString());
    }

    try {
      final categoryQuery = _selectedCategoryId == null
          ? '?limit=60'
          : '?category_id=' + _selectedCategoryId.toString() + '&limit=60';
      products = await _getItems('/products/feed' + categoryQuery);
    } catch (error) {
      productsError = error.toString();
      debugPrint('Flask products request failed: ' + error.toString());
    }

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _products = products;
      _loading = false;
      _error = categoriesError != null && productsError != null
          ? 'تعذر الاتصال بواجهة المتجر. تحقق من اتصال الإنترنت وإعدادات الخادم ثم أعد المحاولة.'
          : null;
    });
  }

  void _selectCategory(dynamic category) {
    final id = category == null ? null : int.tryParse(category['id'].toString());
    setState(() {
      _selectedCategoryId = id;
    });
    _loadStore();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _imageUrl(dynamic product) {
    dynamic candidate;
    if (product is Map) {
      candidate = product['image_url'] ?? product['thumbnail_url'];
      if ((candidate == null || candidate.toString().isEmpty) &&
          product['images'] is List &&
          (product['images'] as List).isNotEmpty) {
        candidate = (product['images'] as List).first;
        if (candidate is Map) candidate = candidate['url'] ?? candidate['src'];
      }
      if ((candidate == null || candidate.toString().isEmpty) &&
          product['media'] is List &&
          (product['media'] as List).isNotEmpty) {
        final first = (product['media'] as List).first;
        if (first is Map) candidate = first['url'];
      }
    }
    final value = _text(candidate);
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    final origin = Uri.parse(_apiBase).origin;
    return value.startsWith('/') ? origin + value : origin + '/' + value;
  }

  List<dynamic> get _visibleProducts {
    final needle = _search.trim().toLowerCase();
    if (needle.isEmpty) return _products;
    return _products.where((product) {
      if (product is! Map) return false;
      final name = _text(product['name'] ?? product['title']).toLowerCase();
      return name.contains(needle);
    }).toList();
  }

  Widget _categoryChip(dynamic category, {bool all = false}) {
    final id = all ? null : int.tryParse(category['id'].toString());
    final selected = id == _selectedCategoryId;
    final label = all ? 'الكل' : _text(category['name'], 'تصنيف');
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _selectCategory(all ? null : category),
        selectedColor: Colors.black,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
        shape: StadiumBorder(side: BorderSide(color: selected ? Colors.black : Colors.black12)),
      ),
    );
  }

  Widget _productCard(dynamic product) {
    final name = _text(product is Map ? (product['name'] ?? product['title']) : null, 'منتج');
    final price = _text(product is Map ? product['price'] : null);
    final currency = _text(product is Map ? product['currency_code'] : null, 'SAR');
    final image = _imageUrl(product);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withOpacity(.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: image.isEmpty
                ? Container(color: Color(0xfff5f5f5), child: Icon(Icons.shopping_bag_outlined, size: 42, color: Colors.black26))
                : Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Color(0xfff5f5f5),
                      child: Icon(Icons.image_not_supported_outlined, size: 38, color: Colors.black26),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black87)),
                SizedBox(height: 6),
                if (price.isNotEmpty)
                  Text(price + ' ' + currency,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          title: Text('التخفيض الصح', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          centerTitle: false,
          actions: [
            IconButton(icon: Icon(Icons.refresh), tooltip: 'تحديث المتجر', onPressed: _loadStore),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن المنتجات',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: Color(0xfff5f5f5),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              if (_categories.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _categoryChip(null, all: true),
                      ..._categories.where((c) => c is Map && (c['parent_id'] == null || c['parent_id'] == 0))
                          .map((c) => _categoryChip(c)).toList(),
                    ],
                  ),
                ),
              if (_loading)
                Expanded(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
                      SizedBox(height: 14),
                      Text('جاري تحميل المتجر', style: TextStyle(color: Colors.black87)),
                    ]),
                  ),
                )
              else if (_error != null && _categories.isEmpty && _products.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.cloud_off_outlined, size: 52, color: Colors.black45),
                        SizedBox(height: 12),
                        Text(_error, textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
                        SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(primary: Colors.black, onPrimary: Colors.white),
                          onPressed: _loadStore,
                          child: Text('إعادة المحاولة'),
                        ),
                      ]),
                    ),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadStore,
                    color: Colors.black,
                    child: products.isEmpty
                        ? ListView(
                            physics: AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: 90),
                              Center(child: Text(_error ?? 'لا توجد منتجات متاحة حاليًا',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))),
                            ],
                          )
                        : GridView.builder(
                            padding: EdgeInsets.all(10),
                            physics: AlwaysScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: MediaQuery.of(context).size.width >= 900
                                  ? 5
                                  : MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                              crossAxisSpacing: 9,
                              mainAxisSpacing: 9,
                              childAspectRatio: .57,
                            ),
                            itemCount: products.length,
                            itemBuilder: (context, index) => _productCard(products[index]),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
