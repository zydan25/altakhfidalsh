import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

// Shared storefront product-card renderer. Keep this file focused on card layout
// so shein_ui.dart remains a page/screen composition layer.
String sxText(dynamic v, [String fallback = '']) => (v ?? fallback).toString();
int sxInt(dynamic v, [int fallback = 0]) => int.tryParse(sxText(v)) ?? fallback;
double sxDouble(dynamic v, [double fallback = 0]) => double.tryParse(sxText(v)) ?? fallback;
Color sxColor(dynamic value, Color fallback) {
  final raw = sxText(value);
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) return fallback;
  return Color(int.tryParse('FF' + raw.substring(1), radix: 16) ?? fallback.value);
}
double sxProductImageRatio(ProductModel product) {
  final direct = product.imageAspectRatio;
  if (direct != null && direct > 0) return direct.clamp(.56, 1.45).toDouble();
  final raw = product.cardAspectRatio ?? '';
  final parts = raw.split(':');
  if (parts.length == 2) {
    final width = double.tryParse(parts[0]);
    final height = double.tryParse(parts[1]);
    if (width != null && height != null && width > 0 && height > 0) {
      return (width / height).clamp(.56, 1.45).toDouble();
    }
  }
  return .75;
}

class _ProductCardImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  const _ProductCardImage({this.url, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    final value = api.url(url);
    if (value.isEmpty) {
      return Container(color: ClientTheme.soft, child: const Icon(Icons.image_outlined, color: Color(0xFF9AA0A6)));
    }
    return CachedNetworkImage(
      imageUrl: value,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => Container(color: ClientTheme.soft),
      errorWidget: (_, __, ___) => Container(
        color: ClientTheme.soft,
        child: const Icon(Icons.image_outlined, color: Color(0xFF9AA0A6)),
      ),
    );
  }
}

class SxProductGrid extends StatelessWidget {
  final List<ProductModel> products;
  final bool masonry;
  final Map<String, dynamic>? displaySettings;
  final ValueChanged<ProductModel>? onProductTap;

  const SxProductGrid({
    super.key,
    required this.products,
    this.masonry = true,
    this.displaySettings,
    this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(
          child: Text(
            'لا توجد منتجات مطابقة',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    if (masonry) {
      return _SxMasonryProductGrid(
        products: products,
        displaySettings: displaySettings,
        onProductTap: onProductTap,
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFFF6F6F6),
        padding: const EdgeInsets.fromLTRB(5, 5, 5, 8),
        child: GridView.builder(
        primary: false,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 5,
          mainAxisSpacing: 7,
          childAspectRatio: .69,
        ),
          itemBuilder: (_, i) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: SxProductCard(
              key: ValueKey<int>(products[i].id),
              product: products[i],
              displaySettings: displaySettings,
              onProductTap: onProductTap,
            ),
          ),
        ),
      ),
    );
  }
}

class _SxMasonryProductGrid extends StatelessWidget {
  final List<ProductModel> products;
  final Map<String, dynamic>? displaySettings;
  final ValueChanged<ProductModel>? onProductTap;

