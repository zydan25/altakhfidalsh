import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'app_state.dart';
import 'models.dart';
import 'product_card.dart';
import 'theme.dart';

class SxProductScreen extends StatefulWidget {
  final int id;
  final WidgetBuilder? cartBuilder;
  const SxProductScreen({super.key, required this.id, this.cartBuilder});

  @override
  State<SxProductScreen> createState() => _SxProductScreenState();
}

class _SxProductScreenState extends State<SxProductScreen> {
  Map<String, dynamic> data = <String, dynamic>{};
  List<ProductModel> related = <ProductModel>[];
  bool loading = true;
  bool loadingRelated = false;
  bool wishlisted = false;
  int page = 0;
  int? selectedColorId;
  int? galleryColorId;
  int? sizeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await api.product(widget.id, currencyId: state.currencyId);
      final next = Map<String, dynamic>.from(
        response['item'] is Map ? response['item'] : response,
      );

      final variants = _maps(next['variants']);
      if (variants.isNotEmpty) {
        final preferred = variants.firstWhere(
          (variant) => sxInt(variant['available_qty']) > 0,
          orElse: () => variants.first,
        );
        final c = sxInt(preferred['color_id']);
        final s = sxInt(preferred['size_id']);
        selectedColorId = c > 0 ? c : null;
        sizeId = s > 0 ? s : null;
      }

