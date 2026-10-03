import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'app_state.dart';
import 'models.dart';
import 'product_card.dart';
import 'theme.dart';

class SxProductScreen extends StatefulWidget {
  final int id;
  const SxProductScreen({super.key, required this.id});

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
    final categoryId = categories.isNotEmpty ? sxInt(categories.first['id']) : null;
    setState(() => loadingRelated = true);
    try {
      final rows = await api.feed(
        category: categoryId != null && categoryId > 0 ? categoryId : null,
        currencyId: state.currencyId,
        sort: 'popular',
      );
      if (!mounted) return;
      final seen = <int>{widget.id};
      setState(() {
        related = rows.where((product) => seen.add(product.id)).take(10).toList();
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

  Future<void> _addToCart() async {
    final variant = _variantId();
    if (variant == null || variant <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر خيارات المنتج أولًا')),
      );
      return;
    }
    try {
      await api.addCart(variant);
      final cart = await api.cart(currencyId: state.currencyId);
      _CartBadge.value.value = sxIntListLength(cart['item']?['items']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة المنتج إلى الحقيبة')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(error))),
        );
      }
    }
  }

  Future<void> _buyNow() async {
    await _addToCart();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SxCartScreen()),
    );
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

    return Scaffold(
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
    );
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
                  itemCount: data.length,
                  onPageChanged: changed,
                  itemBuilder: (_, index) => _DetailNetworkImage(
                    url: sxText(data[index]['url']),
                  ),
                ),
                if (data.length > 1)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _DetailCounter(
                      text: page.toString() + '/' + data.length.toString(),
                    ),
                  ),
                if (data.length > 1)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Row(
                      children: List.generate(
                        data.length.clamp(1, 8),
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: index == page ? 18 : 6,
                          height: 3,
                          margin: const EdgeInsets.only(right: 3),
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
  });

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badges.isNotEmpty)
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: badges.take(6).map((badge) {
                  final settings = badge['settings'] is Map
                      ? Map<String, dynamic>.from(badge['settings'] as Map)
                      : <String, dynamic>{};
                  final tab = sxText(badge['storefront_tab']);
                  final fallback = tab == 'new'
                      ? const Color(0xFF16A34A)
                      : tab == 'offers'
                          ? const Color(0xFFDC2626)
                          : Colors.black;
                  final bg = sxColor(
                    sxText(settings['background_color'], sxText(badge['bg_color'])),
                    fallback,
                  ).withOpacity(
                    sxDouble(settings['background_opacity'], 1).clamp(0, 1),
                  );
                  final fg = sxColor(
                    sxText(settings['text_color'], sxText(badge['text_color'])),
                    Colors.white,
                  );
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(
                        sxDouble(settings['border_radius'], 5),
                      ),
                    ),
                    child: Text(
                      sxText(
                        badge['custom_text'],
                        sxText(badge['name'], sxText(badge['code'])),
                      ),
                      style: TextStyle(
                        color: fg,
                        fontSize: sxDouble(settings['font_size'], 9),
                        fontWeight: _weight(sxInt(settings['font_weight'], 800)),
                        decoration: sxText(settings['text_decoration']) == 'line_through'
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (badges.isNotEmpty) const SizedBox(height: 7),
            if (brand.isNotEmpty)
              Text(
                brand,
                style: const TextStyle(
                  fontSize: 9.5,
                  color: ClientTheme.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w900),
            ),
            if (sku.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  sku,
                  style: const TextStyle(fontSize: 8, color: Color(0xFF9CA3AF)),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1),
                ),
                const SizedBox(width: 5),
                Text(
                  currency,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                ),
                if (discount > 0) ...[
                  const SizedBox(width: 8),
                  _Pill(text: '-' + discount.toString() + '%', background: const Color(0xFFFFEEF2), foreground: ClientTheme.promo),
                ],
                const Spacer(),
                if (oldPrice.isNotEmpty)
                  Text(
                    oldPrice + ' ' + currency,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9CA3AF),
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
            if (showRating && average > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB400)),
                    const SizedBox(width: 2),
                    Text(
                      average.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                    if (showReviewCount && reviewCount > 0)
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
  const _ReviewSection({
    required this.average,
    required this.count,
    required this.reviews,
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
