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
  int? colorId;
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
        colorId = c > 0 ? c : null;
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
      final rows = await api.feed(
        category: scopeId != null && scopeId > 0 ? scopeId : null,
        currencyId: state.currencyId,
        sort: 'random',
        discoveryTab: null,
      );
      if (!mounted) return;
      final seen = <int>{widget.id};
      setState(() {
        related = rows.where((product) => seen.add(product.id))
            .take(sxInt(recommendation['limit'], 10).clamp(2, 20))
            .toList();
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
    if (colorId == null) return rows;
    return <Map<String, dynamic>>[
      ...rows.where((row) => row['color_id'] == null),
      ...rows.where((row) => sxInt(row['color_id']) == colorId),
    ];
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

    if (requiresColor && colorId == null) return null;
    if (requiresSize && sizeId == null) return null;

    for (final variant in variants) {
      final colorOk = !requiresColor || sxInt(variant['color_id']) == sxInt(colorId);
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
    if (colorId != null) {
      final matching = colors.where((x) => sxInt(x['id']) == colorId);
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
    if (colorId != null) {
      final matching = colors.where((x) => sxInt(x['id']) == colorId);
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
                  SliverToBoxAdapter(
                    child: SxGallery(
                      rows: media,
                      page: page,
                      changed: (index) => setState(() => page = index),
                      badges: _maps(data['badges']),
                    ),
                  ),
                  // Thumbnails belong to the gallery and are kept immediately
                  // underneath it, before any product information.
                  SliverToBoxAdapter(
                    child: SxGalleryThumbs(
                      rows: media,
                      page: page,
                      changed: (index) => setState(() => page = index),
                    ),
                  ),
                  // All badges intended for the start/before-price area.
                  SliverToBoxAdapter(
                    child: _DetailBadgeStrip(
                      title: 'الشارات',
                      badges: _maps(data['badges']),
                      positions: const {
                        'first',
                        'before_price',
                        'before_price_new_row',
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProductHeroInfo(
                      mode: 'price',
                      name: sxText(product['name'], 'منتج'),
                      brand: sxText(brand['name']),
                      sku: sxText(product['sku']),
                      price: price,
                      oldPrice: oldPrice,
                      currency: detailCurrency,
                      discount: discount,
                      average: average,
                      reviewCount: reviewCount,
                      showRating: display['show_rating'] != false,
                      showReviewCount: display['show_review_count'] != false,
                      badges: _maps(data['badges']),
                      trendBadges: trendBadges,
                      cardSettings: _asMap(data['product_card_settings']),
                      detailSettings: detailSettings,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProductHeroInfo(
                      mode: 'name',
                      name: sxText(product['name'], 'منتج'),
                      brand: sxText(brand['name']),
                      sku: sxText(product['sku']),
                      price: price,
                      oldPrice: oldPrice,
                      currency: detailCurrency,
                      discount: discount,
                      average: average,
                      reviewCount: reviewCount,
                      showRating: display['show_rating'] != false,
                      showReviewCount: display['show_review_count'] != false,
                      badges: _maps(data['badges']),
                      trendBadges: trendBadges,
                      cardSettings: _asMap(data['product_card_settings']),
                      detailSettings: detailSettings,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _DetailBadgeStrip(
                      title: 'الشارات قبل الوصف',
                      badges: _maps(data['badges']),
                      positions: const {
                        'before_description',
                        'before_description_new_row',
                        'before_details',
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _DetailSection(
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
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _DetailBadgeStrip(
                      title: 'الشارات بعد الوصف والتفاصيل',
                      badges: _maps(data['badges']),
                      positions: const {
                        'after_description',
                        'after_description_same_row',
                        'after_description_new_row',
                        'below_description',
                        'after_details',
                        'after_details_same_row',
                        'after_details_new_row',
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProductIdentityPanel(
                      brand: sxText(brand['name']),
                      productType: sxText(product['product_type']),
                      material: sxText(product['material']),
                      sku: sxText(product['sku']),
                    ),
                  ),
                  if (colors.isNotEmpty || sizes.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ProductOptions(
                        colors: colors,
                        sizes: sizes,
                        selectedColorId: colorId,
                        selectedSizeId: sizeId,
                        onColor: (value) => setState(() {
                          colorId = value;
                          page = 0;
                        }),
                        onSize: (value) => setState(() => sizeId = value),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _StockStatusPanel(
                      availableQty: _availableQty(),
                      hasVariant: _selectedVariant() != null,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _DeliveryBadgePanel(
                      badges: _maps(data['delivery_badges']),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProductTrust(
                      showShipping: display['show_shipping_banner'] != false,
                      showReturn: display['show_return'] != false,
                    ),
                  ),
                  SliverToBoxAdapter(child: _PolicySections(policies: policies)),
                  SliverToBoxAdapter(
                    child: _ReviewSection(
                      average: average,
                      count: reviewCount,
                      reviews: reviews,
                      onWriteReview: _openReviewComposer,
                    ),
                  ),
                  if (related.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          children: [
                            const _DetailSectionTitle(title: 'قد يعجبك أيضًا'),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  width: 58,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'التوصية',
                                    style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(7, 0, 7, 20),
                              child: SxProductGrid(
                                products: related,
                                masonry: false,
                                onProductTap: (product) => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SxProductScreen(id: product.id),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _DetailBadgeStrip(
                      title: 'الشارات الأخيرة',
                      badges: _maps(data['badges']),
                      positions: const {'last'},
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: _ProductBottomBar(
                price: price,
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

class SxGallery extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final int page;
  final ValueChanged<int> changed;
  final List<Map<String, dynamic>> badges;

  const SxGallery({
    super.key,
    required this.rows,
    required this.page,
    required this.changed,
    this.badges = const [],
  });

  @override
  Widget build(BuildContext context) {
    final data = rows.isEmpty
        ? <Map<String, dynamic>>[<String, dynamic>{}]
        : rows;
    return Container(
      color: Colors.white,
      child: AspectRatio(
        aspectRatio: .78,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: PageView.builder(
                itemCount: data.length,
                onPageChanged: changed,
                itemBuilder: (_, index) => _DetailNetworkImage(
                  url: sxText(data[index]['url']),
                ),
              ),
            ),
            ..._galleryBadgeWidgets(badges),
            if (data.length > 1)
              Positioned(
                left: 10,
                bottom: 10,
                child: _DetailCounter(
                  text: (page + 1).toString() + '/' + data.length.toString(),
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
    final s = badge['settings'] is Map ? Map<String, dynamic>.from(badge['settings'] as Map) : <String, dynamic>{};
    return s['visible'] != false && {'top_right','top_left','bottom_right','bottom_left','right_of_image'}.contains(sxText(s['position']));
  }).toList();
  return selected.take(8).map((badge) {
    final s = badge['settings'] is Map ? Map<String, dynamic>.from(badge['settings'] as Map) : <String, dynamic>{};
    final label = sxText(badge['custom_text'], sxText(badge['name'], 'شارة'));
    final bg = sxColor(sxText(s['background_color'], sxText(badge['bg_color'], '#111827')), Colors.black)
      .withOpacity(sxDouble(s['background_opacity'], 1).clamp(0, 1));
    final fg = sxColor(sxText(s['text_color'], sxText(badge['text_color'], '#ffffff')), Colors.white);
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: sxDouble(s['padding_horizontal'], 7), vertical: sxDouble(s['padding_vertical'], 3)),
      decoration: BoxDecoration(color:bg,borderRadius:BorderRadius.circular(sxDouble(s['border_radius'],5))),
      child: Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:fg,fontSize:sxDouble(s['font_size'],9),fontWeight:_weight(sxInt(s['font_weight'],800)))),
    );
    final pos=sxText(s['position']);
    return _galleryBadgePosition(pos, chip);
  }).toList();
}
Widget _galleryBadgePosition(String position, Widget child) {
  switch (position) {
    case 'top_left':
      return Positioned(top: 8, left: 8, child: child);
    case 'bottom_left':
      return Positioned(bottom: 8, left: 8, child: child);
    case 'bottom_right':
      return Positioned(bottom: 8, right: 8, child: child);
    case 'right_of_image':
      return Positioned(
        top: 0,
        right: 0,
        bottom: 0,
        child: Center(child: child),
      );
    default:
      return Positioned(top: 48, right: 8, child: child);
  }
}

class SxGalleryThumbs extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final int page;
  final ValueChanged<int> changed;

  const SxGalleryThumbs({
    super.key,
    required this.rows,
    required this.page,
    required this.changed,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.length < 2) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      child: SizedBox(
        height: 76,
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
                    padding: EdgeInsets.only(left: index == rows.length - 1 ? 0 : 6),
                    child: InkWell(
                      onTap: () => changed(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        width: 62,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: index == page ? Colors.black : ClientTheme.border,
                            width: index == page ? 1.5 : .7,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _DetailNetworkImage(url: sxText(rows[index]['url'])),
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

class _ProductHeroInfo extends StatelessWidget {
  final String name;
  final String brand;
  final String sku;
  final String price;
  final String oldPrice;
  final String currency;
  final int discount;
  final double average;
  final int reviewCount;
  final bool showRating;
  final bool showReviewCount;
  final List<Map<String, dynamic>> badges;
  final List<Map<String, dynamic>> trendBadges;
  final Map<String, dynamic> cardSettings;
  final Map<String, dynamic> detailSettings;
  final String mode;

  const _ProductHeroInfo({
    required this.name,
    required this.brand,
    required this.sku,
    required this.price,
    required this.oldPrice,
    required this.currency,
    required this.discount,
    required this.average,
    required this.reviewCount,
    required this.showRating,
    required this.showReviewCount,
    required this.badges,
    required this.trendBadges,
    required this.cardSettings,
    required this.detailSettings,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final first = <Map<String, dynamic>>[];
    final aboveImage = <Map<String, dynamic>>[];
    final beforeNameRow = <Map<String, dynamic>>[];
    final beforeNameSame = <Map<String, dynamic>>[];
    final afterNameSame = <Map<String, dynamic>>[];
    final afterNameRow = <Map<String, dynamic>>[];
    final beforePriceRow = <Map<String, dynamic>>[];
    final belowPrice = <Map<String, dynamic>>[];
    final beforePriceSame = <Map<String, dynamic>>[];
    final afterPriceSame = <Map<String, dynamic>>[];
    final afterPriceRow = <Map<String, dynamic>>[];
    final rightImage = <Map<String, dynamic>>[];

    for (final badge in badges) {
      final s = badge['settings'] is Map
          ? Map<String, dynamic>.from(badge['settings'] as Map)
          : <String, dynamic>{};
      final position = sxText(s['position'], 'before_name');
      switch (position) {
        case 'first':
          first.add(badge);
          break;
        case 'above_image':
          aboveImage.add(badge);
          break;
        case 'before_name_new_row':
        case 'before_name_row':
          beforeNameRow.add(badge);
          break;
        case 'before_name':
        case 'before_name_same_row':
          beforeNameSame.add(badge);
          break;
        case 'after_name_new_row':
        case 'after_name_row':
          afterNameRow.add(badge);
          break;
        case 'after_name':
        case 'after_name_same_row':
          afterNameSame.add(badge);
          break;
        case 'before_price_new_row':
        case 'before_price':
          beforePriceRow.add(badge);
          break;
        case 'before_price_same_row':
          beforePriceSame.add(badge);
          break;
        case 'after_price_same_row':
          afterPriceSame.add(badge);
          break;
        case 'after_price_new_row':
        case 'after_price':
          afterPriceRow.add(badge);
          break;
        case 'below_price':
          belowPrice.add(badge);
          break;
        case 'right_of_image':
          rightImage.add(badge);
          break;
        default:
          break;
      }
    }

    Widget chip(Map<String, dynamic> badge) {
      final s = badge['settings'] is Map
          ? Map<String, dynamic>.from(badge['settings'] as Map)
          : <String, dynamic>{};
      final bg = sxColor(
        sxText(s['background_color'], sxText(badge['bg_color'], '#111827')),
        Colors.black,
      ).withOpacity(sxDouble(s['background_opacity'], 1).clamp(0, 1));
      final fg = sxColor(
        sxText(s['text_color'], sxText(badge['text_color'], '#ffffff')),
        Colors.white,
      );
      final label = sxText(
        badge['custom_text'],
        sxText(badge['name'], sxText(badge['code'], 'شارة')),
      );
      Widget body = Container(
        padding: EdgeInsets.symmetric(
          horizontal: sxDouble(s['padding_horizontal'], 8),
          vertical: sxDouble(s['padding_vertical'], 4),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(sxDouble(s['border_radius'], 5)),
          border: Border.all(
            color: sxColor(sxText(s['border_color'], '#ffffff'), Colors.transparent),
            width: sxDouble(s['border_width'], 0),
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
            decoration: sxText(s['text_decoration']) == 'line_through'
                ? TextDecoration.lineThrough
                : TextDecoration.none,
          ),
        ),
      );
      return body;
    }

    Widget strip(List<Map<String, dynamic>> items, {bool compact = false}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 4 : 7),
        child: Wrap(
          textDirection: TextDirection.rtl,
          alignment: WrapAlignment.start,
          spacing: 5,
          runSpacing: 5,
          children: items.map(chip).toList(),
        ),
      );
    }

    final trends = trendBadges.map((trend) {
      final s = trend['settings'] is Map
          ? Map<String, dynamic>.from(trend['settings'] as Map)
          : <String, dynamic>{};
      final h = trend['hashtag'] is Map
          ? Map<String, dynamic>.from(trend['hashtag'] as Map)
          : <String, dynamic>{};
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: sxColor(
            sxText(s['trend_badge_background_color'], '#8B5CF6'),
            const Color(0xFF8B5CF6),
          ).withOpacity(sxDouble(s['trend_badge_background_opacity'], 1).clamp(0, 1)),
          borderRadius: BorderRadius.circular(sxDouble(s['trend_badge_radius'], 5)),
        ),
        child: Text(
          sxText(h['display_name'], sxText(trend['text'], 'ترند')),
          style: TextStyle(
            color: sxColor(sxText(s['trend_badge_text_color']), Colors.white),
            fontSize: sxDouble(s['trend_badge_font_size'], 9),
            fontWeight: _weight(sxInt(s['trend_badge_font_weight'], 800)),
          ),
        ),
      );
    }).toList();

    Widget priceBox() => Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          price,
          style: TextStyle(
            color: sxColor(sxText(cardSettings['price_color']), const Color(0xFF111111)),
            fontSize: sxDouble(cardSettings['price_font_size'], 22),
            fontWeight: _weight(sxInt(cardSettings['price_font_weight'], 900)),
            height: 1,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          currency,
          style: TextStyle(
            color: sxColor(sxText(cardSettings['currency_color']), const Color(0xFF111111)),
            fontSize: sxDouble(cardSettings['currency_font_size'], 10.5),
            fontWeight: _weight(sxInt(cardSettings['currency_font_weight'], 800)),
          ),
        ),
        if (oldPrice.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            oldPrice + ' ' + currency,
            style: TextStyle(
              fontSize: sxDouble(cardSettings['compare_price_font_size'], 10),
              color: sxColor(sxText(cardSettings['compare_price_color']), const Color(0xFF9CA3AF)),
              decoration: sxText(cardSettings['compare_price_text_decoration'], 'line_through') == 'line_through'
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ),
        ],
        if (discount > 0) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sxColor(sxText(cardSettings['discount_badge_background_color']), const Color(0xFFDC2626)),
              borderRadius: BorderRadius.circular(sxDouble(cardSettings['discount_badge_radius'], 5)),
            ),
            child: Text(
              'خصم $discount%',
              style: TextStyle(
                color: sxColor(sxText(cardSettings['discount_badge_text_color']), Colors.white),
                fontSize: sxDouble(cardSettings['discount_badge_font_size'], 9),
                fontWeight: _weight(sxInt(cardSettings['discount_badge_font_weight'], 900)),
              ),
            ),
          ),
        ],
      ],
    );

    Widget nameRow() => Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: sxInt(detailSettings['name_max_lines'], 4).clamp(2, 6).toInt(),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: sxColor(sxText(detailSettings['name_color']), const Color(0xFF111111)),
              fontSize: sxDouble(detailSettings['name_font_size'], 20),
              fontWeight: _weight(sxInt(detailSettings['name_font_weight'], 800)),
              height: 1.3,
            ),
          ),
        ),
        if (afterNameSame.isNotEmpty) ...[
          const SizedBox(width: 7),
          Flexible(child: Wrap(textDirection: TextDirection.rtl, spacing: 4, runSpacing: 4, children: afterNameSame.map(chip).toList())),
        ],
      ],
    );

    Widget beforeSameRow() {
      if (beforeNameSame.isEmpty) return nameRow();
      return Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Wrap(
              textDirection: TextDirection.rtl,
              spacing: 4,
              runSpacing: 4,
              children: beforeNameSame.map(chip).toList(),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              name,
              maxLines: sxInt(detailSettings['name_max_lines'], 4).clamp(2, 6).toInt(),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: sxColor(sxText(detailSettings['name_color']), const Color(0xFF111111)),
                fontSize: sxDouble(detailSettings['name_font_size'], 20),
                fontWeight: _weight(sxInt(detailSettings['name_font_weight'], 800)),
                height: 1.3,
              ),
            ),
          ),
        ],
      );
    }

    final priceChildren = <Widget>[
      if (trends.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Wrap(
            textDirection: TextDirection.rtl,
            spacing: 5,
            runSpacing: 5,
            children: trends,
          ),
        ),
      strip(beforePriceRow, compact: true),
      if (beforePriceSame.isNotEmpty || afterPriceSame.isNotEmpty)
        Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (beforePriceSame.isNotEmpty)
              Flexible(
                child: Wrap(
                  textDirection: TextDirection.rtl,
                  spacing: 4,
                  runSpacing: 4,
                  children: beforePriceSame.map(chip).toList(),
                ),
              ),
            if (beforePriceSame.isNotEmpty) const SizedBox(width: 6),
            Expanded(child: priceBox()),
            if (afterPriceSame.isNotEmpty) const SizedBox(width: 6),
            if (afterPriceSame.isNotEmpty)
              Flexible(
                child: Wrap(
                  textDirection: TextDirection.rtl,
                  spacing: 4,
                  runSpacing: 4,
                  children: afterPriceSame.map(chip).toList(),
                ),
              ),
          ],
        )
      else
        priceBox(),
      strip(afterPriceRow, compact: true),
      strip(belowPrice, compact: true),
    ];

    final nameChildren = <Widget>[
      strip(beforeNameRow, compact: true),
      beforeSameRow(),
      if (brand.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            brand,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 10,
              color: ClientTheme.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      if (afterNameRow.isNotEmpty) ...[
        const SizedBox(height: 4),
        strip(afterNameRow, compact: true),
      ],
      if (sku.isNotEmpty)
        Text(
          sku,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 8, color: Color(0xFF9CA3AF)),
        ),
      if (showRating)
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB400)),
              const SizedBox(width: 2),
              Text(
                average > 0 ? average.toStringAsFixed(1) : '—',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
              ),
              if (showReviewCount)
                Text(
                  ' · $reviewCount تقييم',
                  style: const TextStyle(fontSize: 9, color: ClientTheme.muted),
                ),
            ],
          ),
        ),
    ];

    final children = mode == 'price' ? priceChildren : nameChildren;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ProductIdentityPanel extends StatelessWidget {
  final String brand;
  final String productType;
  final String material;
  final String sku;
  const _ProductIdentityPanel({
    required this.brand,
    required this.productType,
    required this.material,
    required this.sku,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String,String>>[
      {'label':'العلامة التجارية','value':brand},
      {'label':'نوع المنتج','value':productType},
      {'label':'الخامة','value':material},
      {'label':'رمز المنتج','value':sku},
    ].where((x) => (x['value'] ?? '').trim().isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      child: Column(
        children: items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(item['label']!, style: const TextStyle(fontSize: 9, color: ClientTheme.muted))),
              const SizedBox(width: 10),
              Flexible(child: Text(item['value']!, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _DeliveryBadgePanel extends StatelessWidget {
  final List<Map<String,dynamic>> badges;
  const _DeliveryBadgePanel({required this.badges});

  @override
  Widget build(BuildContext context) {
    final visible = badges.where((x) => x['visible'] != false).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final groups = <String, List<Map<String,dynamic>>>{};
    for (final badge in visible) {
      final section = sxText(badge['section'], 'shipping');
      groups.putIfAbsent(section, () => <Map<String,dynamic>>[]).add(badge);
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('التوصيل والمزايا', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...groups.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _deliverySectionLabel(entry.key),
                  style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: entry.value.map((badge) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: sxColor(sxText(badge['background_color']), const Color(0xFFF5F5F5)),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (sxText(badge['icon']).isNotEmpty)
                          const Icon(Icons.local_shipping_outlined, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          sxText(badge['text']),
                          style: TextStyle(
                            color: sxColor(sxText(badge['text_color']), const Color(0xFF111111)),
                            fontSize: sxDouble(badge['font_size'], 9),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  String _deliverySectionLabel(String key) {
    switch (key) {
      case 'shipping':
        return 'الشحن';
      case 'returns':
        return 'الإرجاع';
      case 'payment':
        return 'الدفع';
      case 'warranty':
        return 'الضمان';
      default:
        return key;
    }
  }
}

class _ProductOptions extends StatelessWidget {
  final List<Map<String, dynamic>> colors;
  final List<Map<String, dynamic>> sizes;
  final int? selectedColorId;
  final int? selectedSizeId;
  final ValueChanged<int> onColor;
  final ValueChanged<int> onSize;

  const _ProductOptions({
    required this.colors,
    required this.sizes,
    required this.selectedColorId,
    required this.selectedSizeId,
    required this.onColor,
    required this.onSize,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (colors.isNotEmpty) ...[
              const Text('اللون', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                children: colors.map((item) {
                  final id = sxInt(item['id']);
                  final selected = id == selectedColorId;
                  return InkWell(
                    onTap: () => onColor(id),
                    borderRadius: BorderRadius.circular(30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sxColor(
                              sxText(item['hex_code'], '#D1D5DB'),
                              const Color(0xFFD1D5DB),
                            ),
                            border: Border.all(
                              color: selected ? Colors.black : Colors.white,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check, size: 17, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sxText(item['name']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            if (colors.isNotEmpty && sizes.isNotEmpty) const Divider(height: 24),
            if (sizes.isNotEmpty) ...[
              Row(
                children: [
                  const Expanded(
                    child: Text('المقاس', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      builder: (_) => const _SizeGuide(),
                    ),
                    child: const Text(
                      'دليل المقاسات',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: sizes.map((item) {
                  final id = sxInt(item['id']);
                  final selected = id == selectedSizeId;
                  return InkWell(
                    onTap: () => onSize(id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      constraints: const BoxConstraints(minWidth: 55),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? Colors.black : Colors.white,
                        border: Border.all(color: selected ? Colors.black : const Color(0xFFD8D8D8)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        sxText(item['label'], sxText(item['code'])),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
}

class _ProductSavings extends StatelessWidget {
  final int percent;
  final String price;
  final String oldPrice;
  final String currency;
  const _ProductSavings({
    required this.percent,
    required this.price,
    required this.oldPrice,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            _Pill(
              text: 'وفر ' + percent.toString() + '%',
              background: Colors.black,
              foreground: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'السعر الحالي ' + price + ' ' + currency +
                    ' بدلًا من ' + oldPrice + ' ' + currency,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _ProductTrust extends StatelessWidget {
  final bool showShipping;
  final bool showReturn;
  const _ProductTrust({
    required this.showShipping,
    required this.showReturn,
  });

  @override
  Widget build(BuildContext context) {
    if (!showShipping && !showReturn) return const SizedBox.shrink();
    final items = <Widget>[
      if (showShipping)
        const _TrustCell(
          icon: Icons.local_shipping_outlined,
          title: 'الشحن',
          text: 'المدة حسب العنوان',
        ),
      if (showReturn)
        const _TrustCell(
          icon: Icons.assignment_return_outlined,
          title: 'الإرجاع',
          text: 'حسب السياسة',
        ),
      const _TrustCell(
        icon: Icons.lock_outline,
        title: 'الدفع',
        text: 'دفع آمن',
      ),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: items.map((item) => Expanded(child: item)).toList()),
    );
  }
}

class _TrustCell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _TrustCell({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 3),
          Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 7.5, color: ClientTheme.muted),
          ),
        ],
      );
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        color: Colors.white,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          title: Row(
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                text.isEmpty ? 'لا توجد تفاصيل إضافية لهذا المنتج.' : text,
                style: const TextStyle(fontSize: 10.5, height: 1.65, color: Color(0xFF4B5563)),
              ),
            ),
          ],
        ),
      );
}

class _PolicySections extends StatelessWidget {
  final Map<String, dynamic> policies;
  const _PolicySections({required this.policies});

  @override
  Widget build(BuildContext context) {
    final shipping = _asMap(policies['shipping']);
    final returning = _asMap(policies['return']);
    final warranty = _asMap(policies['warranty']);
    final widgets = <Widget>[];

    if (shipping.isNotEmpty) {
      widgets.add(
        _DetailSection(
          title: 'الشحن والتوصيل',
          icon: Icons.local_shipping_outlined,
          text: <String>[
            sxText(shipping['name']),
            sxText(shipping['promo_text']),
            if (sxText(shipping['delivery_window']).isNotEmpty)
              'مدة التوصيل: ' + sxText(shipping['delivery_window']),
          ].where((x) => x.trim().isNotEmpty).join('\n\n'),
        ),
      );
    }
    if (returning.isNotEmpty) {
      widgets.add(
        _DetailSection(
          title: 'الإرجاع والاسترداد',
          icon: Icons.assignment_return_outlined,
          text: <String>[
            sxText(returning['name']),
            if (sxInt(returning['return_window_days']) > 0)
              'مدة الإرجاع: ' + sxInt(returning['return_window_days']).toString() + ' يومًا',
            sxText(returning['conditions']),
            if (sxText(returning['fee_rule']).isNotEmpty)
              'الرسوم: ' + sxText(returning['fee_rule']),
            if (sxText(returning['refund_method']).isNotEmpty)
              'طريقة الاسترداد: ' + sxText(returning['refund_method']),
          ].where((x) => x.trim().isNotEmpty).join('\n\n'),
        ),
      );
    }
    if (warranty.isNotEmpty) {
      widgets.add(
        _DetailSection(
          title: 'الضمان',
          icon: Icons.verified_user_outlined,
          text: <String>[
            sxText(warranty['name']),
            if (sxInt(warranty['duration_days']) > 0)
              'المدة: ' + sxInt(warranty['duration_days']).toString() + ' يومًا',
            sxText(warranty['coverage']),
            if (sxText(warranty['exclusions']).isNotEmpty)
              'الاستثناءات: ' + sxText(warranty['exclusions']),
            if (sxText(warranty['claim_method']).isNotEmpty)
              'طريقة المطالبة: ' + sxText(warranty['claim_method']),
          ].where((x) => x.trim().isNotEmpty).join('\n\n'),
        ),
      );
    }
    return Column(children: widgets);
  }
}

class _ReviewSection extends StatelessWidget {
  final double average;
  final int count;
  final List<Map<String, dynamic>> reviews;
  final VoidCallback onWriteReview;
  const _ReviewSection({
    required this.average,
    required this.count,
    required this.reviews,
    required this.onWriteReview,
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
                const Expanded(
                  child: Text('المراجعات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
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
  const _DetailBadgeStrip({
    required this.title,
    required this.badges,
    required this.positions,
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
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Wrap(
            textDirection: TextDirection.rtl,
            spacing: 5,
            runSpacing: 5,
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

  const _StockStatusPanel({
    required this.availableQty,
    required this.hasVariant,
  });

  @override
  Widget build(BuildContext context) {
    final inStock = hasVariant && availableQty > 0;
    final text = !hasVariant
        ? 'اختر اللون والمقاس لمعرفة التوفر'
        : inStock
            ? (availableQty <= 5
                ? 'متوفر — تبقى $availableQty فقط'
                : 'متوفر في المخزون')
            : 'غير متوفر حاليًا';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          Icon(
            inStock ? Icons.check_circle_outline : Icons.inventory_2_outlined,
            size: 19,
            color: inStock ? const Color(0xFF15803D) : ClientTheme.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: inStock ? const Color(0xFF15803D) : ClientTheme.muted,
              ),
            ),
          ),
        ],
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