      if (state.loggedIn) {
        try {
          final ids = await api.wishlistIds();
          wishlisted = ids.contains(widget.id);
          state.wishlist = ids.toSet();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        data = next;
        loading = false;
      });
      await _loadRelated(next);
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(error))),
      );
    }
  }

  Future<void> _loadRelated(Map<String, dynamic> productData) async {
    if (loadingRelated) return;
    final categories = _maps(productData['categories']);
    final recommendation = _asMap(productData['recommendation_settings']);
    final source = sxText(recommendation['source'], 'same_category');
    int? scopeId;

    if (source == 'same_category' && categories.isNotEmpty) {
      scopeId = sxInt(categories.first['id']);
    } else if (source == 'parent_category' && categories.isNotEmpty) {
      final parent = categories.first['parent_id'];
      scopeId = parent == null ? null : sxInt(parent);
    } else if (source == 'root_category') {
      final roots = productData['root_category_ids'];
      if (roots is List && roots.isNotEmpty) {
        scopeId = sxInt(roots.first);
      }
    }

    setState(() => loadingRelated = true);
    try {
      final limit = sxInt(recommendation['limit'], 10).clamp(2, 20);
      var rows = await api.feed(
        category: scopeId != null && scopeId > 0 ? scopeId : null,
        currencyId: state.currencyId,
        sort: 'random',
        discoveryTab: null,
      );

      // A product-detail opened from another recommendation can arrive with a
      // category scope that has no remaining candidates after excluding itself.
      // Fall back to the general storefront feed so "قد يعجبك أيضًا" never
      // becomes permanently empty just because its local category is exhausted.
      final filtered = <ProductModel>[];
      final seen = <int>{widget.id};
      for (final product in rows) {
        if (seen.add(product.id)) filtered.add(product);
        if (filtered.length >= limit) break;
      }
      if (filtered.isEmpty && scopeId != null) {
        rows = await api.feed(
          currencyId: state.currencyId,
          sort: 'random',
          discoveryTab: null,
        );
        filtered
          ..clear()
          ..addAll(
            rows.where((product) => seen.add(product.id)).take(limit),
          );
      }

      if (!mounted) return;
      setState(() {
        related = filtered.take(limit).toList();
      });
    } catch (_) {
      if (mounted) setState(() => related = <ProductModel>[]);
    } finally {
      if (mounted) setState(() => loadingRelated = false);
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> _media() {
    final rows = _maps(data['media']);
    if (rows.isEmpty) return const <Map<String, dynamic>>[];

    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addRow(Map<String, dynamic> row) {
      final url = sxText(row['url']);
      final id = sxInt(row['id']);
      final key = id > 0 ? 'id:$id' : 'url:$url';
      if (key.endsWith(':') || (!seen.add(key))) return;
      result.add(row);
    }

    // The carousel always starts with the product's main images.
    for (final row in rows.where((row) => row['color_id'] == null)) {
      addRow(row);
    }

    // Then it walks color by color in the exact reference-color order.
    final selectedColorIds = _colors().map((color) => sxInt(color['id'])).where((id) => id > 0);
    final includedColorIds = <int>{};
    for (final id in selectedColorIds) {
      includedColorIds.add(id);
      for (final row in rows.where((row) => sxInt(row['color_id']) == id)) {
        addRow(row);
      }
    }

    // Preserve any colored media whose color is not currently in the reference
    // list, without losing it from the customer's gallery.
    for (final row in rows) {
      final id = sxInt(row['color_id']);
      if (id > 0 && !includedColorIds.contains(id)) addRow(row);
    }
    return result;
  }

  int _firstGalleryIndexForColor(int color) {
    final rows = _media();
    for (var i = 0; i < rows.length; i++) {
      if (sxInt(rows[i]['color_id']) == color) return i;
    }
    return 0;
  }

  void _onGalleryPageChanged(int index) {
    final rows = _media();
    if (rows.isEmpty) return;
    final safeIndex = index.clamp(0, rows.length - 1).toInt();
    final mediaColor = sxInt(rows[safeIndex]['color_id']);
    setState(() {
      page = safeIndex;
      galleryColorId = mediaColor > 0 ? mediaColor : null;
      // Main images clear the color indicator; colored media select that color.
      selectedColorId = mediaColor > 0 ? mediaColor : null;
    });
  }

  Map<int, String> _colorThumbUrls(
    List<Map<String, dynamic>> colors,
    List<Map<String, dynamic>> media,
  ) {
    final urls = <int, String>{};
    for (final row in media) {
      final id = sxInt(row['color_id']);
      final url = sxText(row['url']);
      if (id > 0 && url.isNotEmpty) urls.putIfAbsent(id, () => url);
    }
    for (final color in colors) {
      final id = sxInt(color['id']);
      if (id <= 0) continue;
      final swatch = sxText(
        color['swatch_asset_url'],
        sxText(color['swatch_url']),
      );
      if (swatch.isNotEmpty) urls[id] = swatch;
    }
    return urls;
  }

  void _selectColor(int color) {
    final index = _firstGalleryIndexForColor(color);
    setState(() {
      selectedColorId = color;
      galleryColorId = color;
      page = index;
    });
  }

  List<Map<String, dynamic>> _colors() {
    final refs = _maps(data['reference_colors']);
    if (refs.isNotEmpty) return refs;
    final found = <int, Map<String, dynamic>>{};
    for (final option in _maps(data['options'])) {
      for (final value in _maps(option['values'])) {
        final id = sxInt(value['color_id']);
        if (id > 0 && !found.containsKey(id)) {
          found[id] = <String, dynamic>{
            'id': id,
            'name': sxText(value['label']),
            'hex_code': '#d1d5db',
          };
        }
      }
    }
    return found.values.toList();
  }

  List<Map<String, dynamic>> _sizes() {
    final refs = _maps(data['reference_sizes']);
    if (refs.isNotEmpty) return refs;
    final found = <int, Map<String, dynamic>>{};
    for (final option in _maps(data['options'])) {
      for (final value in _maps(option['values'])) {
        final id = sxInt(value['size_id']);
        if (id > 0 && !found.containsKey(id)) {
          found[id] = <String, dynamic>{
            'id': id,
            'label': sxText(value['label']),
          };
        }
      }
    }
    return found.values.toList();
  }

  Map<String, dynamic>? _selectedVariant() {
    final variants = _maps(data['variants']);
    final colors = _colors();
    final sizes = _sizes();
    final requiresColor = colors.isNotEmpty;
    final requiresSize = sizes.isNotEmpty;

    if (requiresColor && selectedColorId == null) return null;
    if (requiresSize && sizeId == null) return null;

    for (final variant in variants) {
      final colorOk = !requiresColor || sxInt(variant['color_id']) == sxInt(selectedColorId);
      final sizeOk = !requiresSize || sxInt(variant['size_id']) == sxInt(sizeId);
      if (colorOk && sizeOk && sxInt(variant['id']) > 0) {
        return variant;
      }
    }
    return null;
  }

  int? _variantId() => sxIntNullable(_selectedVariant()?['id']);

  int _availableQty() {
    final variant = _selectedVariant();
    return variant == null ? 0 : sxInt(variant['available_qty']);
  }

  int _discount(String current, String previous) {
    final now = double.tryParse(current);
    final old = double.tryParse(previous);
    if (now == null || old == null || old <= now || old <= 0) return 0;
    return ((1 - now / old) * 100).round();
  }

  Future<void> _toggleWishlist() async {
    if (!state.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل الدخول لإضافة المنتج إلى المفضلة')),
      );
      return;
    }
    final next = !wishlisted;
    setState(() => wishlisted = next);
    try {
      if (next) {
        await api.wishlistAdd(widget.id);
        state.wishlist.add(widget.id);
      } else {
        await api.wishlistRemove(widget.id);
        state.wishlist.remove(widget.id);
      }
    } catch (error) {
      if (mounted) setState(() => wishlisted = !next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(error))),
        );
      }
    }
  }

  Map<String, dynamic> _selectedOptions() {
    final result = <String, dynamic>{};
    final colors = _colors();
    final sizes = _sizes();
    if (selectedColorId != null) {
      final matching = colors.where((x) => sxInt(x['id']) == selectedColorId);
      if (matching.isNotEmpty) result['اللون'] = sxText(matching.first['name']);
    }
    if (sizeId != null) {
      final matching = sizes.where((x) => sxInt(x['id']) == sizeId);
      if (matching.isNotEmpty) result['المقاس'] = sxText(matching.first['label'], sxText(matching.first['code']));
    }
    return result;
  }

  Future<int?> _confirmAddQuantity() async {
    if (!mounted) return null;
    final colors = _colors();
    final sizes = _sizes();
    String selectedColor = '';
    String selectedSize = '';
    if (selectedColorId != null) {
      final matching = colors.where((x) => sxInt(x['id']) == selectedColorId);
      if (matching.isNotEmpty) selectedColor = sxText(matching.first['name']);
    }
    if (sizeId != null) {
      final matching = sizes.where((x) => sxInt(x['id']) == sizeId);
      if (matching.isNotEmpty) selectedSize = sxText(matching.first['label'], sxText(matching.first['code']));
    }
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _AddToCartConfirmation(
        productName: sxText((data['product'] as Map?)?['name'], 'منتج'),
        color: selectedColor,
        size: selectedSize,
        maxQuantity: _availableQty(),
      ),
    );
  }


  Future<bool> _addToCart() async {
    final variant = _variantId();
    if (variant == null || variant <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر خيارات المنتج أولًا')),
        );
      }
      return false;
    }

    final available = _availableQty();
    if (available <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا الاختيار غير متوفر حاليًا')),
        );
      }
      return false;
    }

    final quantity = await _confirmAddQuantity();
    if (quantity == null || quantity < 1) return false;
    if (quantity > available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('المتاح لهذا الاختيار $available فقط')),
        );
      }
      return false;
    }

    try {
      await api.addCart(variant, quantity, _selectedOptions());
      final cart = await api.cart(currencyId: state.currencyId);
      cartBadge.value = sxIntListLength(cart['item']?['items']);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة $quantity إلى عربة التسوق')),
      );
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(error))),
        );
      }
      return false;
    }
  }

  Future<void> _buyNow() async {
    final added = await _addToCart();
    if (!added || !mounted) return;
    final builder = widget.cartBuilder;
    if (builder != null) {
      Navigator.push(context, MaterialPageRoute(builder: builder));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final product = Map<String, dynamic>.from(
      (data['product'] as Map?) ?? <String, dynamic>{},
    );
    final brand = product['brand'] is Map
        ? Map<String, dynamic>.from(product['brand'] as Map)
        : <String, dynamic>{};
    final media = _media();
    final colors = _colors();
    final sizes = _sizes();
    final price = sxText(
      product['display_price'],
      sxText(product['price'], sxText(product['base_price_sar'], '0')),
    );

    final oldPrice = sxText(
      product['display_compare_price'],
      sxText(product['compare_at_price']),
    );
    final displayCurrency = product['display_currency'] is Map
        ? Map<String, dynamic>.from(product['display_currency'] as Map)
        : <String, dynamic>{};
    final detailCurrency = sxText(
      displayCurrency['symbol'],
      state.currencySymbol,
    );
    final shortDescription = sxText(
      product['short_description'],
      sxText(product['description']),
    );
    final currencyCode = sxText(
      displayCurrency['code'],
      state.currencyCode,
    ).toUpperCase();
    final formattedPrice = sxFormatMoney(
      price,
      currencyCode: currencyCode,
    );
    final formattedOldPrice = sxFormatMoney(
      oldPrice,
      currencyCode: currencyCode,
    );
    final discount = _discount(price, oldPrice);
    final summary = Map<String, dynamic>.from(
      (data['rating_summary'] as Map?) ?? <String, dynamic>{},
    );
    final average = sxDouble(summary['average']);
    final reviewCount = sxInt(summary['count']);
    final display = Map<String, dynamic>.from(
      (data['display'] as Map?) ?? <String, dynamic>{},
    );
    final policies = Map<String, dynamic>.from(
      (data['policies'] as Map?) ?? <String, dynamic>{},
    );
    final reviews = _maps(data['reviews_preview']);
    final detailSettings = _asMap(data['product_detail_settings']);
    final trendBadges = _maps(data['trend_badges']);
    final promotionalStrips = _maps(data['promotional_strips']);
    final campaigns = _maps(data['campaigns']);
    final cardSettings = _asMap(data['product_card_settings']);
    final detailOrder = ((detailSettings['detail_order'] as List?) ?? const <dynamic>[])
        .map((x) => sxText(x))
        .where((x) => x.isNotEmpty)
        .toList();
    if (!detailOrder.contains('rating')) {
      final brandIndex = detailOrder.indexOf('brand');
      detailOrder.insert(brandIndex >= 0 ? brandIndex + 1 : detailOrder.length, 'rating');
    }
    if (!detailOrder.contains('trend')) {
      detailOrder.insert(0, 'trend');
    }
    if (!detailOrder.contains('promotions')) {
      final priceIndex = detailOrder.indexOf('price');
      detailOrder.insert(priceIndex >= 0 ? priceIndex + 1 : detailOrder.length, 'promotions');
    }
    if (!detailOrder.contains('description')) {
      final nameIndex = detailOrder.indexOf('name');
      detailOrder.insert(nameIndex >= 0 ? nameIndex + 1 : detailOrder.length, 'description');
    }

    Widget? detailSection(String key) {
      switch (key) {
        case 'badges':
          return detailSettings['badges_show'] == false
              ? const SizedBox.shrink()
              : _DetailBadgeStrip(
                  title: 'الشارات',
                  badges: _maps(data['badges']),
                  positions: const {
                    'first', 'above_image',
                    'before_name', 'before_name_new_row',
                    'after_name', 'after_name_same_row', 'after_name_new_row',
                    'before_price', 'before_price_same_row', 'before_price_new_row',
                    'after_price', 'after_price_same_row', 'after_price_new_row',
                    'after_description', 'after_description_same_row', 'after_description_new_row',
                    'before_details', 'after_details', 'after_details_same_row', 'after_details_new_row',
                    'below_description', 'below_price', 'right_of_image', 'last',
                  },
                  gap: sxDouble(detailSettings['badges_gap'], 5),
                );
        case 'gallery':
          return detailSettings['gallery_show'] == false
              ? const SizedBox.shrink()
              : SxGallery(
                  rows: media,
                  page: page,
                  aspectRatio: sxDouble(detailSettings['gallery_ratio'], .78),
                  changed: _onGalleryPageChanged,
                  badges: _maps(data['badges']),
                );
        case 'thumbs':
          return detailSettings['thumbs_show'] == false
              ? const SizedBox.shrink()
              : SxGalleryThumbs(
                  rows: media,
                  page: page,
                  changed: _onGalleryPageChanged,
                  itemWidth: sxDouble(detailSettings['thumbs_size'], 62),
                  itemHeight: sxDouble(detailSettings['thumbs_height'], 70),
                  gap: sxDouble(detailSettings['thumbs_gap'], 6),
                  radius: sxDouble(detailSettings['thumbs_radius'], 4),
                  borderWidth: sxDouble(detailSettings['thumbs_border_width'], 1.5),
                  colorRows: colors,
                );
        case 'trend':
          return trendBadges.isEmpty
              ? const SizedBox.shrink()
              : _DetailTrendSection(trends: trendBadges, settings: detailSettings);
        case 'price':
          return detailSettings['price_show'] == false
              ? const SizedBox.shrink()
              : _DetailPriceBlock(
                  price: formattedPrice,
                  oldPrice: formattedOldPrice,
                  currency: detailCurrency,
                  settings: detailSettings,
                  cardSettings: cardSettings,
                );
        case 'promotions':
          return (promotionalStrips.isEmpty && campaigns.isEmpty)
              ? const SizedBox.shrink()
              : _DetailPromotionsSection(
                  strips: promotionalStrips,
                  campaigns: campaigns,
                );
        case 'name':
          return detailSettings['name_show'] == false
              ? const SizedBox.shrink()
              : _DetailNameBlock(
                  name: sxText(product['name'], 'منتج'),
                  settings: detailSettings,
                  badges: _maps(data['badges']),
                );
        case 'description':
          return detailSettings['description_show'] == false || shortDescription.trim().isEmpty
              ? const SizedBox.shrink()
              : _DetailDescriptionBlock(
                  description: shortDescription,
                  settings: detailSettings,
                );
        case 'brand':
          return detailSettings['brand_show'] == false || brand.isEmpty
              ? const SizedBox.shrink()
              : _DetailBrandBlock(
                  brand: sxText(brand['name']),
                  settings: detailSettings,
                );
        case 'rating':
          return detailSettings['rating_show'] == false
              ? const SizedBox.shrink()
              : _DetailRatingBlock(
                  average: average,
                  reviewCount: reviewCount,
                  settings: detailSettings,
                );
        case 'colors':
          return _ProductOptions(
            colors: colors,
            sizes: const [],
            selectedColorId: selectedColorId,
            selectedSizeId: sizeId,
            onColor: _selectColor,
            onSize: (_) {},
            colorThumbUrls: _colorThumbUrls(colors, media),
            settings: detailSettings,
            showColors: detailSettings['colors_show'] != false,
            showSizes: false,
          );
        case 'sizes':
          final sizeGuide = _asMap(data['size_guide']);
          final guideRows = sizeGuide['rows'] is List
        ? (sizeGuide['rows'] as List)
            .whereType<Map>()
            .map((x) => Map<String, dynamic>.from(x))
            .toList()
        : <Map<String, dynamic>>[];
          final selectedGuideIndex = guideRows.indexWhere(
            (row) => sxInt(row['size_id']) == sxInt(sizeId),
          );
          final selectedGuideRow = selectedGuideIndex >= 0
              ? guideRows[selectedGuideIndex]
              : <String, dynamic>{};
          final hasSizeDetails =
              selectedGuideRow.isNotEmpty &&
              (_asMap(selectedGuideRow['product_measurements']).isNotEmpty ||
                  _asMap(selectedGuideRow['body_measurements']).isNotEmpty);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProductOptions(
                colors: const [],
                sizes: sizes,
                selectedColorId: selectedColorId,
                selectedSizeId: sizeId,
                onColor: (_) {},
                onSize: (value) => setState(() => sizeId = value),
                settings: detailSettings,
                showColors: false,
                showSizes: detailSettings['sizes_show'] != false,
              ),
              if (hasSizeDetails)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => _SizeGuideDialog(
                          guide: sizeGuide,
                          initialSizeId: sizeId,
                        ),
                      ),
                      child: Text(
                        'تفاصيل المقاس',
                        style: TextStyle(
                          color: sxColor(
                            sxText(detailSettings['size_guide_color']),
                            Colors.black,
                          ),
                          fontSize: sxDouble(detailSettings['size_guide_font_size'], 10),
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                          decorationThickness: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        case 'size_guide':
          return const SizedBox.shrink();
        case 'details':
          return detailSettings['details_show'] == false
              ? const SizedBox.shrink()
              : _DetailSection(
                  title: 'تفاصيل المنتج',
                  icon: Icons.description_outlined,
                  text: <String>[
                    sxText(product['description']),
                    if (sxText(product['material']).isNotEmpty)
                      'الخامة: ' + sxText(product['material']),
                    if (sxText(product['care_instructions']).isNotEmpty)
                      'العناية: ' + sxText(product['care_instructions']),
                    if (sxText(product['product_type']).isNotEmpty)
                      'نوع المنتج: ' + sxText(product['product_type']),
                    if (sxText(product['sku']).isNotEmpty)
                      'رمز المنتج: ' + sxText(product['sku']),
                  ].where((text) => text.trim().isNotEmpty).join('\n\n'),
                  settings: detailSettings,
                );
        case 'stock':
          return detailSettings['stock_show'] == false
              ? const SizedBox.shrink()
              : _StockStatusPanel(
                  availableQty: _availableQty(),
                  hasVariant: _selectedVariant() != null,
                  fontSize: sxDouble(detailSettings['stock_font_size'], 10),
                  textColor: sxColor(sxText(detailSettings['stock_text_color']), Colors.black),
                );
        case 'delivery':
          return detailSettings['delivery_show'] == false
              ? const SizedBox.shrink()
              : _DeliveryBadgePanel(
                  badges: _maps(data['delivery_badges']),
                  fontSize: sxDouble(detailSettings['delivery_font_size'], 9),
                  color: sxColor(sxText(detailSettings['delivery_color']), Colors.black),
                );
        case 'policies':
          return detailSettings['policies_show'] == false
              ? const SizedBox.shrink()
              : _PolicySections(policies: policies, settings: detailSettings);
        case 'reviews':
          return detailSettings['reviews_show'] == false
              ? const SizedBox.shrink()
              : _ReviewSection(
                  average: average,
                  count: reviewCount,
                  reviews: reviews,
                  onWriteReview: _openReviewComposer,
                  settings: detailSettings,
                );
        case 'related':
          return detailSettings['related_show'] == false
              ? const SizedBox.shrink()
              : _RelatedProductsSection(
                  related: related,
                  titleFontSize: sxDouble(detailSettings['related_title_font_size'], 13),
                  displaySettings: cardSettings,
                );
        default:
          return null;
      }
    }

    final orderedSections = <Widget>[];
    final variantKeys = <String>{'thumbs', 'sizes', 'colors', 'size_guide'};
    final policyKeys = <String>{'delivery', 'policies'};
    var variantRendered = false;
    var policyRendered = false;

    Widget variantBox() => _DetailVariantSelectionBox(
      media: media,
      page: page,
      colors: colors,
      sizes: sizes,
      variants: _maps(data['variants']),
      selectedColorId: selectedColorId,
      selectedSizeId: sizeId,
      colorThumbUrls: _colorThumbUrls(colors, media),
      detailSettings: detailSettings,
      showThumbs: detailSettings['thumbs_show'] != false,
      showSizes: detailSettings['sizes_show'] != false,
      showColors: detailSettings['colors_show'] != false,
      sizeGuide: (() {
        final guide = _asMap(data['size_guide']);
        if (guide.isNotEmpty) return guide;
        return <String, dynamic>{
          'name': 'دليل المقاسات',
          'intro_text': 'اختر المقاس من الجدول لعرض القياسات بالكامل.',
          'rows': sizes.map((item) => <String, dynamic>{
            'size_id': sxInt(item['id']),
            'size_label': sxText(item['label'], sxText(item['code'], '—')),
            'size_code': sxText(item['code']),
            'product_measurements': <String, dynamic>{},
            'body_measurements': <String, dynamic>{},
          }).toList(),
        };
      })(),
      showSizeGuide: detailSettings['size_guide_show'] != false,
      onGalleryChanged: _onGalleryPageChanged,
      onColor: _selectColor,
      onSize: (value) => setState(() => sizeId = value),
    );

    Widget policyBox() => _DeliveryPolicyBox(
      deliveryBadges: _maps(data['delivery_badges']),
      policies: policies,
      settings: detailSettings,
    );

    Widget renderGroup(String title, List<String> keys) {
      final children = <Widget>[];
      var groupVariant = false;
      var groupPolicy = false;
      for (final key in keys) {
        if (key == 'gallery') continue;
        if (variantKeys.contains(key)) {
          if (!groupVariant) {
            groupVariant = true;
            children.add(variantBox());
            variantRendered = true;
          }
          continue;
        }
        if (policyKeys.contains(key)) {
          if (!groupPolicy) {
            groupPolicy = true;
            children.add(policyBox());
            policyRendered = true;
          }
          continue;
        }
        final section = detailSection(key);
        if (section != null) children.add(section);
      }
      if (children.isEmpty) return const SizedBox.shrink();
      return _DetailGroupBox(
        title: title,
        settings: detailSettings,
        children: children,
      );
    }

    // SHEIN: gallery remains the first visual block and every following group is
    // driven by the server-side detail_groups definition.
    if (detailSettings['gallery_show'] != false) {
      orderedSections.add(
        SliverToBoxAdapter(
          child: SxGallery(
            rows: media,
            page: page,
            aspectRatio: sxDouble(detailSettings['gallery_ratio'], .78),
            changed: _onGalleryPageChanged,
            badges: _maps(data['badges']),
          ),
        ),
      );
    }

    final rawGroups = detailSettings['detail_groups'];
    if (rawGroups is List && rawGroups.isNotEmpty) {
      for (final rawGroup in rawGroups) {
        if (rawGroup is! Map || rawGroup['show'] == false) continue;
        final group = Map<String, dynamic>.from(rawGroup);
        final rawItems = group['items'];
        final keys = rawItems is List
            ? rawItems.map((x) => sxText(x)).where((x) => x.isNotEmpty).toList()
            : <String>[];
        if (keys.isEmpty) continue;
        final groupWidget = renderGroup(
          sxText(group['title'], 'قسم تفاصيل'),
          keys,
        );
        if (groupWidget is! SizedBox) {
          orderedSections.add(SliverToBoxAdapter(child: groupWidget));
        }
      }
    }

    // Safety net for old or incomplete saved settings.
    if (!variantRendered &&
        (colors.isNotEmpty || sizes.isNotEmpty ||
            (detailSettings['thumbs_show'] != false && media.length > 1))) {
      orderedSections.add(SliverToBoxAdapter(child: variantBox()));
      variantRendered = true;
    }
    if (!policyRendered &&
        (policies.isNotEmpty || _maps(data['delivery_badges']).isNotEmpty)) {
      orderedSections.add(SliverToBoxAdapter(child: policyBox()));
      policyRendered = true;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    backgroundColor: Colors.white,
                    automaticallyImplyLeading: false,
                    toolbarHeight: 52,
                    titleSpacing: 4,
                    title: Row(
                      children: [
                        _iconButton(
                          Icons.arrow_forward_ios,
                          () => Navigator.pop(context),
                          'رجوع',
                        ),
                        const Spacer(),
                        _iconButton(
                          wishlisted ? Icons.favorite : Icons.favorite_border,
                          _toggleWishlist,
                          'المفضلة',
                          iconColor: wishlisted ? ClientTheme.promo : Colors.black,
                        ),
                        _iconButton(
                          Icons.share_outlined,
                          () => _share(context, sxText(product['name'], 'منتج')),
                          'مشاركة',
                        ),
                      ],
                    ),
                  ),
                  ...orderedSections,
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: _ProductBottomBar(
                price: formattedPrice,
                currency: detailCurrency,
                onAdd: _addToCart,
                availableQty: _availableQty(),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _openReviewComposer() async {
    if (!state.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل الدخول لإضافة تقييم أو تعليق')),
      );
      return;
    }
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ReviewComposer(
        onSubmit: (rating, title, body) async {
          await api.submitProductReview(
            widget.id,
            rating: rating,
            title: title,
            body: body,
          );
        },
      ),
    );
    if (submitted == true && mounted) {
      await _load();
    }
  }

  Widget _iconButton(
    IconData icon,
    VoidCallback onTap,
    String tooltip, {
    Color iconColor = Colors.black,
  }) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        icon: Icon(icon, size: 20, color: iconColor),
      );

  Future<void> _share(BuildContext context, String name) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DetailHandle(),
              const SizedBox(height: 9),
              const Text(
                'مشاركة المنتج',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: ClientTheme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SxGallery extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final int page;
  final ValueChanged<int> changed;
  final List<Map<String, dynamic>> badges;
  final double aspectRatio;

  const SxGallery({
    super.key,
    required this.rows,
    required this.page,
    required this.changed,
    this.badges = const [],
    this.aspectRatio = .78,
  });

  @override
  State<SxGallery> createState() => _SxGalleryState();
}

class _SxGalleryState extends State<SxGallery> {
  late final PageController _controller;
  static const int _virtualBase = 500000;

  int _initialVirtualPage() {
    final length = widget.rows.length;
    if (length <= 1) return 0;
    final logical = widget.page.clamp(0, length - 1).toInt();
    final base = (_virtualBase ~/ length) * length;
    return base + logical;
  }

  int _logicalIndex(int virtualIndex) {
    final length = widget.rows.length;
    if (length <= 1) return 0;
    return virtualIndex % length;
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _initialVirtualPage());
  }

  @override
  void didUpdateWidget(covariant SxGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows.length != widget.rows.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(_initialVirtualPage());
      });
      return;
    }
    if (widget.page != oldWidget.page &&
        _controller.hasClients &&
        widget.rows.length > 1) {
      final current = (_controller.page ?? _initialVirtualPage()).round();
      final length = widget.rows.length;
      final currentBase = (current ~/ length) * length;
      var target = currentBase + widget.page.clamp(0, length - 1).toInt();
      if ((target - current).abs() > length ~/ 2) {
        target += target < current ? length : -length;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.animateToPage(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.rows.isEmpty
        ? <Map<String, dynamic>>[<String, dynamic>{}]
        : widget.rows;
    final virtualCount = data.length > 1 ? 1000000 : data.length;

    return Container(
      color: Colors.white,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: PageView.builder(
                controller: _controller,
                itemCount: virtualCount,
                onPageChanged: (virtualIndex) {
                  final logical = _logicalIndex(virtualIndex);
                  widget.changed(logical);
                  // Keep a large safety margin from either end of the virtual
                  // range so swiping remains circular for normal use.
                  if (virtualIndex < 1000 || virtualIndex > virtualCount - 1000) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_controller.hasClients || data.length <= 1) return;
                      _controller.jumpToPage(_initialVirtualPage() + logical);
                    });
                  }
                },
                itemBuilder: (_, virtualIndex) {
                  final logical = _logicalIndex(virtualIndex);
                  return _DetailNetworkImage(
                    url: sxText(data[logical]['url']),
                  );
                },
              ),
            ),
            ..._galleryBadgeWidgets(widget.badges),
            if (data.length > 1)
              Positioned(
                left: 10,
                bottom: 10,
                child: _DetailCounter(
                  text: (widget.page + 1).toString() + '/' + data.length.toString(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
List<Widget> _galleryBadgeWidgets(List<Map<String, dynamic>> badges) {
  final selected = badges.where((badge) {
    final s = badge['settings'] is Map
        ? Map<String, dynamic>.from(badge['settings'] as Map)
        : <String, dynamic>{};
    return s['visible'] != false &&
        {
          'top_right',
          'top_left',
          'bottom_right',
          'bottom_left',
          'right_of_image',
        }.contains(sxText(s['position']));
  }).toList();

  return selected.take(8).map((badge) {
    final s = badge['settings'] is Map
        ? Map<String, dynamic>.from(badge['settings'] as Map)
        : <String, dynamic>{};
    final label = sxText(
      badge['custom_text'],
      sxText(badge['name'], 'شارة'),
    );
    final bg = sxColor(
      sxText(s['background_color'], sxText(badge['bg_color'], '#111827')),
      Colors.black,
    ).withOpacity(
      sxDouble(s['background_opacity'], 1).clamp(0, 1).toDouble(),
    );
    final fg = sxColor(
      sxText(s['text_color'], sxText(badge['text_color'], '#ffffff')),
      Colors.white,
    );
    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: sxDouble(s['padding_horizontal'], 7),
        vertical: sxDouble(s['padding_vertical'], 3),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          sxDouble(s['border_radius'], 5),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: sxDouble(s['font_size'], 9),
          fontWeight: _weight(sxInt(s['font_weight'], 800)),
        ),
      ),
    );
    switch (sxText(s['position'])) {
      case 'top_left':
        return Positioned(top: 8, left: 8, child: chip);
      case 'bottom_left':
        return Positioned(bottom: 8, left: 8, child: chip);
      case 'bottom_right':
        return Positioned(bottom: 8, right: 8, child: chip);
      case 'right_of_image':
        return Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          child: Center(child: chip),
        );
      default:
        return Positioned(top: 48, right: 8, child: chip);
    }
  }).toList();
}

