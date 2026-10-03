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
        final c = sxInt(variants.first['color_id']);
        final s = sxInt(variants.first['size_id']);
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

  int? _variantId() {
    final variants = _maps(data['variants']);
    for (final variant in variants) {
      final colorOk = colorId == null || sxInt(variant['color_id']) == colorId;
      final sizeOk = sizeId == null || sxInt(variant['size_id']) == sizeId;
      if (colorOk && sizeOk && sxInt(variant['id']) > 0) {
        return sxInt(variant['id']);
      }
    }
    return variants.isEmpty ? null : sxInt(variants.first['id']);
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
    try {
      await api.addCart(variant);
      final cart = await api.cart(currencyId: state.currencyId);
      cartBadge.value = sxIntListLength(cart['item']?['items']);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة المنتج إلى الحقيبة')),
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
      product['price'],
      sxText(product['base_price_sar'], '0'),
    );
    final oldPrice = sxText(product['compare_at_price']);
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
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProductHeroInfo(
                      name: sxText(product['name'], 'منتج'),
                      brand: sxText(brand['name']),
                      sku: sxText(product['sku']),
                      price: price,
                      oldPrice: oldPrice,
                      currency: state.currencySymbol,
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
                  if (discount > 0)
                    SliverToBoxAdapter(
                      child: _ProductSavings(
                        percent: discount,
                        price: price,
                        oldPrice: oldPrice,
                        currency: state.currencySymbol,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _ProductTrust(
                      showShipping: display['show_shipping_banner'] != false,
                      showReturn: display['show_return'] != false,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _DeliveryBadgePanel(
                      badges: _maps(data['delivery_badges']),
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
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: _ProductBottomBar(
                price: price,
                currency: state.currencySymbol,
                onAdd: _addToCart,
                onBuy: _buyNow,
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

  const SxGallery({
    super.key,
    required this.rows,
    required this.page,
    required this.changed,
  });

  @override
  Widget build(BuildContext context) {
    final data = rows.isEmpty
        ? <Map<String, dynamic>>[<String, dynamic>{}]
        : rows;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: .78,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  reverse: true,
                  itemCount: data.length,
                  onPageChanged: changed,
                  itemBuilder: (_, index) => _DetailNetworkImage(
                    url: sxText(data[index]['url']),
                  ),
                ),
                if (data.length > 1)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: _DetailCounter(
                      text: page.toString() + '/' + data.length.toString(),
                    ),
                  ),
                if (data.length > 1)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Row(
                      children: List.generate(
                        data.length.clamp(1, 8),
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: index == page ? 18 : 6,
                          height: 3,
                          margin: const EdgeInsets.only(left: 3),
                          decoration: BoxDecoration(
                            color: index == page ? Colors.white : Colors.white70,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (data.length > 1)
            SizedBox(
              height: 82,
              child: ListView.separated(
                reverse: true,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(7),
                itemCount: data.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, index) => InkWell(
                  onTap: () => changed(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    width: 62,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: index == page ? Colors.black : ClientTheme.border,
                        width: index == page ? 1.5 : .7,
                      ),
                    ),
                    child: _DetailNetworkImage(url: sxText(data[index]['url'])),
                  ),
                ),
              ),
            ),
        ],
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
  });

  @override
  Widget build(BuildContext context) {
    final globalBadgePosition = sxText(
      cardSettings['product_badge_position'],
      'before_name',
    );
    final beforeName = <Map<String, dynamic>>[];
    final afterName = <Map<String, dynamic>>[];
    final belowPrice = <Map<String, dynamic>>[];

    for (final badge in badges) {
      final settings = badge['settings'] is Map
          ? Map<String, dynamic>.from(badge['settings'] as Map)
          : <String, dynamic>{};
      final position = sxText(settings['position'], globalBadgePosition);
      if (position == 'after_name') {
        afterName.add(badge);
      } else if (position == 'below_price') {
        belowPrice.add(badge);
      } else {
        beforeName.add(badge);
      }
    }

    Widget badgeChip({
      required String text,
      required Color background,
      required Color foreground,
      required double fontSize,
      required int fontWeight,
      double radius = 5,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: fontSize,
            fontWeight: _weight(fontWeight),
          ),
        ),
      );
    }

    Widget productBadge(Map<String, dynamic> badge) {
      final settings = badge['settings'] is Map
          ? Map<String, dynamic>.from(badge['settings'] as Map)
          : <String, dynamic>{};
      final background = sxColor(
        sxText(settings['background_color'], sxText(badge['bg_color'], '#111827')),
        Colors.black,
      ).withOpacity(sxDouble(settings['background_opacity'], 1).clamp(0, 1));
      final foreground = sxColor(
        sxText(settings['text_color'], sxText(badge['text_color'], '#ffffff')),
        Colors.white,
      );
      final size = sxDouble(
        settings['font_size'],
        sxDouble(cardSettings['product_badge_font_size'], 9),
      );
      final radius = sxDouble(
        settings['border_radius'],
        sxDouble(cardSettings['product_badge_radius'], 5),
      );
      final decoration = sxText(settings['text_decoration']);
      final label = sxText(
        badge['custom_text'],
        sxText(badge['name'], sxText(badge['code'], 'شارة')),
      );
      final chip = badgeChip(
        text: label,
        background: background,
        foreground: foreground,
        fontSize: size,
        fontWeight: sxInt(settings['font_weight'], 800),
        radius: radius,
      );
      if (decoration == 'line_through') {
        return DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.lineThrough),
          child: chip,
        );
      }
      return chip;
    }

    final trendWidgets = trendBadges.map((trend) {
      final settings = trend['settings'] is Map
          ? Map<String, dynamic>.from(trend['settings'] as Map)
          : <String, dynamic>{};
      final hashtag = trend['hashtag'] is Map
          ? Map<String, dynamic>.from(trend['hashtag'] as Map)
          : <String, dynamic>{};
      final label = sxText(
        hashtag['display_name'],
        sxText(trend['text'], 'ترند'),
      );
      return badgeChip(
        text: label,
        background: sxColor(
          sxText(settings['trend_badge_background_color']),
          const Color(0xFF8B5CF6),
        ).withOpacity(sxDouble(settings['trend_badge_background_opacity'], 1).clamp(0, 1)),
        foreground: sxColor(
          sxText(settings['trend_badge_text_color']),
          Colors.white,
        ),
        fontSize: sxDouble(
          settings['trend_badge_font_size'],
          sxDouble(cardSettings['trend_badge_font_size'], 9),
        ),
        fontWeight: sxInt(settings['trend_badge_font_weight'], 800),
        radius: sxDouble(settings['trend_badge_radius'], 5),
      );
    }).toList();

    Widget discountBadge() {
      return badgeChip(
        text: 'خصم ' + discount.toString() + '%',
        background: sxColor(
          sxText(cardSettings['discount_badge_background_color']),
          const Color(0xFFDC2626),
        ),
        foreground: sxColor(
          sxText(cardSettings['discount_badge_text_color']),
          Colors.white,
        ),
        fontSize: sxDouble(cardSettings['discount_badge_font_size'], 9),
        fontWeight: sxInt(cardSettings['discount_badge_font_weight'], 900),
        radius: sxDouble(cardSettings['discount_badge_radius'], 5),
      );
    }

    Widget badgeRow(List<Widget> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: 5,
          runSpacing: 5,
          children: items,
        ),
      );
    }

    final beforeWidgets = <Widget>[
      ...trendWidgets,
      ...beforeName.map(productBadge),
      if (discount > 0) discountBadge(),
    ];
    final afterWidgets = afterName.map(productBadge).toList();
    final belowPriceWidgets = belowPrice.map(productBadge).toList();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          badgeRow(beforeWidgets),
          if (brand.isNotEmpty)
            Text(
              brand,
              style: const TextStyle(
                fontSize: 10,
                color: ClientTheme.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 3),
          Text(
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
          badgeRow(afterWidgets),
          if (sku.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                sku,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 8, color: Color(0xFF9CA3AF)),
              ),
            ),
          const SizedBox(height: 8),
          Row(
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
              const Spacer(),
              if (oldPrice.isNotEmpty)
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
          ),
          badgeRow(belowPriceWidgets),
          if (showRating)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
                      ' · ' + reviewCount.toString() + ' تقييم',
                      style: const TextStyle(fontSize: 9, color: ClientTheme.muted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
  
  );
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

class _ProductBottomBar extends StatelessWidget {
  final String price;
  final String currency;
  final VoidCallback onAdd;
  final VoidCallback onBuy;

  const _ProductBottomBar({
    required this.price,
    required this.currency,
    required this.onAdd,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: ClientTheme.border, width: .8),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('السعر', style: TextStyle(fontSize: 7.5, color: ClientTheme.muted)),
                  const SizedBox(height: 2),
                  Text(
                    price + ' ' + currency,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: OutlinedButton(
                onPressed: onAdd,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: Colors.black),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                ),
                child: const Text('أضف إلى الحقيبة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                ),
                child: const Text('اشترِ الآن', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
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

int sxIntListLength(dynamic value) => value is List ? value.length : 0;