  const _SxMasonryProductGrid({
    required this.products,
    this.displaySettings,
    this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - 5) / 2;
        final columns = <List<ProductModel>>[[], []];
        final heights = <double>[0, 0];

        for (final product in products) {
          final ratio = sxProductImageRatio(product);
          final ribbonHeight =
              product.trendCard != null || product.hashtags.isNotEmpty ? 20 : 0;
          final estimatedHeight =
              columnWidth / ratio + 112 + ribbonHeight;
          final column = heights[0] <= heights[1] ? 0 : 1;
          columns[column].add(product);
          heights[column] += estimatedHeight + 7;
        }

        Widget buildColumn(List<ProductModel> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              SxProductCard(
                key: ValueKey<int>(rows[i].id),
                product: rows[i],
                masonry: true,
                displaySettings: displaySettings,
                onProductTap: onProductTap,
              ),
              if (i != rows.length - 1) const SizedBox(height: 7),
            ],
          ],
        );

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            color: const Color(0xFFF6F6F6),
            padding: const EdgeInsets.fromLTRB(5, 5, 5, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Expanded(child: buildColumn(columns[0])),
              const SizedBox(width: 5),
                Expanded(child: buildColumn(columns[1])),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SxProductCard extends StatefulWidget {
  final ProductModel product;
  final bool masonry;
  final Map<String, dynamic>? displaySettings;
  final ValueChanged<ProductModel>? onProductTap;

  const SxProductCard({
    super.key,
    required this.product,
    this.masonry = false,
    this.displaySettings,
    this.onProductTap,
  });

  @override
  State<SxProductCard> createState() => _SxProductCardState();
}

class _SxProductCardState extends State<SxProductCard> {
  int page = 0;
  double _dragDistance = 0;
  int _swipeDirection = 1;
  late List<String> _gallery;
  bool _galleryLoading = false;
  bool _galleryLoaded = false;

  @override
  void didUpdateWidget(covariant SxProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      page = 0;
      _gallery = _uniqueImages(widget.product.images, widget.product.image);
      _galleryLoaded = _gallery.length > 1;
      _galleryLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _gallery = _uniqueImages(widget.product.images, widget.product.image);
    _galleryLoaded = _gallery.length > 1;
  }

  List<String> _uniqueImages(Iterable<String> images, String? primary) {
    final merged = <String>[
      ...images.where((x) => x.isNotEmpty),
      if (primary != null && primary.isNotEmpty) primary,
    ];
    return merged.toSet().toList();
  }

  Future<void> _loadFullGallery() async {
    if (_galleryLoaded || _galleryLoading || !mounted) return;
    _galleryLoading = true;
    try {
      final data = await api.product(
        widget.product.id,
        currencyId: state.currencyId,
      );
      final item = data['item'] is Map
          ? Map<String, dynamic>.from(data['item'])
          : const <String, dynamic>{};
      final media = (item['media'] as List?)
              ?.whereType<Map>()
              .map((e) => sxText(e['url']))
              .where((x) => x.isNotEmpty)
              .toList() ??
          <String>[];
      final next = _uniqueImages(media, widget.product.image);
      if (!mounted) return;
      setState(() {
        if (next.isNotEmpty) _gallery = next;
        _galleryLoaded = true;
        _galleryLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _galleryLoaded = true;
          _galleryLoading = false;
        });
      }
    }
  }

  Future<void> _handleImageSwipeEnd(
    DragEndDetails details,
    int imageCount,
  ) async {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDistance;
    _dragDistance = 0;

    if (imageCount <= 1) {
      await _loadFullGallery();
      if (!mounted || _gallery.length <= 1) return;
      imageCount = _gallery.length;
    }

    if (distance.abs() < 18 && velocity.abs() < 100) return;

    final direction = velocity.abs() >= 100
        ? (velocity < 0 ? 1 : -1)
        : (distance < 0 ? 1 : -1);

    var nextPage = page + direction;
    if (nextPage < 0) {
      nextPage = imageCount - 1;
    } else if (nextPage >= imageCount) {
      nextPage = 0;
    }

    if (nextPage != page && mounted) {
      setState(() {
        _swipeDirection = direction;
        page = nextPage;
      });
    }
  }

  Map<String, dynamic> get _cardSettings =>
      widget.product.cardSettings ?? widget.displaySettings ?? const {};

  dynamic _cardValue(String key, dynamic fallback) {
    final value = _cardSettings[key];
    return value ?? fallback;
  }

  bool _cardBool(String key, bool fallback) {
    final value = _cardValue(key, fallback);
    return value is bool ? value : (value.toString().toLowerCase() == 'true');
  }

  double _cardNumber(String key, double fallback) {
    final value = _cardValue(key, fallback);
    final parsed = value is num ? value.toDouble() : double.tryParse(value.toString());
    return (parsed == null || !parsed.isFinite) ? fallback : parsed;
  }

  String _cardText(String key, String fallback) {
    final value = _cardValue(key, fallback).toString().trim();
    return value.isEmpty ? fallback : value;
  }

  Color _cardColor(String key, Color fallback) =>
      sxColor(_cardText(key, ''), fallback);

  double _cardOpacity(String key, double fallback) =>
      _cardNumber(key, fallback).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> _badgeSettings(Map<String, dynamic> badge) =>
      badge['settings'] is Map
          ? Map<String, dynamic>.from(badge['settings'] as Map)
          : const <String, dynamic>{};

  String _badgePosition(Map<String, dynamic> badge) {
    final settings = _badgeSettings(badge);
    final position = sxText(
      settings['position'],
      _cardText('product_badge_position', 'top_right'),
    );
    return position.isEmpty ? 'top_right' : position;
  }

  Widget _cornerPositioned(
    String position,
    Widget child, {
    double offset = 6,
    double? bottomOffset,
  }) {
    final bottom = bottomOffset ?? offset;
    switch (position) {
      case 'top_left':
        return Positioned(top: offset, left: offset, child: child);
      case 'top_right':
        return Positioned(top: offset, right: offset, child: child);
      case 'bottom_left':
        return Positioned(bottom: bottom, left: offset, child: child);
      default:
        return Positioned(bottom: bottom, right: offset, child: child);
    }
  }

  Widget _cardMetaChip(Map<String, dynamic> meta) {
    final text = sxText(meta['label']);
    if (text.isEmpty || !_cardBool('meta_show', true)) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _cardNumber('meta_padding_horizontal', 4),
        vertical: _cardNumber('meta_padding_vertical', 2),
      ),
      decoration: BoxDecoration(
        color: _cardColor('meta_background_color', const Color(0xFFF4F4F4)),
        borderRadius: BorderRadius.circular(_cardNumber('meta_radius', 3)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _cardColor('meta_text_color', const Color(0xFF111111)),
          fontSize: _cardNumber('meta_font_size', 7.5),
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  Widget _trendRibbon() {
    final trend = widget.product.trendCard;
    final trendSettings = trend?['settings'] is Map
        ? Map<String, dynamic>.from(trend!['settings'] as Map)
        : const <String, dynamic>{};
    final trendHashtag = trend?['hashtag'] is Map
        ? Map<String, dynamic>.from(trend!['hashtag'] as Map)
        : null;
    final hashtag = trendHashtag ??
        (widget.product.hashtags.isNotEmpty
            ? widget.product.hashtags.first
            : null);
    final showTrend =
        trend != null && _cardBool('show_trend_badge', true) &&
        trendSettings['show_trend_badge'] != false;
    final showHashtag = hashtag != null &&
        _cardBool('show_trend_hashtag', true) &&
        trendSettings['show_trend_hashtag'] != false;

    if (!showTrend && !showHashtag) return const SizedBox.shrink();

    final trendText = sxText(
      trendSettings['trend_badge_text'],
      _cardText('trend_badge_text', 'Trends'),
    );
    final hashtagText = sxText(
      hashtag?['display_name'],
      hashtag == null ? '' : '#' + sxText(hashtag['name']),
    );

    final trendBg = sxColor(
      sxText(
        trendSettings['trend_badge_background_color'],
        _cardText('trend_badge_background_color', '#8b5cf6'),
      ),
      const Color(0xFF8B5CF6),
    );
    final trendFg = sxColor(
      sxText(
        trendSettings['trend_badge_text_color'],
        _cardText('trend_badge_text_color', '#ffffff'),
      ),
      Colors.white,
    );
    final hashtagFg = sxColor(
      sxText(
        trendSettings['trend_hashtag_text_color'],
        _cardText('trend_hashtag_text_color', '#7c3aed'),
      ),
      const Color(0xFF7C3AED),
    );
    final hashtagBg = sxColor(
      sxText(
        trendSettings['trend_hashtag_background_color'],
        _cardText('trend_hashtag_background_color', '#f0e6ff'),
      ),
      const Color(0xFFF0E6FF),
    );
    final useHashtagBg = trendSettings['trend_hashtag_use_background']
            is bool
        ? trendSettings['trend_hashtag_use_background'] as bool
        : _cardBool('trend_hashtag_use_background', true);
    final showArrow = trendSettings['trend_show_arrow'] is bool
        ? trendSettings['trend_show_arrow'] as bool
        : _cardBool('trend_show_arrow', true);

    Widget hashtagChip = Flexible(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: useHashtagBg ? hashtagBg : Colors.transparent,
          borderRadius: BorderRadius.circular(
            _cardNumber('trend_badge_radius', 3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showArrow)
              Text(
                _cardText('trend_arrow_text', '‹'),
                style: TextStyle(
                  color: sxColor(
                    sxText(
                      trendSettings['trend_arrow_color'],
                      _cardText('trend_arrow_color', '#7c3aed'),
                    ),
                    const Color(0xFF7C3AED),
                  ),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            Flexible(
              child: Text(
                hashtagText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: hashtagFg,
                  fontSize: _cardNumber('trend_hashtag_font_size', 8),
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget trendChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: trendBg,
        borderRadius: BorderRadius.circular(
          _cardNumber('trend_badge_radius', 3),
        ),
      ),
      child: Text(
        trendText,
        style: TextStyle(
          color: trendFg,
          fontSize: _cardNumber('trend_badge_font_size', 8),
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 1),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showHashtag) hashtagChip,
            if (showHashtag && showTrend)
              SizedBox(width: _cardNumber('trend_ribbon_gap', 3)),
            if (showTrend) trendChip,
          ],
        ),
      ),
    );
  }

  Widget _imageStack({
    required double ratio,
    required bool masonry,
    required int discount,
    required List<String> gallery,
  }) {
    final image = gallery.isEmpty
        ? Container(
            color: ClientTheme.soft,
            child: const Icon(Icons.image_outlined),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _dragDistance = 0;
              if (_gallery.length <= 1) {
                unawaited(_loadFullGallery());
              }
            },
            onHorizontalDragUpdate: (details) {
              _dragDistance += details.delta.dx;
            },
            onHorizontalDragEnd: (details) {
              unawaited(
                _handleImageSwipeEnd(details, _gallery.length),
              );
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final begin = Offset(_swipeDirection > 0 ? 1.0 : -1.0, 0);
                final slide = Tween<Offset>(begin: begin, end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeOutCubic))
                    .animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(
                  widget.product.id.toString() + '-' + page.toString(),
                ),
                child: _ProductCardImage(
                  url: gallery[page],
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );

    final imageContainer = ClipRRect(
      borderRadius: BorderRadius.circular(
        widget.masonry ? 8 : 10,
      ),
      child: image,
    );

    final product = widget.product;
    final meta = product.cardMeta;
    final metaPosition = _cardText('meta_position', 'top_right');
    final brandPosition = _cardText('brand_position', 'top_left');
    final badgePosition = _cardText('product_badge_position', 'top_right');
    final colorPosition = _cardText('colors_position', 'bottom_right');
    final badgeTopOffset =
        badgePosition == 'top_right' && meta != null && _cardBool('meta_show', true)
            ? 31.0
            : 6.0;
    final brandText = sxText(product.brandName);

    Widget colorSwatches() {
      if (!_cardBool('colors_show', true) || product.colors.isEmpty) {
        return const SizedBox.shrink();
      }
      final swatchSize = _cardNumber('colors_size', 13);
      final containerSize =
          _cardNumber('colors_container_size', 16).clamp(swatchSize, 28).toDouble();
      final gap = _cardNumber('colors_gap', 2);
      final max = _cardNumber('colors_max', 6).round().clamp(1, 8).toInt();
      final items = product.colors.take(max).map((color) {
        final hex = sxText(color['hex_code']);
        final swatchUrl = sxText(color['swatch_url']);
        return Container(
          width: containerSize,
          height: containerSize,
          padding: EdgeInsets.all(
            ((containerSize - swatchSize) / 2).clamp(0, 8).toDouble(),
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.94),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: _cardNumber('colors_border_width', 1),
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 2,
                offset: Offset(0, 1),
                color: Colors.black26,
              ),
            ],
          ),
          child: swatchUrl.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    api.url(swatchUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: sxColor(hex, const Color(0xFFE5E7EB)),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: sxColor(hex, const Color(0xFFE5E7EB)),
                    shape: BoxShape.circle,
                  ),
                ),
        );
      }).toList();

      final direction = _cardText('colors_direction', 'horizontal');
      final child = direction == 'vertical'
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.from(
                items.map((item) => Padding(
                  padding: EdgeInsets.only(bottom: gap),
                  child: item,
                )),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.from(
                items.map((item) => Padding(
                  padding: EdgeInsets.only(left: gap),
                  child: item,
                )),
              ),
            );
      return child;
    }

    final body = Stack(
      fit: StackFit.passthrough,
      children: [
        if (masonry)
          AspectRatio(aspectRatio: ratio, child: imageContainer)
        else
          Positioned.fill(child: imageContainer),

        if (_cardBool('show_brand', true) && brandText.isNotEmpty)
          _cornerPositioned(
            brandPosition,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: _cardColor(
                  'brand_background_color',
                  const Color(0xFF111827),
                ).withOpacity(.90),
                borderRadius: BorderRadius.circular(
                  _cardNumber('brand_radius', 4),
                ),
              ),
              child: Text(
                brandText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _cardColor(
                    'brand_text_color',
                    Colors.white,
                  ),
                  fontSize: _cardNumber('brand_font_size', 8),
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),

        if (meta != null && sxText(meta['label']).isNotEmpty &&
            _cardBool('meta_show', true))
          _cornerPositioned(
            metaPosition,
            _cardMetaChip(meta),
          ),

        for (final position in const ['top_left', 'top_right', 'bottom_left', 'bottom_right'])
          if (product.badges.any((badge) => _badgePosition(badge) == position))
            _cornerPositioned(
              position,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: product.badges
                    .where((badge) => _badgePosition(badge) == position)
                    .take(_cardNumber('product_badge_max', 4).round().clamp(1, 8).toInt())
                    .map(_badgeChip)
                    .toList(),
              ),
              offset: 6,
            ),

        if (_cardBool('colors_show', true) && product.colors.isNotEmpty)
          _cornerPositioned(
            colorPosition,
            colorSwatches(),
            bottomOffset: discount > 0 ? 32 : 6,
          ),

        if (_cardBool('show_product_badges', true) &&
            product.badges.any((badge) => _badgePosition(badge) == 'right_of_image'))
          Positioned(
            right: 6,
            top: 50,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: product.badges
                  .where((badge) => _badgePosition(badge) == 'right_of_image')
                  .take(_cardNumber('product_badge_max', 4).round().clamp(1, 8).toInt())
                  .map(_badgeChip)
                  .toList(),
            ),
          ),

        if (gallery.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: discount > 0 ? 29 : 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                gallery.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: i == page ? 12 : 5,
                  height: 3,
                  decoration: BoxDecoration(
                    color: i == page ? Colors.white : Colors.white70,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),

        if (_galleryLoading)
          const Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        if (discount > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black.withOpacity(.74),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              child: Row(
                children: [
                  const Text(
                    '🔥 توفير',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    discount.toString() + '%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),

        Positioned(
          left: 7,
          bottom: discount > 0 ? 27 : 7,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.93),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shopping_bag_outlined, size: 17),
          ),
        ),
      ],
    );
    if (!masonry) {
      return Expanded(child: body);
    }
    return body;
  }

  Widget _badgeChip(Map<String, dynamic> badge) {
    final settings = _badgeSettings(badge);
    if (settings['visible'] == false) return const SizedBox.shrink();

    final tab = sxText(badge['storefront_tab']);
    final fallback = tab == 'new'
        ? const Color(0xFF16A34A)
        : tab == 'offers'
            ? const Color(0xFFDC2626)
            : const Color(0xFF111827);
    final bg = sxColor(
      sxText(settings['background_color'], sxText(badge['bg_color'])),
      fallback,
    ).withOpacity(_cardNumberFromMap(settings, 'background_opacity', 1));
    final fg = sxColor(
      sxText(settings['text_color'], sxText(badge['text_color'])),
      Colors.white,
    );
    final text = sxText(
      badge['custom_text'],
      sxText(badge['name'], sxText(badge['code'])),
    );
    final decoration = sxText(settings['text_decoration'], 'none');
    final fontSize = _numberFromMap(settings, 'font_size', _cardNumber('product_badge_font_size', 8));
    final weight = _intFromMap(settings, 'font_weight', 900);
    final radius = _numberFromMap(settings, 'border_radius', _cardNumber('product_badge_radius', 3));
    final horizontal = _numberFromMap(settings, 'padding_horizontal', 5);
    final vertical = _numberFromMap(settings, 'padding_vertical', 2);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: settings['border_width'] != null
            ? Border.all(
                width: _numberFromMap(settings, 'border_width', 0),
                color: sxColor(sxText(settings['border_color'], '#ffffff'), Colors.white).withOpacity(.72),
              )
            : null,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: _fontWeight(weight),
          fontStyle: FontStyle.normal,
          decoration: decoration == 'line_through'
              ? TextDecoration.lineThrough
              : TextDecoration.none,
          decorationColor: fg,
          height: 1,
        ),
      ),
    );
  }

  double _numberFromMap(Map<String, dynamic> map, String key, double fallback) {
    final raw = map[key];
    final parsed = raw is num ? raw.toDouble() : double.tryParse(sxText(raw));
    return parsed == null || !parsed.isFinite ? fallback : parsed;
  }

  double _cardNumberFromMap(Map<String, dynamic> map, String key, double fallback) =>
      _numberFromMap(map, key, fallback).clamp(0.0, 1.0).toDouble();

  int _intFromMap(Map<String, dynamic> map, String key, int fallback) {
    final raw = map[key];
    final parsed = raw is num ? raw.toInt() : int.tryParse(sxText(raw));
    return parsed ?? fallback;
  }

  FontWeight _fontWeight(int weight) {
    if (weight >= 900) return FontWeight.w900;
    if (weight >= 800) return FontWeight.w800;
    if (weight >= 700) return FontWeight.w700;
    if (weight >= 600) return FontWeight.w600;
    if (weight >= 500) return FontWeight.w500;
    if (weight >= 400) return FontWeight.w400;
    return FontWeight.w300;
  }
  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final old = sxDouble(product.oldPrice);
    final now = sxDouble(product.price);
    final discount = old > now && old > 0 ? ((1 - now / old) * 100).round() : 0;
    final ratio = sxProductImageRatio(product);
    final gallery = _gallery;
    final rating = product.rating;
    final hasRating = rating != null && rating > 0;
    final badges = product.badges.where((badge) {
      final settings = _badgeSettings(badge);
      return settings['visible'] != false;
    }).toList();

    List<Map<String, dynamic>> at(String position) => badges
        .where((badge) => _badgePosition(badge) == position)
        .take(_cardNumber('product_badge_max', 4).round().clamp(1, 8).toInt())
        .toList();

    Widget inlineBadges(String position) {
      final items = at(position);
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 3),
        child: Align(
          alignment: position == 'after_name'
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Wrap(
            spacing: 4,
            runSpacing: 3,
            children: items.map(_badgeChip).toList(),
          ),
        ),
      );
    }

    final surface = _cardColor('card_background_color', Colors.white)
        .withOpacity(_cardOpacity('card_background_opacity', 1));
    final nameBackground = _cardColor('name_background_color', Colors.white)
        .withOpacity(_cardOpacity('name_background_opacity', 1));
    final priceBackground = _cardColor('price_background_color', Colors.white)
        .withOpacity(_cardOpacity('price_background_opacity', 1));
    final compareBackground = _cardColor('compare_price_background_color', Colors.white)
        .withOpacity(_cardOpacity('compare_price_background_opacity', 1));
    final currencyBackground = _cardColor('currency_background_color', Colors.white)
        .withOpacity(_cardOpacity('currency_background_opacity', 1));
    final descBackground = _cardColor(
      'short_description_background_color',
      Colors.transparent,
    ).withOpacity(_cardOpacity('short_description_background_opacity', 0));

    return Container(
      color: surface,
      child: InkWell(
        onTap: widget.onProductTap == null
            ? null
            : () => widget.onProductTap!(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (at('above_image').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 4, 5, 1),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: at('above_image').map(_badgeChip).toList(),
                ),
              ),
            _imageStack(
              ratio: ratio,
              masonry: widget.masonry,
              discount: discount,
              gallery: gallery,
            ),
            if (_cardBool('show_trend_badge', true) || _cardBool('show_trend_hashtag', true))
              _trendRibbon(),
            inlineBadges('before_name'),
            if (_cardBool('show_name', true))
              Container(
                color: nameBackground,
                padding: const EdgeInsets.fromLTRB(8, 1, 8, 0),
                child: Text(
                  product.name,
                  maxLines: _cardNumber('name_max_lines', 2).round().clamp(1, 3),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _cardColor('name_color', const Color(0xFF111111)),
                    fontSize: _cardNumber('name_font_size', 11),
                    fontWeight: _fontWeight(_cardNumber('name_font_weight', 600).round()),
                    height: 1.25,
                  ),
                ),
              ),
            inlineBadges('after_name'),
            if (_cardBool('show_short_description', false) &&
                product.shortDescription.trim().isNotEmpty)
              Container(
                color: descBackground,
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 1),
                child: Text(
                  product.shortDescription,
                  maxLines: _cardNumber('short_description_max_lines', 1).round().clamp(1, 3),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _cardColor('short_description_color', const Color(0xFF6B7280)),
                    fontSize: _cardNumber('short_description_font_size', 9),
                    fontWeight: _fontWeight(_cardNumber('short_description_font_weight', 500).round()),
                    height: 1.25,
                  ),
                ),
              ),
            if (_cardBool('show_price', true))
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 5,
                  runSpacing: 2,
                  children: [
                    if (discount > 0)
                      Text(
                        '-' + discount.toString() + '%',
                        style: TextStyle(
                          color: ClientTheme.promo,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    Container(
                      color: priceBackground,
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      child: Text(
                        product.price,
                        style: TextStyle(
                          color: _cardColor('price_color', const Color(0xFF111111)),
                          fontSize: _cardNumber('price_font_size', 14),
                          fontWeight: _fontWeight(_cardNumber('price_font_weight', 900).round()),
                        ),
                      ),
                    ),
                    if (_cardBool('show_currency', true))
                      Container(
                        color: currencyBackground,
                        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                        child: Text(
                          state.currencySymbol,
                          style: TextStyle(
                            color: _cardColor('currency_color', const Color(0xFF111111)),
                            fontSize: _cardNumber('currency_font_size', 10),
                            fontWeight: _fontWeight(_cardNumber('currency_font_weight', 800).round()),
                          ),
                        ),
                      ),
                    if (_cardBool('show_compare_price', true) &&
                        product.oldPrice != null &&
                        product.oldPrice!.isNotEmpty)
                      Container(
                        color: compareBackground,
                        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                        child: Text(
                          product.oldPrice!,
                          style: TextStyle(
                            color: _cardColor('compare_price_color', const Color(0xFF8B9198)),
                            fontSize: _cardNumber('compare_price_font_size', 10),
                            fontWeight: _fontWeight(_cardNumber('compare_price_font_weight', 500).round()),
                            decoration: _cardText('compare_price_text_decoration', 'line_through') == 'line_through'
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            inlineBadges('below_price'),
            if (hasRating)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 12.5, color: Color(0xFFFFB400)),
                    Text(
                      ' ' + rating!.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
                    ),
                    if (product.reviewCount > 0)
                      Text(
                        ' (' + product.reviewCount.toString() + ')',
                        style: const TextStyle(fontSize: 8, color: ClientTheme.muted),
                      ),
                  ],
                ),
              ),
            if (_cardBool('show_size', false) &&
                product.cardMeta != null &&
                sxText(product.cardMeta!['label']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 1, 8, 5),
                child: Text(
                  sxText(product.cardMeta!['label']),
                  style: TextStyle(
                    color: _cardColor('size_color', const Color(0xFF6B7280)),
                    fontSize: _cardNumber('size_font_size', 9),
                    fontWeight: _fontWeight(_cardNumber('size_font_weight', 600).round()),
                  ),
                ),
              ),
            if (!hasRating && !_cardBool('show_size', false))
              const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}