class SxGalleryThumbs extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final int page;
  final ValueChanged<int> changed;
  final double itemWidth;
  final double itemHeight;
  final double gap;
  final double radius;
  final double borderWidth;
  final List<Map<String, dynamic>> colorRows;

  const SxGalleryThumbs({
    super.key,
    required this.rows,
    required this.page,
    required this.changed,
    this.itemWidth = 62,
    this.itemHeight = 70,
    this.gap = 6,
    this.radius = 4,
    this.borderWidth = 1.5,
    this.colorRows = const [],
  });

  Color _colorFor(Map<String, dynamic> row) {
    final colorId = sxInt(row['color_id']);
    final match = colorRows.where((x) => sxInt(x['id']) == colorId);
    if (match.isEmpty) return const Color(0xFFE5E7EB);
    return sxColor(sxText(match.first['hex_code'], '#E5E7EB'), const Color(0xFFE5E7EB));
  }

  @override
  Widget build(BuildContext context) {
    if (rows.length < 2) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 5),
      child: SizedBox(
        height: itemHeight + 8,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: false,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int index = 0; index < rows.length; index++)
                  Padding(
                    padding: EdgeInsets.only(left: index == rows.length - 1 ? 0 : gap),
                    child: InkWell(
                      onTap: () => changed(index),
                      borderRadius: BorderRadius.circular(radius),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        width: itemWidth,
                        height: itemHeight,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: index == page ? Colors.black : ClientTheme.border,
                            width: index == page ? borderWidth : .7,
                          ),
                          borderRadius: BorderRadius.circular(radius),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _DetailNetworkImage(url: sxText(rows[index]['url'])),
                            if (sxInt(rows[index]['color_id']) > 0)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _colorFor(rows[index]),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.4),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x22000000),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddToCartConfirmation extends StatefulWidget {
  final String productName;
  final String color;
  final String size;
  final int maxQuantity;

  const _AddToCartConfirmation({
    required this.productName,
    required this.color,
    required this.size,
    required this.maxQuantity,
  });

  @override
  State<_AddToCartConfirmation> createState() => _AddToCartConfirmationState();
}

