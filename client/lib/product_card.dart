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
    final product = widget.product;
    final old = sxDouble(product.oldPrice);
    final now = sxDouble(product.price);
    final discount = old > now && old > 0 ? ((1 - now / old) * 100).round() : 0;
    final ratio = sxProductImageRatio(product);
    final gallery = _gallery;
    final rating = product.rating;
    final hasRating = rating != null && rating > 0;

    final badges = product.badges.where((badge) {
      return _badgeSettings(badge)['visible'] != false;
    }).toList();

    int badgeLimit() => _cardNumber('product_badge_max', 8).round().clamp(1, 8).toInt();

    String canonicalPosition(String position) {
      const aliases = <String, String>{
        'before_name': 'before_name_new_row',
        'after_name': 'after_name_new_row',
        'after_price': 'after_price',
      };
      return aliases[position] ?? position;
    }

    List<Map<String, dynamic>> at(String position) {
      final actual = canonicalPosition(position);
      return badges
          .where((badge) => _badgePosition(badge) == actual)
          .take(badgeLimit())
          .toList();
    }

    Widget badgeWrap(
      List<Map<String, dynamic>> items, {
      Alignment alignment = Alignment.centerRight,
      EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    }) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: padding,
        child: Align(
          alignment: alignment,
          child: Wrap(
            spacing: 4,
            runSpacing: 3,
            children: items.map(_badgeChip).toList(),
          ),
        ),
      );
    }

    Widget badgeRow(String position) => badgeWrap(at(position));

    Widget sameRowBadgeText(
      String position, {
      required Widget main,
      required bool before,
    }) {
      final items = at(position);
      if (items.isEmpty) return main;
      final badgesWidget = Flexible(
        fit: FlexFit.loose,
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 4,
            runSpacing: 3,
            children: items.map(_badgeChip).toList(),
          ),
        ),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: before
            ? <Widget>[
                badgesWidget,
                const SizedBox(width: 4),
                Expanded(child: main),
              ]
            : <Widget>[
                Expanded(child: main),
                const SizedBox(width: 4),
                badgesWidget,
              ],
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

    final nameWidget = Container(
      color: nameBackground,
      padding: const EdgeInsets.fromLTRB(8, 1, 8, 0),
      child: Text(
        product.name,
        maxLines: _cardNumber('name_max_lines', 2).round().clamp(1, 3),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: _cardColor('name_color', const Color(0xFF111111)),
          fontSize: _cardNumber('name_font_size', 11),
          fontWeight: _fontWeight(_cardNumber('name_font_weight', 600).round()),
          height: 1.25,
        ),
      ),
    );

    final descriptionVisible =
        _cardBool('show_short_description', false) &&
        product.shortDescription.trim().isNotEmpty;
    final descriptionWidget = descriptionVisible
        ? Container(
            color: descBackground,
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 1),
            child: Text(
              product.shortDescription,
              maxLines: _cardNumber('short_description_max_lines', 1).round().clamp(1, 3),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _cardColor('short_description_color', const Color(0xFF6B7280)),
                fontSize: _cardNumber('short_description_font_size', 9),
                fontWeight: _fontWeight(_cardNumber('short_description_font_weight', 500).round()),
                height: 1.25,
              ),
            ),
          )
        : const SizedBox.shrink();

    final priceMain = Wrap(
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
    );

    final beforePrice = at('before_price_same_row');
    final afterPrice = at('after_price_same_row');
    Widget priceArea = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (beforePrice.isNotEmpty) ...[
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: beforePrice.map(_badgeChip).toList(),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(child: priceMain),
          if (afterPrice.isNotEmpty) ...[
            const SizedBox(width: 4),
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: afterPrice.map(_badgeChip).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: surface,
        child: InkWell(
          onTap: widget.onProductTap == null
              ? null
              : () => widget.onProductTap!(product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              badgeRow('first'),
              badgeRow('above_image'),
              _imageStack(
                ratio: ratio,
                masonry: widget.masonry,
                discount: discount,
                gallery: gallery,
              ),
              if (_cardBool('show_trend_badge', true) || _cardBool('show_trend_hashtag', true))
                _trendRibbon(),

              badgeRow('before_name_new_row'),
              if (_cardBool('show_name', true))
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 1, 8, 0),
                  child: sameRowBadgeText(
                    'before_name_same_row',
                    before: true,
                    main: nameWidget,
                  ),
                ),
              if (!_cardBool('show_name', true))
                badgeWrap(
                  at('before_name_same_row'),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                ),
              if (_cardBool('show_name', true))
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 1, 8, 0),
                  child: sameRowBadgeText(
                    'after_name_same_row',
                    before: false,
                    main: nameWidget,
                  ),
                ),
              badgeRow('after_name_new_row'),

              badgeRow('before_description'),
              if (descriptionVisible) descriptionWidget,
              badgeRow('after_description'),
              badgeRow('below_description'),

              badgeRow('before_price'),
              if (_cardBool('show_price', true)) priceArea,
              if (!_cardBool('show_price', true))
                badgeWrap(at('before_price_same_row')),
              badgeRow('after_price'),
              badgeRow('below_price'),

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
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _cardColor('size_color', const Color(0xFF6B7280)),
                      fontSize: _cardNumber('size_font_size', 9),
                      fontWeight: _fontWeight(_cardNumber('size_font_weight', 600).round()),
                    ),
                  ),
                ),

              badgeRow('after_details'),
              if (!hasRating && !_cardBool('show_size', false))
                const SizedBox(height: 5),
              badgeRow('last'),
            ],
          ),
        ),
      ),
    );
  }

}