class _AddToCartConfirmationState extends State<_AddToCartConfirmation> {
  int quantity = 1;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (widget.color.trim().isNotEmpty) 'اللون: ' + widget.color,
      if (widget.size.trim().isNotEmpty) 'المقاس: ' + widget.size,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 17),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DetailHandle(),
            const SizedBox(height: 10),
            const Text(
              'تأكيد الإضافة إلى عربة التسوق',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              widget.productName,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                details.join('  •  '),
                style: const TextStyle(fontSize: 9.5, color: ClientTheme.muted),
              ),
            ],
            const SizedBox(height: 12),
            if (widget.maxQuantity > 0) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'المتاح: ${widget.maxQuantity}',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: ClientTheme.muted),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text('الكمية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                ),
                Container(
                  height: 39,
                  decoration: BoxDecoration(
                    border: Border.all(color: ClientTheme.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: quantity >= widget.maxQuantity
                            ? null
                            : () => setState(() => quantity++),
                        icon: const Icon(Icons.add, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 39, height: 39),
                      ),
                      SizedBox(
                        width: 42,
                        child: Center(
                          child: Text(
                            quantity.toString(),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: quantity <= 1 ? null : () => setState(() => quantity--),
                        icon: const Icon(Icons.remove, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 39, height: 39),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, quantity),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                style: FilledButton.styleFrom(backgroundColor: Colors.black),
                label: const Text(
                  'أضف إلى عربة التسوق',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailNetworkImage extends StatelessWidget {
  final String url;
  const _DetailNetworkImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final resolved = api.url(url);
    if (resolved.isEmpty) {
      return Container(
        color: ClientTheme.soft,
        child: const Icon(Icons.image_outlined, color: Color(0xFF9AA0A6)),
      );
    }
    return CachedNetworkImage(
      imageUrl: resolved,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => Container(color: ClientTheme.soft),
      errorWidget: (_, __, ___) => Container(
        color: ClientTheme.soft,
        child: const Icon(Icons.image_outlined, color: Color(0xFF9AA0A6)),
      ),
    );
  }
}


int _discountValue(String current, String previous) {
  final now = double.tryParse(current);
  final old = double.tryParse(previous);
  if (now == null || old == null || old <= now || old <= 0) return 0;
  return ((1 - now / old) * 100).round();
}

class _DetailTrendSection extends StatelessWidget {
  final List<Map<String, dynamic>> trends;
  final Map<String, dynamic> settings;

  const _DetailTrendSection({
    required this.trends,
    this.settings = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (settings['trend_show'] == false) return const SizedBox.shrink();
    final visible = trends.where((x) {
      final s = x['settings'];
      return s is! Map || s['visible'] != false;
    }).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final bg = sxColor(sxText(settings['trend_background_color']), const Color(0xFFF2E8FF));
    final titleColor = sxColor(sxText(settings['trend_title_color']), const Color(0xFF8B5CF6));
    final hashtagColor = sxColor(sxText(settings['trend_hashtag_color']), const Color(0xFF7C3AED));
    final arrowColor = sxColor(sxText(settings['trend_arrow_color']), hashtagColor);
    final height = sxDouble(settings['trend_height'], 46);
    final horizontal = sxDouble(settings['trend_padding_horizontal'], 12);

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++)
          Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                bottom: BorderSide(
                  color: sxColor(sxText(settings['trend_divider_color']), const Color(0xFFE9D5FF)),
                  width: i == visible.length - 1 ? 0 : .7,
                ),
              ),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    sxText(settings['trend_title'], 'ترندات'),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: sxDouble(settings['trend_title_font_size'], 17),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (settings['trend_show_hashtag'] != false)
                  Expanded(
                    flex: 2,
                    child: Text(
                      sxText(
                        (visible[i]['hashtag'] as Map?)?['display_name'],
                        sxText(visible[i]['hashtag'] is Map ? (visible[i]['hashtag'] as Map)['name'] : null, '#trend'),
                      ),
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hashtagColor,
                        fontSize: sxDouble(settings['trend_hashtag_font_size'], 12),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (settings['trend_show_arrow'] == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.chevron_left, size: 18, color: arrowColor),
                  ),
                if (settings['trend_show_promo'] == true)
                  const SizedBox(width: 6),
                if (settings['trend_show_promo'] == true)
                  Flexible(
                    child: Text(
                      sxText(visible[i]['promo_text']),
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hashtagColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DetailPromotionsSection extends StatelessWidget {
  final List<Map<String, dynamic>> strips;
  final List<Map<String, dynamic>> campaigns;
  const _DetailPromotionsSection({
    required this.strips,
    required this.campaigns,
  });

  IconData _iconFor(Map<String, dynamic> row) {
    final key = sxText(row['icon']).toLowerCase();
    if (key.contains('gift')) return Icons.card_giftcard_outlined;
    if (key.contains('club')) return Icons.workspace_premium_outlined;
    if (key.contains('ship')) return Icons.local_shipping_outlined;
    if (key.contains('percent') || key.contains('discount')) return Icons.percent_outlined;
    return Icons.local_offer_outlined;
  }

  @override
  Widget build(BuildContext context) {
    if (strips.isEmpty && campaigns.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          for (final strip in strips)
            InkWell(
              onTap: () {},
              child: Container(
                constraints: const BoxConstraints(minHeight: 42),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF0F0F0), width: .7),
                  ),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      _iconFor(strip),
                      size: 16,
                      color: sxColor(sxText(strip['text_color']), const Color(0xFF7C2D12)),
                    ),
                    const SizedBox(width: 7),
                    if (sxText(strip['prefix']).isNotEmpty)
                      Text(
                        sxText(strip['prefix']),
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: sxColor(sxText(strip['text_color']), const Color(0xFF7C2D12)),
                        ),
                      ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        sxText(strip['text'], sxText(strip['name'], 'عرض خاص')),
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: sxColor(sxText(strip['text_color']), const Color(0xFF7C2D12)),
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_left, size: 17, color: Color(0xFF777777)),
                  ],
                ),
              ),
            ),
          for (final campaign in campaigns)
            Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF0F0F0), width: .7),
                ),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  const Icon(Icons.local_offer_outlined, size: 15),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      sxText(campaign['text'], sxText(campaign['name'], 'عرض')),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveryPolicyBox extends StatelessWidget {
  final List<Map<String, dynamic>> deliveryBadges;
  final Map<String, dynamic> policies;
  final Map<String, dynamic> settings;

  const _DeliveryPolicyBox({
    required this.deliveryBadges,
    required this.policies,
    required this.settings,
  });

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _showDetails(
    BuildContext context, {
    required String title,
    required String text,
  }) async {
    if (settings['policy_show_dialog'] == false) return;
    if (text.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          title,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10.5, height: 1.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget row(
    BuildContext context, {
    required IconData icon,
    required String title,
    String subtitle = '',
    VoidCallback? onTap,
    bool arrow = true,
    bool divider = true,
    Color iconColor = Colors.black,
    Color titleColor = Colors.black,
  }) {
    final height = sxDouble(settings['delivery_row_height'], 54).clamp(40, 76).toDouble();
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: divider
                  ? sxColor(
                      sxText(settings['delivery_row_divider_color']),
                      const Color(0xFFEEEEEE),
                    )
                  : Colors.transparent,
              width: divider
                  ? sxDouble(settings['delivery_row_divider_width'], .7)
                  : 0,
            ),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: sxDouble(settings['delivery_row_icon_size'], 19),
              color: iconColor,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: sxDouble(settings['delivery_row_title_font_size'], 11),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: sxDouble(settings['delivery_row_subtitle_font_size'], 9.5),
                          color: ClientTheme.muted,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (arrow && settings['policy_show_arrows'] != false)
              const Padding(
                padding: EdgeInsets.only(left: 1),
                child: Icon(
                  Icons.chevron_left,
                  size: 19,
                  color: Color(0xFF555555),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shipping = _map(policies['shipping']);
    final returning = _map(policies['return']);
    final warranty = _map(policies['warranty']);

    final returnDays = sxInt(returning['return_window_days']);
    final warrantyDays = sxInt(warranty['duration_days']);

    final policyItems = <String, Map<String, dynamic>>{
      'shipping': {
        'title': 'الشحن والتوصيل',
        'icon': Icons.local_shipping_outlined,
        'subtitle': <String>[
          sxText(shipping['promo_text']),
          if (sxText(shipping['delivery_window']).isNotEmpty)
            'التوصيل المتوقع: ' + sxText(shipping['delivery_window']),
          if (shipping['free_shipping_enabled'] == true &&
              sxText(shipping['min_order_amount']).isNotEmpty)
            'شحن مجاني عند ' + sxText(shipping['min_order_amount']),
        ].where((x) => x.trim().isNotEmpty).join(' · '),
        'dialog': <String>[
          sxText(shipping['name']),
          sxText(shipping['promo_text']),
          if (sxText(shipping['delivery_window']).isNotEmpty)
            'مدة التوصيل: ' + sxText(shipping['delivery_window']),
          if (shipping['free_shipping_enabled'] == true &&
              sxText(shipping['min_order_amount']).isNotEmpty)
            'شحن مجاني عند بلوغ ' + sxText(shipping['min_order_amount']),
        ].where((x) => x.trim().isNotEmpty).join('\n\n'),
      },
      'returns': {
        'title': 'إرجاع مجاني',
        'icon': Icons.assignment_return_outlined,
        'subtitle': returnDays > 0
            ? 'إرجاع مجاني خلال ' + returnDays.toString() + ' يومًا'
            : 'اضغط لعرض سياسة الإرجاع والاسترداد',
        'dialog': <String>[
          sxText(returning['name']),
          if (returnDays > 0)
            'مدة الإرجاع: ' + returnDays.toString() + ' يومًا',
          sxText(returning['conditions']),
          sxText(returning['fee_rule']),
          sxText(returning['refund_method']),
        ].where((x) => x.trim().isNotEmpty).join('\n\n'),
      },
      'warranty': {
        'title': 'الضمان',
        'icon': Icons.verified_user_outlined,
        'subtitle': warrantyDays > 0
            ? 'ضمان لمدة ' + warrantyDays.toString() + ' يومًا'
            : sxText(warranty['coverage'], 'اضغط لعرض تفاصيل الضمان'),
        'dialog': <String>[
          sxText(warranty['name']),
          if (warrantyDays > 0)
            'المدة: ' + warrantyDays.toString() + ' يومًا',
          sxText(warranty['coverage']),
          sxText(warranty['exclusions']),
          sxText(warranty['claim_method']),
        ].where((x) => x.trim().isNotEmpty).join('\n\n'),
      },
      'payment': {
        'title': 'الدفع عند الاستلام · مدفوعات آمنة · حماية الخصوصية',
        'icon': Icons.shield_outlined,
        'subtitle': 'طرق الدفع المتاحة تظهر عند إتمام الطلب',
        'dialog': 'الدفع يتم وفق طرق الدفع المتاحة عند إتمام الطلب.',
      },
    };

    final rows = <Widget>[];

    if (settings['delivery_location_show'] != false) {
      rows.add(
        row(
          context,
          icon: Icons.location_on_outlined,
          title: sxText(settings['delivery_location_title'], 'الشحن إلى'),
          subtitle: sxText(settings['delivery_location_country'], 'Saudi Arabia'),
          arrow: true,
          iconColor: sxColor(
            sxText(settings['delivery_location_color']),
            Colors.black,
          ),
          titleColor: sxColor(
            sxText(settings['delivery_location_color']),
            Colors.black,
          ),
        ),
      );
    }

    final visibleDelivery = deliveryBadges.where((x) => x['visible'] != false).toList();
    for (final badge in visibleDelivery) {
      final title = sxText(badge['text'], 'التوصيل');
      final subtitle = sxText(
        badge['subtitle'],
        sxText(badge['details']),
      );
      rows.add(
        row(
          context,
          icon: Icons.local_shipping_outlined,
          title: title,
          subtitle: subtitle,
          onTap: () => _showDetails(
            context,
            title: title,
            text: sxText(badge['details'], subtitle),
          ),
          iconColor: sxColor(sxText(badge['text_color']), Colors.black),
        ),
      );
    }

    final order = <String>[];
    final rawOrder = settings['policy_order'];
    if (rawOrder is List) {
      for (final key in rawOrder) {
        final k = sxText(key);
        if (policyItems.containsKey(k) && !order.contains(k)) order.add(k);
      }
    }
    for (final key in policyItems.keys) {
      if (!order.contains(key)) order.add(key);
    }

    for (final key in order) {
      final item = policyItems[key];
      if (item == null) continue;
      final hasContent = key == 'payment' ||
          (key == 'shipping' && (shipping.isNotEmpty || sxText(item['subtitle']).isNotEmpty)) ||
          (key == 'returns' && returning.isNotEmpty) ||
          (key == 'warranty' && warranty.isNotEmpty);
      if (!hasContent) continue;

      rows.add(
        row(
          context,
          icon: item['icon'] as IconData,
          title: sxText(item['title']),
          subtitle: sxText(item['subtitle']),
          onTap: () => _showDetails(
            context,
            title: sxText(item['title']),
            text: sxText(item['dialog']),
          ),
          divider: true,
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
      child: Column(children: rows),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final double average;
  final int count;
  final List<Map<String, dynamic>> reviews;
  final VoidCallback onWriteReview;
  final Map<String, dynamic> settings;
  const _ReviewSection({
    required this.average,
    required this.count,
    required this.reviews,
    required this.onWriteReview,
    this.settings = const {},
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المراجعات',
                    style: TextStyle(
                      fontSize: sxDouble(settings['reviews_title_font_size'], 13),
                      fontWeight: FontWeight.w900,
                      color: sxColor(sxText(settings['reviews_color']), Colors.black),
                    ),
                  ),
                ),
                if (count > 0)
                  Text(
                    count.toString() + ' تقييم',
                    style: const TextStyle(fontSize: 9, color: ClientTheme.muted),
                  ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 38,
                  child: FilledButton.icon(
                    onPressed: onWriteReview,
                    icon: const Icon(Icons.star_outline_rounded, size: 16),
                    label: const Text(
                      'قيّم المنتج',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(112, 38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (average > 0)
              Row(
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 7),
                  Row(
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < average.round()
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 15,
                        color: const Color(0xFFFFB400),
                      ),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'لا توجد تقييمات منشورة لهذا المنتج بعد.',
                style: TextStyle(fontSize: 9.5, color: ClientTheme.muted),
              ),
            if (reviews.isNotEmpty) ...[
              const Divider(height: 22),
              for (final review in reviews.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Row(
                            children: List.generate(
                              5,
                              (index) => Icon(
                                index < sxInt(review['rating'])
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 12,
                                color: const Color(0xFFFFB400),
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Text('عميل', style: TextStyle(fontSize: 8, color: ClientTheme.muted)),
                        ],
                      ),
                      if (sxText(review['title']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            sxText(review['title']),
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                      if (sxText(review['body']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            sxText(review['body']),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, height: 1.45),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
}

class _ReviewComposer extends StatefulWidget {
  final Future<void> Function(int rating, String? title, String? body) onSubmit;
  const _ReviewComposer({required this.onSubmit});

  @override
  State<_ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<_ReviewComposer> {
  int rating = 5;
  bool saving = false;
  final titleController = TextEditingController();
  final bodyController = TextEditingController();

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => saving = true);
    try {
      await widget.onSubmit(
        rating,
        titleController.text.trim().isEmpty ? null : titleController.text.trim(),
        bodyController.text.trim().isEmpty ? null : bodyController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(14, 9, 14, MediaQuery.viewInsetsOf(context).bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DetailHandle(),
          const SizedBox(height: 9),
          const Text('أضف تقييمك', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) => IconButton(
              onPressed: saving ? null : () => setState(() => rating = index + 1),
              icon: Icon(
                index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                color: const Color(0xFFFFB400),
                size: 26,
              ),
            )),
          ),
          TextField(controller: titleController, enabled: !saving, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'عنوان مختصر (اختياري)')),
          const SizedBox(height: 7),
          TextField(controller: bodyController, enabled: !saving, maxLines: 4, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'تعليقك')),
          const SizedBox(height: 10),
          SizedBox(height: 46, child: FilledButton(onPressed: saving ? null : submit, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: Text(saving ? 'جارٍ الحفظ...' : 'إرسال التقييم'))),
        ],
      ),
    ),
  );
}

class _DetailBadgeStrip extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> badges;
  final Set<String> positions;
  final double gap;
  const _DetailBadgeStrip({
    required this.title,
    required this.badges,
    required this.positions,
    this.gap = 5,
  });

  @override
  Widget build(BuildContext context) {
    final rows = badges.where((badge) {
      final s = badge['settings'] is Map
          ? Map<String, dynamic>.from(badge['settings'] as Map)
          : <String, dynamic>{};
      return s['visible'] != false && positions.contains(sxText(s['position']));
    }).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    Color color(dynamic value, Color fallback) => sxColor(sxText(value), fallback);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gap > 0) SizedBox(height: gap),
          Wrap(
            textDirection: TextDirection.rtl,
            spacing: gap,
            runSpacing: gap,
            children: rows.map((badge) {
              final s = badge['settings'] is Map
                  ? Map<String, dynamic>.from(badge['settings'] as Map)
                  : <String, dynamic>{};
              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: sxDouble(s['padding_horizontal'], 8),
                  vertical: sxDouble(s['padding_vertical'], 4),
                ),
                decoration: BoxDecoration(
                  color: color(s['background_color'], color(badge['bg_color'], Colors.black))
                      .withOpacity(sxDouble(s['background_opacity'], 1).clamp(0, 1)),
                  borderRadius: BorderRadius.circular(sxDouble(s['border_radius'], 5)),
                ),
                child: Text(
                  sxText(badge['custom_text'], sxText(badge['name'], 'شارة')),
                  style: TextStyle(
                    color: color(s['text_color'], color(badge['text_color'], Colors.white)),
                    fontSize: sxDouble(s['font_size'], 9),
                    fontWeight: _weight(sxInt(s['font_weight'], 800)),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}


class _StockStatusPanel extends StatelessWidget {
  final int availableQty;
  final bool hasVariant;
  final double fontSize;
  final Color textColor;

  const _StockStatusPanel({
    required this.availableQty,
    required this.hasVariant,
    this.fontSize = 10,
    this.textColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    final inStock = hasVariant && availableQty > 0;
    final text = !hasVariant
        ? 'اختر اللون والمقاس لمعرفة التوفر'
        : inStock
            ? (availableQty <= 5
                ? 'متوفر — تبقى ' + availableQty.toString() + ' فقط'
                : 'متوفر في المخزون')
            : 'غير متوفر حاليًا';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text(
                'المخزون والتوفر',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              content: Text(
                text,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.65,
                  color: textColor,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
          icon: Icon(
            inStock ? Icons.inventory_2_outlined : Icons.inventory_2_outlined,
            size: 18,
            color: inStock ? const Color(0xFF15803D) : ClientTheme.muted,
          ),
          label: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: inStock ? const Color(0xFF15803D) : textColor,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE6E6E6)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
        ),
      ),
    );
  }
}


class _ProductBottomBar extends StatelessWidget {
  final String price;
  final String currency;
  final VoidCallback onAdd;
  final int availableQty;

  const _ProductBottomBar({
    required this.price,
    required this.currency,
    required this.onAdd,
    required this.availableQty,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(color: ClientTheme.border, width: .8),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: availableQty > 0 ? onAdd : null,
            icon: Icon(
              availableQty > 0
                  ? Icons.shopping_bag_outlined
                  : Icons.remove_shopping_cart_outlined,
              size: 18,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: availableQty > 0 ? Colors.black : const Color(0xFFBDBDBD),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            label: Text(
              availableQty > 0
                  ? 'أضف إلى عربة التسوق  ·  $price $currency'
                  : 'غير متوفر حاليًا',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    ),
  );
}
class _DetailSectionTitle extends StatelessWidget {
  final String title;
  const _DetailSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: foreground,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _DetailCounter extends StatelessWidget {
  final String text;
  const _DetailCounter({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.62),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
        ),
      );
}

class _DetailHandle extends StatelessWidget {
  const _DetailHandle();

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFD4D4D4),
          borderRadius: BorderRadius.circular(10),
        ),
      );
}

class _SizeGuide extends StatelessWidget {
  const _SizeGuide();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 9, 15, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DetailHandle(),
              const SizedBox(height: 10),
              const Text(
                'دليل المقاسات',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              const Text(
                'اختر المقاس وفق جدول المنتج والقياسات المتاحة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, height: 1.5),
              ),
            ],
          ),
        ),
      );
}

class _SizeGuideButton extends StatelessWidget {
  final Map<String, dynamic> guide;
  final Map<String, dynamic> settings;
  const _SizeGuideButton({required this.guide, required this.settings});

  @override
  Widget build(BuildContext context) {
    final font = sxDouble(settings['size_guide_font_size'], 10);
    final fg = sxColor(sxText(settings['size_guide_color']), Colors.black);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _SizeGuideDialog(guide: guide),
          ),
          icon: Icon(Icons.straighten_outlined, size: font + 5, color: fg),
          label: Text(
            'دليل المقاسات',
            style: TextStyle(fontSize: font, fontWeight: FontWeight.w900, color: fg),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: sxColor(
              sxText(settings['size_guide_background_color']),
              Colors.white,
            ),
            side: BorderSide(color: fg),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
        ),
      ),
    );
  }
}


class _SizeGuideDialog extends StatefulWidget {
  final Map<String, dynamic> guide;
  final int? initialSizeId;

  const _SizeGuideDialog({
    required this.guide,
    this.initialSizeId,
  });

  @override
  State<_SizeGuideDialog> createState() => _SizeGuideDialogState();
}

class _SizeGuideDialogState extends State<_SizeGuideDialog> {
  int? selectedIndex;

  @override
  void initState() {
    super.initState();
    final rawRows = widget.guide['rows'];
    if (widget.initialSizeId != null && rawRows is List) {
      for (var i = 0; i < rawRows.length; i++) {
        final row = rawRows[i];
        if (row is Map && sxInt(row['size_id']) == widget.initialSizeId) {
          selectedIndex = i;
          break;
        }
      }
    }
  }

  String _value(Map<String, dynamic> map, String key) {
    final value = sxText(map[key]);
    return value.isEmpty ? '—' : value;
  }

  String _label(String key) {
    const labels = <String, String>{
      'length': 'الطول',
      'height': 'الطول',
      'chest': 'الصدر',
      'bust': 'الصدر',
      'waist': 'الخصر',
      'hip': 'الأرداف',
      'hips': 'الأرداف',
      'shoulder': 'الكتف',
      'sleeve': 'طول الكم',
      'sleeve_length': 'طول الكم',
      'inseam': 'طول الساق الداخلي',
      'outseam': 'طول الساق',
      'width': 'العرض',
    };
    return labels[key] ?? key;
  }

  List<String> _metricKeys(List<Map<String, dynamic>> rows) {
    final keys = <String>[];
    for (final row in rows) {
      for (final key in _asMap(row['product_measurements']).keys) {
        final k = key.toString();
        if (!keys.contains(k)) keys.add(k);
      }
    }
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.guide['rows'] is List
        ? (widget.guide['rows'] as List)
            .whereType<Map>()
            .map((x) => Map<String, dynamic>.from(x))
            .toList()
        : <Map<String, dynamic>>[];
    final metrics = _metricKeys(rows);
    final selected = selectedIndex == null || selectedIndex! >= rows.length
        ? null
        : rows[selectedIndex!];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.straighten_outlined, size: 20),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        sxText(widget.guide['name'], 'دليل المقاسات'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
                if (sxText(widget.guide['intro_text']).isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        sxText(widget.guide['intro_text']),
                        style: const TextStyle(fontSize: 9.5, height: 1.5, color: ClientTheme.muted),
                      ),
                    ),
                  ),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(child: Text('لا توجد بيانات جدول المقاسات لهذا المنتج حاليًا.'))
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: ClientTheme.border, width: .7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    Container(
                                      color: const Color(0xFFF5F5F5),
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                                      child: Row(
                                        textDirection: TextDirection.rtl,
                                        children: [
                                          const SizedBox(
                                            width: 58,
                                            child: Text(
                                              'المقاس',
                                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
                                            ),
                                          ),
                                          for (final key in metrics)
                                            Expanded(
                                              child: Text(
                                                _label(key),
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    for (var i = 0; i < rows.length; i++)
                                      InkWell(
                                        onTap: () => setState(() => selectedIndex = selectedIndex == i ? null : i),
                                        child: Container(
                                          color: selectedIndex == i ? const Color(0xFFF9FAFB) : Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
                                          child: Row(
                                            textDirection: TextDirection.rtl,
                                            children: [
                                              SizedBox(
                                                width: 58,
                                                child: Text(
                                                  sxText(rows[i]['size_label'], sxText(rows[i]['size_code'], '—')),
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                                                ),
                                              ),
                                              for (final key in metrics)
                                                Expanded(
                                                  child: Text(
                                                    _value(_asMap(rows[i]['product_measurements']), key),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(fontSize: 8.5, height: 1.35),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (selected != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F7F7),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(color: ClientTheme.border, width: .7),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'تفاصيل المقاس ' + sxText(selected['size_label'], sxText(selected['size_code'], '')),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 8),
                                      _MeasurementPanel(
                                        title: 'قياسات المنتج',
                                        values: _asMap(selected['product_measurements']),
                                      ),
                                      const SizedBox(height: 7),
                                      _MeasurementPanel(
                                        title: 'قياسات الجسم',
                                        values: _asMap(selected['body_measurements']),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasurementPanel extends StatelessWidget {
  final String title;
  final Map<String, dynamic> values;
  const _MeasurementPanel({required this.title, required this.values});

  String _label(String key) {
    const labels = <String, String>{
      'length': 'الطول',
      'height': 'الطول',
      'chest': 'الصدر',
      'bust': 'الصدر',
      'waist': 'الخصر',
      'hip': 'الأرداف',
      'hips': 'الأرداف',
      'shoulder': 'الكتف',
      'sleeve': 'طول الكم',
      'sleeve_length': 'طول الكم',
      'width': 'العرض',
    };
    return labels[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text(
        title + ': لا توجد قياسات مسجلة.',
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 9, color: ClientTheme.muted),
      );
    }
    return Wrap(
      textDirection: TextDirection.rtl,
      spacing: 6,
      runSpacing: 6,
      children: values.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: ClientTheme.border, width: .7),
          ),
          child: Text(
            _label(entry.key) + ': ' + sxText(entry.value, '—'),
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
          ),
        );
      }).toList(),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

FontWeight _weight(int value) {
  if (value >= 900) return FontWeight.w900;
  if (value >= 800) return FontWeight.w800;
  if (value >= 700) return FontWeight.w700;
  if (value >= 600) return FontWeight.w600;
  if (value >= 500) return FontWeight.w500;
  return FontWeight.w400;
}

int? sxIntNullable(dynamic value) {
  if (value == null) return null;
  final parsed = sxInt(value);
  return parsed > 0 ? parsed : null;
}

int sxIntListLength(dynamic value) => value is List ? value.length : 0;
