// CI validation: client builds must pass analyze, tests, APK and web builds.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

String sxText(dynamic v, [String fallback = '']) => (v ?? fallback).toString();
int sxInt(dynamic v, [int fallback = 0]) => int.tryParse(sxText(v)) ?? fallback;
double sxDouble(dynamic v, [double fallback = 0]) => double.tryParse(sxText(v)) ?? fallback;

Color sxColor(dynamic value, Color fallback) {
  final raw = sxText(value);
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) return fallback;
  return Color(int.tryParse('FF' + raw.substring(1), radix: 16) ?? fallback.value);
}

List<Map<String, dynamic>> sxMaps(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
String sxImage(dynamic value) => api.url(sxText(value));

class SxAppShell extends StatefulWidget {
  const SxAppShell({super.key});
  @override State<SxAppShell> createState() => _SxAppShellState();
}

class _SxAppShellState extends State<SxAppShell> {
  int index = 0;
  final GlobalKey<_SxHomeScreenState> _homeKey = GlobalKey<_SxHomeScreenState>();
  late final List<Widget> pages;

  @override void initState() {
    super.initState();
    pages = [
      SxHomeScreen(key: _homeKey),
      const SxCategoriesScreen(),
      const SxTrendsScreen(),
      const SxCartScreen(),
      const SxAccountScreen(),
    ];
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }
  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SxBottomBar(
        index: index,
        onChanged: (v) {
          setState(() => index = v);
          if (v == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _homeKey.currentState?.refreshAndScrollTop();
            });
          }
        },
      ),
    ),
  );
}

class SxBottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const SxBottomBar({super.key, required this.index, required this.onChanged});
  @override Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: ClientTheme.border, width: .7)),
      ),
      child: Row(children: [
        _item(0, Icons.storefront_outlined, Icons.storefront, 'متجر'),
        _item(1, Icons.grid_view_outlined, Icons.grid_view, 'الفئات'),
        _item(2, Icons.trending_up_outlined, Icons.trending_up, 'ترندات'),
        _item(3, Icons.shopping_bag_outlined, Icons.shopping_bag, 'حقيبة التسوق'),
        _item(4, Icons.person_outline, Icons.person, 'أنا'),
      ]),
    ),
  );
  Widget _item(int i, IconData off, IconData on, String label) => Expanded(
    child: InkWell(
      onTap: () => onChanged(i),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(i == index ? on : off, size: 23, color: i == index ? Colors.black : const Color(0xFF7D8792)),
          if (i == 3) ValueListenableBuilder<int>(
            valueListenable: _CartBadge.value,
            builder: (_, n, __) => n == 0 ? const SizedBox.shrink() : Positioned(
              right: -7, top: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: ClientTheme.promo, borderRadius: BorderRadius.circular(20)),
                child: Text(n > 9 ? '9+' : n.toString(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: i == index ? FontWeight.w900 : FontWeight.w600, color: i == index ? Colors.black : const Color(0xFF71808E))),
      ]),
    ),
  );
}

class _CartBadge {
  static final ValueNotifier<int> value = ValueNotifier<int>(0);
}

class SxAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool back;
  final VoidCallback? onSearch;
  const SxAppBar({super.key, this.title, this.back = false, this.onSearch});
  @override Size get preferredSize => const Size.fromHeight(58);
  @override Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leading: back ? IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_ios, size: 18)) : null,
    titleSpacing: 8,
    title: title == null ? SxSearchBar(onTap: onSearch) : Text(title!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    actions: [if (title != null && onSearch != null) IconButton(onPressed: onSearch, icon: const Icon(Icons.search))],
  );
}

class SxShellPage extends StatelessWidget {
  final Widget child;
  final String? title;
  final bool back;
  final VoidCallback? onSearch;
  const SxShellPage({super.key, required this.child, this.title, this.back = false, this.onSearch});
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: SxAppBar(title: title, back: back, onSearch: onSearch),
    body: child,
  );
}

class SxSearchBar extends StatelessWidget {
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final bool autofocus;
  final Color borderColor;
  final Color backgroundColor;
  final Color iconColor;
  final Color iconBackgroundColor;

  const SxSearchBar({
    super.key,
    this.onTap,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hint = 'ابحث عن المنتجات',
    this.autofocus = false,
    this.borderColor = const Color(0xFFD5D5D5),
    this.backgroundColor = Colors.white,
    this.iconColor = Colors.black,
    this.iconBackgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 43,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SearchBarPainter(
                  backgroundColor: backgroundColor,
                  borderColor: borderColor,
                  iconBackgroundColor: iconBackgroundColor,
                ),
              ),
            ),
            Positioned.fill(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                readOnly: onTap != null && controller == null,
                onTap: onTap,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.only(
                    left: 48,
                    right: 10,
                  ),
                ).copyWith(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: 3,
              width: 36,
              height: 37,
              child: Center(
                child: Icon(
                  Icons.search,
                  size: 21,
                  color: iconColor,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SearchBarPainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconBackgroundColor;

  const _SearchBarPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconBackgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(7),
    );
    final iconRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4, 3, 36, 37),
      const Radius.circular(4),
    );

    // Paint the search field on its own layer, then physically clear the
    // icon area when idle. This makes that area truly transparent instead
    // of merely painting a transparent-colored rectangle over white.
    canvas.saveLayer(Offset.zero & size, Paint());

    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.fill
        ..color = backgroundColor,
    );

    if (iconBackgroundColor == Colors.transparent) {
      canvas.drawRRect(
        iconRect,
        Paint()
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.clear,
      );
    } else {
      canvas.drawRRect(
        iconRect,
        Paint()
          ..style = PaintingStyle.fill
          ..color = iconBackgroundColor,
      );
    }

    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = borderColor,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SearchBarPainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.iconBackgroundColor != iconBackgroundColor;
}


class SxSectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const SxSectionTitle({super.key, required this.title, this.onMore});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 17, 12, 10),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
      if (onMore != null) TextButton(onPressed: onMore, child: const Text('المزيد', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
    ]),
  );
}

class SxPill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const SxPill({super.key, required this.text, this.background = ClientTheme.soft, this.foreground = Colors.black});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(color: foreground, fontSize: 9, fontWeight: FontWeight.w900)),
  );
}

class SxImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  const SxImage({super.key, this.url, this.fit = BoxFit.cover, this.width, this.height});
  @override Widget build(BuildContext context) {
    final value = sxImage(url);
    if (value.isEmpty) return Container(width: width, height: height, color: ClientTheme.soft, child: const Icon(Icons.image_outlined, color: Color(0xFF9AA0A6)));
    return CachedNetworkImage(
      imageUrl: value,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => Container(
        width: width,
        height: height,
        color: ClientTheme.soft,
      ),
      errorWidget: (_, __, ___) => Container(
        width: width,
        height: height,
        color: ClientTheme.soft,
        child: const Icon(
          Icons.image_outlined,
          color: Color(0xFF9AA0A6),
        ),
      ),
    );
  }
}

class SxCircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dot;
  final Color iconColor;
  final Color backgroundColor;

  const SxCircleIcon({
    super.key,
    required this.icon,
    this.onTap,
    this.dot = false,
    this.iconColor = Colors.black,
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Stack(children: [
        Center(child: Icon(icon, size: 20, color: iconColor)),
        if (dot)
          Positioned(
            right: 5,
            top: 6,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: ClientTheme.promo,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ]),
    ),
  );
}

class SxHomeScreen extends StatefulWidget {
  const SxHomeScreen({super.key});
  @override State<SxHomeScreen> createState() => _SxHomeScreenState();
}

class _SxHomeScreenState extends State<SxHomeScreen> {
  Map<String, dynamic> home = {};
  List<ProductModel> products = [];
  List<ProductModel> _allStoreProducts = [];
  List<CategoryModel> roots = [];
  List<CategoryModel> allCategories = [];
  List<Map<String, dynamic>> looks = [];
  int selected = -1;
  int discoveryTab = 2;
  bool loading = true;
  int _loadSerial = 0;
  int _activeBannerIndex = 0;
  double _pullExtent = 0;
  bool _headerIsSolid = false;
  final GlobalKey _homeHeroKey = GlobalKey();
  late final ScrollController _homeScrollController;
  static const String _bannerColorCacheKey =
      'altakhfid_home_banner_header_colors_v1';
  Map<int, List<Map<String, dynamic>>> _cachedBannerColors = {};

  @override
  void initState() {
    super.initState();
    _homeScrollController = ScrollController()..addListener(_handleHomeScroll);
    unawaited(_loadCachedBannerColors());
    load();
  }

  Future<void> _loadCachedBannerColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bannerColorCacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final next = <int, List<Map<String, dynamic>>>{};
      for (final entry in decoded.entries) {
        final scope = int.tryParse(entry.key.toString());
        if (scope == null || entry.value is! List) continue;
        final colors = (entry.value as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        if (colors.isNotEmpty) {
          next[scope] = colors;
        }
      }
      if (!mounted) {
        _cachedBannerColors = next;
        return;
      }
      setState(() => _cachedBannerColors = next);
    } catch (_) {
      // Local cache is optional; network data remains the source of truth.
    }
  }

  List<Map<String, dynamic>> _cachedColorsForScope([int? scope]) {
    return _cachedBannerColors[scope ?? selected] ??
        _cachedBannerColors[-1] ??
        const [];
  }

  Future<void> _saveBannerColorCache(
    int scope,
    List<Map<String, dynamic>> banners,
  ) async {
    final colors = banners.map((banner) {
      return <String, dynamic>{
        'id': sxInt(banner['id']),
        'root_category_id': banner['root_category_id'],
        'header_top_background_color':
            sxText(banner['header_top_background_color']),
        'header_category_text_color':
            sxText(banner['header_category_text_color']),
        'header_category_active_color':
            sxText(banner['header_category_active_color']),
      };
    }).where((item) =>
        sxText(item['header_top_background_color']).isNotEmpty ||
        sxText(item['header_category_text_color']).isNotEmpty ||
        sxText(item['header_category_active_color']).isNotEmpty).toList();

    if (colors.isEmpty) return;
    final next = <int, List<Map<String, dynamic>>>{
      ..._cachedBannerColors,
      scope: colors,
    };
    _cachedBannerColors = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        next.map((key, value) => MapEntry(key.toString(), value)),
      );
      await prefs.setString(_bannerColorCacheKey, encoded);
    } catch (_) {}
  }

  void _handleHomeScroll() {
    if (!_homeScrollController.hasClients || !mounted) return;
    final position = _homeScrollController.position;
    final pullExtent = (position.minScrollExtent - position.pixels)
        .clamp(0.0, 220.0)
        .toDouble();

    // Keep the header transparent for the first 40px of upward scroll.
    // It becomes solid only after the user passes that threshold.
    const headerScrollThreshold = 40.0;
    final scrolledDistance =
        position.pixels - position.minScrollExtent;
    final headerIsSolid = scrolledDistance >= headerScrollThreshold;

    if ((pullExtent - _pullExtent).abs() > .5 ||
        headerIsSolid != _headerIsSolid) {
      setState(() {
        _pullExtent = pullExtent;
        _headerIsSolid = headerIsSolid;
      });
    }
  }

  @override
  void dispose() {
    _homeScrollController
      ..removeListener(_handleHomeScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> refreshAndScrollTop() async {
    if (_homeScrollController.hasClients) {
      await _homeScrollController.animateTo(
        _homeScrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    await load();
  }

  Future<void> load() async {
    final int requestSerial = ++_loadSerial;
    if (mounted) {
      setState(() {
        loading = true;
        _activeBannerIndex = 0;
        _pullExtent = 0;
        _headerIsSolid = false;
      });
    }
    try {
      // Load the complete storefront payload once. Navigation is local.
      final h = await api.home();
      unawaited(_saveBannerColorCache(-1, sxMaps(h['banners'])));
      final nextLooks = sxMaps(h['looks']);
      final nextAllCategories =
          sxMaps(h['categories']).map(CategoryModel.fromJson).toList();
      final nextRoots = nextAllCategories.where((x) => x.parentId == null).toList()
        ..sort((a, b) => a.sortOrder == b.sortOrder
            ? a.id.compareTo(b.id)
            : a.sortOrder.compareTo(b.sortOrder));
      // Load the complete storefront product set once. Category and
      // discovery filtering happen locally.
      final nextProducts = await api.feed(
        sort: 'recommended',
        currencyId: state.currencyId,
      );
      try {
        final c = await api.cart(currencyId: state.currencyId);
        _CartBadge.value.value = sxMaps(c['item']?['items']).length;
      } catch (_) {}

      if (!mounted || requestSerial != _loadSerial) {
        return;
      }
      setState(() {
        home = h;
        looks = nextLooks;
        allCategories = nextAllCategories;
        roots = nextRoots;
        _allStoreProducts = nextProducts;
        products = _filterVisibleProducts(nextProducts);
        loading = false;
      });
    } catch (e) {
      if (!mounted || requestSerial != _loadSerial) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(sxText(e))));
      setState(() => loading = false);
    }
  }
  Set<int> _categoryScopeIds(int rootId) {
    final ids = <int>{rootId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final category in allCategories) {
        if (category.parentId != null &&
            ids.contains(category.parentId) &&
            ids.add(category.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  List<ProductModel> _filterVisibleProducts(
    List<ProductModel> source, [
    int? tab,
  ]) {
    final selectedTab = tab ?? discoveryTab;
    Iterable<ProductModel> scoped = source;

    if (selected >= 0) {
      scoped = scoped.where((product) {
        if (product.rootCategoryIds.isNotEmpty) {
          return product.rootCategoryIds.contains(selected);
        }
        // Fallback for legacy cached/product payloads.
        final categoryIds = _categoryScopeIds(selected);
        return product.categoryIds.any(categoryIds.contains);
      });
    }

    final scopedList = scoped.toList();
    if (selectedTab == 2) return scopedList;

    final wanted = selectedTab == 0 ? 'offers' : 'new';
    final now = DateTime.now().toUtc();

    return scopedList.where((product) {
      return product.badges.any((badge) {
        if (sxText(badge['storefront_tab']) != wanted) return false;
        final starts = DateTime.tryParse(sxText(badge['starts_at']));
        final ends = DateTime.tryParse(sxText(badge['ends_at']));
        if (starts != null && starts.isAfter(now)) return false;
        if (ends != null && !ends.isAfter(now)) return false;
        return true;
      });
    }).toList();
  }

  Map<String, dynamic> _categoryDisplaySettings() {
    final payload = home['category_display'];
    if (payload is! Map) {
      return const {
        'grid_rows': 2,
        'show_coupon_strip': true,
        'show_looks_strip': true,
        'item_shape': 'circle',
        'item_size': 64,
        'item_width': 64,
        'item_height': 64,
        'item_spacing': 6,
        'item_corner_radius': 16,
        'item_label_font_size': 9,
        'item_label_bold': true,
      };
    }
    final global = sxMaps([payload['all']]).isNotEmpty
        ? Map<String, dynamic>.from(payload['all'] as Map)
        : <String, dynamic>{};
    if (selected < 0) return global;
    final categories = payload['categories'];
    if (categories is Map) {
      final scoped = categories[selected.toString()];
      if (scoped is Map) {
        return {
          ...global,
          ...Map<String, dynamic>.from(scoped),
        };
      }
    }
    return global;
  }

  double _homeHeaderCategoryGap() {
    final payload = home['ui_settings'];
    if (payload is! Map) return 3.0;
    final raw = payload['home_header_category_gap'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(sxText(raw));
    if (value == null || !value.isFinite) return 3.0;
    return value.clamp(-30.0, 120.0).toDouble();
  }

  Map<String, dynamic> _couponDisplaySettings() {
    final payload = home['coupon_strip'];
    const defaults = <String, dynamic>{
      'enabled': true,
      'auto_flip': true,
      'flip_seconds': 4,
      'cards_per_slide': 1,
      'card_height': 64,
      'card_radius': 14,
      'card_spacing': 8,
      'title_font_size': 16,
      'subtitle_font_size': 11,
      'badge_font_size': 10,
      'default_background_color': '#E2EFDA',
      'default_text_color': '#1B5E20',
      'default_badge_background_color': '#166534',
      'default_badge_text_color': '#FFFFFF',
    };
    if (payload is! Map) return {...defaults};
    final global = payload['all'] is Map
        ? Map<String, dynamic>.from(payload['all'] as Map)
        : <String, dynamic>{};
    final categories = payload['categories'];
    if (selected >= 0 && categories is Map) {
      final scoped = categories[selected.toString()];
      if (scoped is Map) {
        return {...defaults, ...global, ...Map<String, dynamic>.from(scoped)};
      }
    }
    return {...defaults, ...global};
  }

  List<Map<String, dynamic>> _homeCoupons() {
    final payload = home['coupon_strip'];
    if (payload is! Map) return const [];
    final cards = payload['cards'];
    if (cards is! Map) return const [];
    final global = sxMaps(cards['all']);
    if (selected >= 0) {
      final categoryCards = cards['categories'];
      if (categoryCards is Map) {
        final scoped = categoryCards[selected.toString()];
        if (scoped is List && scoped.isNotEmpty) {
          return sxMaps(scoped);
        }
      }
    }
    return global;
  }

  List<Map<String, dynamic>> _homeLooks() {
    return looks.where((look) {
      final rootId = look['root_category_id'];
      final scopedRoot = rootId == null ? null : sxInt(rootId);
      return selected < 0 ? scopedRoot == null : scopedRoot == selected;
    }).toList()
      ..sort((a, b) {
        final ao = sxInt(a['sort_order']);
        final bo = sxInt(b['sort_order']);
        return ao == bo
            ? sxInt(a['id']).compareTo(sxInt(b['id']))
            : ao.compareTo(bo);
      });
  }

  List<Map<String, dynamic>> _homeBanners() {
    final banners = sxMaps(home['banners']);
    return banners.where((banner) {
      final rawRoot = banner['root_category_id'];
      final bannerRoot = rawRoot == null ? null : sxInt(rawRoot);
      return selected < 0
          ? bannerRoot == null
          : bannerRoot == selected;
    }).toList();
  }

  void _openHomeLook(BuildContext context, Map<String, dynamic> look) {
    final targets = sxMaps(look['targets']);
    if (targets.isNotEmpty) {
      final target = targets.first;
      final type = sxText(target['type']);
      final targetId = sxInt(target['target_id']);
      final title = sxText(target['name'], sxText(look['name'], 'الإطلالة'));
      if (type == 'circle' && targetId > 0) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SxResults(title: title, circleId: targetId),
          ),
        );
        return;
      }
      if (type == 'hashtag' && targetId > 0) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SxResults(title: title, hashtagId: targetId),
          ),
        );
        return;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SxLookDetail(look: look)),
    );
  }

  @override Widget build(BuildContext context) {
    final banners = _homeBanners();
    final safeBannerIndex = banners.isEmpty
        ? 0
        : _activeBannerIndex.clamp(0, banners.length - 1).toInt();
    final cachedBanners = _cachedColorsForScope();
    final cachedBannerIndex = cachedBanners.isEmpty
        ? 0
        : _activeBannerIndex.clamp(0, cachedBanners.length - 1).toInt();
    final activeBanner = banners.isNotEmpty
        ? banners[safeBannerIndex]
        : cachedBanners.isNotEmpty
            ? cachedBanners[cachedBannerIndex]
            : const <String, dynamic>{};
    final headerTopColor = sxColor(
      activeBanner['header_top_background_color'],
      Colors.white,
    );
    final categoryTextColor = sxColor(
      activeBanner['header_category_text_color'],
      Colors.white,
    );
    final categoryActiveColor = sxColor(
      activeBanner['header_category_active_color'],
      Colors.white,
    );
    final pullGradientHeight = _pullExtent.clamp(0.0, 220.0).toDouble();
    // Keep the lower end of the pull gradient behind the hero image instead
    // of stopping exactly at the banner's top edge. This removes the hard
    // transition and lets the darker part disappear naturally underneath the
    // banner while the user pulls down.
    final heroHeight = _homeHeroKey.currentContext?.size?.height ?? 280.0;
    final pullGradientTail = (heroHeight * 0.5).clamp(110.0, 180.0).toDouble();
    final pullGradientTotalHeight =
        pullGradientHeight > 0
            ? pullGradientHeight + pullGradientTail
            : 0.0;
    final bannerTopStop = pullGradientTotalHeight > 0
        ? (pullGradientHeight / pullGradientTotalHeight)
            .clamp(0.16, 0.72)
            .toDouble()
        : 0.16;
    final effectiveCategoryTextColor =
        _headerIsSolid ? Colors.black : categoryTextColor;
    final effectiveCategoryActiveColor =
        _headerIsSolid ? Colors.black : categoryActiveColor;
    final headerCategoryGap = _homeHeaderCategoryGap();
    final categoryDisplay = _categoryDisplaySettings();
    final couponStrip = _couponDisplaySettings();
    final coupons = _homeCoupons();
    final showCoupons = categoryDisplay['show_coupon_strip'] == true &&
        couponStrip['enabled'] == true &&
        coupons.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: pullGradientTotalHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      headerTopColor,
                      Color.lerp(headerTopColor, Colors.black, .68) ??
                          Colors.black,
                      Colors.black,
                    ],
                    stops: [
                      0.0,
                      bannerTopStop * 0.86,
                      1.0,
                    ],
                  ),
                ),
              ),
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis != Axis.vertical) return false;

              // Only the HOME CustomScrollView may drive the pull-to-stretch
              // effect. Nested vertical PageViews (notably the coupon
              // carousel) also emit ScrollNotifications; treating those as
              // a pull would make the banner gradient appear after a coupon
              // flip/swipe and leave the home page visually stretched.
              if (notification.depth != 0) return false;

              if (notification is OverscrollNotification &&
                  notification.metrics.pixels <=
                      notification.metrics.minScrollExtent) {
                final extent = (_pullExtent - notification.overscroll)
                    .clamp(0.0, 220.0)
                    .toDouble();
                if ((extent - _pullExtent).abs() > .5 && mounted) {
                  setState(() => _pullExtent = extent);
                }
              } else if (notification is ScrollUpdateNotification &&
                  notification.metrics.pixels <=
                      notification.metrics.minScrollExtent &&
                  (notification.scrollDelta ?? 0) < 0) {
                final extent = (_pullExtent - (notification.scrollDelta ?? 0))
                    .clamp(0.0, 220.0)
                    .toDouble();
                if ((extent - _pullExtent).abs() > .5 && mounted) {
                  setState(() => _pullExtent = extent);
                }
              } else if (notification is ScrollEndNotification &&
                  _pullExtent > 0 &&
                  mounted) {
                // The controller will keep this in sync while the bounce settles.
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: load,
              color: headerTopColor,
              backgroundColor: Colors.white,
              child: Transform.translate(
                offset: Offset(0, pullGradientHeight),
                child: CustomScrollView(
                  controller: _homeScrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
          slivers: [
            SliverToBoxAdapter(
              child: _HomeHero(
                key: _homeHeroKey,
                banners: banners,
                onBannerChanged: (index) {
                  if (!mounted) return;
                  if (index == _activeBannerIndex) return;
                  setState(() => _activeBannerIndex = index);
                },
              ),
            ),
            if (showCoupons)
              SliverToBoxAdapter(
                child: SxCouponStrip(
                  settings: couponStrip,
                  coupons: coupons,
                ),
              ),
            if (!loading &&
                categoryDisplay['show_looks_strip'] == true &&
                _homeLooks().isNotEmpty)
              SliverToBoxAdapter(
                child: SxHomeLookCarousel(
                  looks: _homeLooks(),
                  onTap: (look) => _openHomeLook(context, look),
                ),
              ),
            if (!loading)
              SliverToBoxAdapter(
                child: SxHomeCategoryGrid(
                  rootCategories: roots,
                  allCategories: allCategories,
                  selectedRootId: selected,
                  gridRows: sxInt(categoryDisplay['grid_rows'], 2).clamp(1, 6),
                  itemShape: sxText(categoryDisplay['item_shape'], 'circle'),
                  itemSize: sxDouble(categoryDisplay['item_size'], 64),
                  itemWidth: sxDouble(categoryDisplay['item_width'], sxDouble(categoryDisplay['item_size'], 64)),
                  itemHeight: sxDouble(categoryDisplay['item_height'], sxDouble(categoryDisplay['item_size'], 64)),
                  itemSpacing: sxDouble(categoryDisplay['item_spacing'], 6),
                  itemCornerRadius: sxDouble(
                    categoryDisplay['item_corner_radius'],
                    16,
                  ),
                  itemLabelFontSize: sxDouble(
                    categoryDisplay['item_label_font_size'],
                    9,
                  ),
                  itemLabelBold: categoryDisplay['item_label_bold'] != false,

                  onRootTap: (category) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SxResults(
                          title: category.name,
                          categoryId: category.id,
                        ),
                      ),
                    );
                  },
                  onCategoryTap: (category) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SxResults(
                          title: category.name,
                          categoryId: category.id,
                        ),
                      ),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: SxDiscoveryTabs(
                selected: discoveryTab,
                onChanged: (tab) {
                  setState(() {
                    discoveryTab = tab;
                    products = _filterVisibleProducts(
                      _allStoreProducts,
                      tab,
                    );
                  });
                },
              ),
            ),
            if (loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 18),
                  child: SxProductGrid(
                    products: products,
                    displaySettings: home['product_card_settings'] is Map
                        ? Map<String, dynamic>.from(
                            home['product_card_settings'] as Map,
                          )
                        : null,
                  ),
                ),
              ),
          ],
                ),
              ),
            ),
          ),
          _HomeFixedHeader(
            roots: roots,
            selected: selected,
            solidBackground: _headerIsSolid,
            categoryGap: headerCategoryGap,
            categoryTextColor: effectiveCategoryTextColor,
            categoryActiveColor: effectiveCategoryActiveColor,
            onSelected: (id) {
              if (selected == id) return;
              setState(() {
                selected = id;
                _activeBannerIndex = 0;
                products = _filterVisibleProducts(_allStoreProducts);
              });
            },
            onSearch: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SxSearchScreen()),
            ),
            onWishlist: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SxWishlistScreen()),
            ),
            onNotifications: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SxNotificationsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeFixedHeader extends StatelessWidget {
  final List<CategoryModel> roots;
  final int selected;
  final bool solidBackground;
  final double categoryGap;
  final Color categoryTextColor;
  final Color categoryActiveColor;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch, onWishlist, onNotifications;

  const _HomeFixedHeader({
    required this.roots,
    required this.selected,
    required this.solidBackground,
    this.categoryGap = 3,
    required this.categoryTextColor,
    required this.categoryActiveColor,
    required this.onSelected,
    required this.onSearch,
    required this.onWishlist,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <CategoryModel>[
      const CategoryModel(id: -1, name: 'الكل'),
      ...roots,
    ];
    final topInset = MediaQuery.of(context).padding.top;
    final effectiveGap = categoryGap.clamp(-30.0, 120.0).toDouble();
    final extraHeaderSpace = effectiveGap > 3.0 ? effectiveGap - 3.0 : 0.0;
    final categoryShift = effectiveGap < 3.0 ? effectiveGap - 3.0 : 0.0;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: solidBackground ? Colors.white : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: solidBackground ? const Color(0xFFE6E6E6) : Colors.transparent,
                width: 1,
              ),
            ),
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: topInset),
            SizedBox(
              height: 48 + extraHeaderSpace,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 3),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    children: [
                      SxCircleIcon(
                        icon: Icons.notifications_none_outlined,
                        onTap: onNotifications,
                        dot: true,
                        iconColor: solidBackground
                            ? Colors.black
                            : Colors.white,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: GestureDetector(
                          onTap: onSearch,
                          child: SxSearchBar(
                            // Keep the search field white. The search icon
                            // switches presentation with the sticky header
                            // state, matching the SHEIN-style header treatment.
                            borderColor: solidBackground
                                ? const Color(0xFF111111)
                                : Colors.transparent,
                            backgroundColor: Colors.white,
                            iconColor: solidBackground
                                ? Colors.white
                                : Colors.black,
                            iconBackgroundColor: solidBackground
                                ? Colors.black
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      SxCircleIcon(
                        icon: Icons.favorite_border,
                        onTap: onWishlist,
                        iconColor: solidBackground
                            ? Colors.black
                            : Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, categoryShift),
              child: SizedBox(
                height: 42,
                child: Directionality(
                textDirection: TextDirection.rtl,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  children: tabs.map((t) {
                    final active = selected == t.id;
                    return InkWell(
                      onTap: () => onSelected(t.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              t.name,
                              style: TextStyle(
                                color: active
                                    ? categoryActiveColor
                                    : categoryTextColor,
                                fontSize: 13,
                                fontWeight: active
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                                shadows: const [
                                  Shadow(
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                    color: Colors.black26,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: active ? 35 : 0,
                              height: 3,
                              decoration: BoxDecoration(
                                color: categoryActiveColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
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

class _HomeHero extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  final ValueChanged<int>? onBannerChanged;

  const _HomeHero({
    super.key,
    required this.banners,
    this.onBannerChanged,
  });

  @override
  State<_HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<_HomeHero> {
  static const int _virtualPages = 1000000;

  int page = 0;
  int _virtualPage = 0;
  Timer? _timer;
  late final PageController _controller;

  int _middlePage(int length) {
    if (length <= 0) return 0;
    final middle = _virtualPages ~/ 2;
    return middle - (middle % length);
  }

  @override
  void initState() {
    super.initState();
    final length = widget.banners.length;
    _virtualPage = _middlePage(length);
    _controller = PageController(initialPage: _virtualPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.banners.isNotEmpty) {
        final current = _virtualPage % widget.banners.length;
        page = current;
        widget.onBannerChanged?.call(current);
        _scheduleNext();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.banners.length == 0 && widget.banners.isNotEmpty) {
      final target = _middlePage(widget.banners.length);
      _virtualPage = target;
      page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(target);
        _scheduleNext();
        widget.onBannerChanged?.call(0);
      });
      return;
    }

    if (oldWidget.banners.length != widget.banners.length) {
      if (widget.banners.isEmpty) {
        _timer?.cancel();
        page = 0;
        _virtualPage = 0;
        return;
      }

      final currentIndex = _virtualPage % widget.banners.length;
      _virtualPage = _middlePage(widget.banners.length) + currentIndex;
      page = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpToPage(_virtualPage);
        widget.onBannerChanged?.call(currentIndex);
        _scheduleNext();
      });
      return;
    }

    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _pageChanged(int value) {
    if (!mounted || widget.banners.isEmpty) return;
    _virtualPage = value;
    final length = widget.banners.length;
    final current = value % length;
    setState(() => page = current);
    widget.onBannerChanged?.call(current);
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!mounted || widget.banners.length <= 1) return;
    final index = _virtualPage % widget.banners.length;
    final seconds =
        (sxInt(widget.banners[index]['duration'], 6)).clamp(1, 120);
    _timer = Timer(Duration(seconds: seconds), () {
      if (!mounted || !_controller.hasClients || widget.banners.length <= 1) {
        return;
      }
      _controller.animateToPage(
        _virtualPage + 1,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewportWidth = media.size.width;

    final configuredSpec = sxText(
      widget.banners.isNotEmpty ? widget.banners.first['size_spec'] : '',
    );
    final ratioMatch = RegExp(
      r'(?:mobile\s+)?(\d+(?:\.\d+)?)\s*[:x]\s*(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(configuredSpec);
    final configuredRatio = ratioMatch == null
        ? null
        : double.tryParse(ratioMatch.group(1)!)! /
            double.tryParse(ratioMatch.group(2)!)!;
    final fallbackHeroHeight = viewportWidth < 360
        ? viewportWidth * .75
        : viewportWidth > 430
            ? 320.0
            : viewportWidth * .68;
    final heroHeight = configuredRatio != null && configuredRatio > 0
        ? (viewportWidth / configuredRatio).clamp(190.0, 340.0)
        : fallbackHeroHeight;

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.banners.isEmpty)
            const ColoredBox(color: ClientTheme.soft)
          else
            PageView.builder(
              controller: _controller,
              itemCount: _virtualPages,
              onPageChanged: _pageChanged,
              itemBuilder: (_, virtualIndex) {
                final index = virtualIndex % widget.banners.length;
                return _BannerSlide(
                  banner: widget.banners[index],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SxBannerLandingScreen(banner: widget.banners[index]),
                    ),
                  ),
                );
              },
            ),
          Positioned(
            bottom: 7,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.banners.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: i == page ? 16 : 4,
                  height: 3,
                  decoration: BoxDecoration(
                    color: i == page ? Colors.white : Colors.white54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerSlide extends StatelessWidget {
  final Map<String, dynamic> banner;
  final VoidCallback onTap;

  const _BannerSlide({
    required this.banner,
    required this.onTap,
  });

  Alignment _alignment(String value, [Alignment fallback = Alignment.center]) {
    switch (value.toLowerCase()) {
      case 'top_left':
        return Alignment.topLeft;
      case 'top_center':
        return Alignment.topCenter;
      case 'top_right':
        return Alignment.topRight;
      case 'center_left':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'center_right':
        return Alignment.centerRight;
      case 'bottom_left':
        return Alignment.bottomLeft;
      case 'bottom_center':
        return Alignment.bottomCenter;
      case 'bottom_right':
        return Alignment.bottomRight;
      default:
        return fallback;
    }
  }

  TextAlign _textAlign(String value) {
    switch (value.toLowerCase()) {
      case 'top_left':
      case 'center_left':
      case 'bottom_left':
        return TextAlign.left;
      case 'top_right':
      case 'center_right':
      case 'bottom_right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  CrossAxisAlignment _crossAxis(String value) {
    switch (value.toLowerCase()) {
      case 'top_left':
      case 'center_left':
      case 'bottom_left':
        return CrossAxisAlignment.start;
      case 'top_right':
      case 'center_right':
      case 'bottom_right':
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.center;
    }
  }

  Color _color(dynamic value, Color fallback) {
    final raw = sxText(value);
    if (!raw.startsWith('#') || raw.length != 7) return fallback;
    return Color(int.tryParse('FF' + raw.substring(1), radix: 16) ?? fallback.value);
  }

  @override
  Widget build(BuildContext context) {
    final overlay = sxText(banner['overlay_text']);
    final title = sxText(banner['title']);
    final description = sxText(banner['description']);
    final button = sxText(banner['button_label']);
    final textPosition = sxText(banner['position_text'], 'center').toLowerCase();
    final configuredButtonPosition = sxText(banner['button_position'], 'same').toLowerCase();
    final buttonPosition = configuredButtonPosition == 'same' ? textPosition : configuredButtonPosition;
    final textAlign = _textAlign(textPosition);
    final crossAxis = _crossAxis(textPosition);
    final padding = sxDouble(banner['content_padding'], 18).clamp(0.0, 80.0).toDouble();
    final overlaySize = sxDouble(banner['overlay_font_size'], 13).clamp(8.0, 36.0).toDouble();
    final titleSize = sxDouble(banner['title_font_size'], 28).clamp(10.0, 60.0).toDouble();
    final descriptionSize = sxDouble(banner['description_font_size'], 16).clamp(8.0, 40.0).toDouble();
    final buttonSize = sxDouble(banner['button_font_size'], 11).clamp(8.0, 30.0).toDouble();
    final buttonRadius = sxDouble(banner['button_radius'], 0).clamp(0.0, 40.0).toDouble();
    final overlayColor = _color(banner['overlay_background_color'], Colors.transparent);
    final overlayOpacity = sxDouble(banner['overlay_opacity'], 0).clamp(0.0, 1.0);

    Widget buttonWidget() => ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _color(banner['button_background_color'], Colors.black),
        foregroundColor: _color(banner['button_text_color'], Colors.white),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        button,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: buttonSize, fontWeight: FontWeight.w900),
      ),
    );

    Widget textColumn({bool includeButton = false}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        if (overlay.isNotEmpty)
          Text(
            overlay,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: _color(banner['description_color'], Colors.white),
              fontSize: overlaySize,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        if (title.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: overlay.isNotEmpty ? 5 : 0),
            child: Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(
                color: _color(banner['title_color'], Colors.white),
                fontSize: titleSize,
                height: 1.08,
                fontWeight: FontWeight.w900,
                shadows: const [
                  Shadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black26),
                ],
              ),
            ),
          ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(
                color: _color(banner['description_color'], Colors.white),
                fontSize: descriptionSize,
                height: 1.18,
                fontWeight: FontWeight.w700,
                shadows: const [
                  Shadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black26),
                ],
              ),
            ),
          ),
        if (includeButton && button.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: buttonWidget(),
          ),
      ],
    );

    final hasText = overlay.isNotEmpty || title.isNotEmpty || description.isNotEmpty;
    final independentButton = button.isNotEmpty && configuredButtonPosition != 'same';

    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SxImage(
            url: banner['mobile_image_url'] ?? banner['image_url'],
            width: double.infinity,
            height: double.infinity,
          ),
          if (overlayOpacity > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: overlayColor.withOpacity(overlayOpacity)),
              ),
            ),
          if (hasText || (button.isNotEmpty && !independentButton))
            Positioned.fill(
              child: Align(
                alignment: _alignment(textPosition),
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: textColumn(includeButton: !independentButton),
                ),
              ),
            ),
          if (independentButton)
            Positioned.fill(
              child: Align(
                alignment: _alignment(buttonPosition),
                child: Padding(
                  padding: EdgeInsets.all(padding),
                  child: buttonWidget(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SxBannerLandingScreen extends StatefulWidget {
  final Map<String, dynamic> banner;
  const SxBannerLandingScreen({super.key, required this.banner});
  @override State<SxBannerLandingScreen> createState() => _SxBannerLandingScreenState();
}

class _SxBannerLandingScreenState extends State<SxBannerLandingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    final targets = sxMaps(widget.banner['targets']);
    final categoryTargets = targets
        .where((target) => sxText(target['type']) == 'category' && sxInt(target['id']) > 0)
        .toList();
    final hashtagTargets = targets
        .where((target) => sxText(target['type']) == 'hashtag' && sxInt(target['id']) > 0)
        .toList();

    Widget destination;
    final bannerTitle = sxText(widget.banner['title'], 'العروض');

    // A banner with multiple category targets represents one combined storefront
    // scope. A single category keeps the normal category-entry behavior.
    if (categoryTargets.length > 1) {
      destination = SxResults(
        title: bannerTitle,
        categoryIds: categoryTargets.map((target) => sxInt(target['id'])).toList(),
      );
    } else if (categoryTargets.length == 1) {
      final target = categoryTargets.first;
      destination = SxResults(
        title: sxText(target['name'], bannerTitle),
        categoryId: sxInt(target['id']),
      );
    } else if (hashtagTargets.length > 1) {
      destination = SxResults(
        title: bannerTitle,
        hashtagIds: hashtagTargets.map((target) => sxInt(target['id'])).toList(),
      );
    } else if (hashtagTargets.length == 1) {
      final target = hashtagTargets.first;
      destination = SxResults(
        title: sxText(target['name'], bannerTitle),
        hashtagId: sxInt(target['id']),
      );
    } else {
      final target = targets.isEmpty ? <String, dynamic>{} : targets.first;
      final type = sxText(target['type']);
      final id = sxInt(target['id']);

      if (type == 'product' && id > 0) {
        destination = SxProductScreen(id: id);
      } else if ((type == 'circle' || type == 'side_category_circle') && id > 0) {
        destination = SxResults(
          title: sxText(target['name'], bannerTitle),
          circleId: id,
        );
      } else {
        destination = SxResults(title: bannerTitle);
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class SxCouponStrip extends StatefulWidget {
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> coupons;

  const SxCouponStrip({
    super.key,
    required this.settings,
    required this.coupons,
  });

  @override
  State<SxCouponStrip> createState() => _SxCouponStripState();
}

class _SxCouponStripState extends State<SxCouponStrip> {
  PageController? _controller;
  Timer? _timer;
  int _page = 0;

  int get _perSlide {
    final value = sxInt(widget.settings['cards_per_slide'], 1);
    return value == 2 ? 2 : 1;
  }

  List<List<Map<String, dynamic>>> get _pages {
    final pages = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < widget.coupons.length; i += _perSlide) {
      pages.add(widget.coupons.skip(i).take(_perSlide).toList());
    }
    return pages;
  }

  int _secondsForPage(int index) {
    if (_pages.isEmpty) return 4;
    final pageIndex = index.clamp(0, _pages.length - 1).toInt();
    for (final card in _pages[pageIndex]) {
      final custom = sxInt(card['duration']);
      if (custom > 0) return custom.clamp(1, 120).toInt();
    }
    return sxInt(widget.settings['flip_seconds'], 4).clamp(1, 120).toInt();
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant SxCouponStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupons.length != widget.coupons.length ||
        oldWidget.settings['flip_seconds'] != widget.settings['flip_seconds'] ||
        oldWidget.settings['cards_per_slide'] !=
            widget.settings['cards_per_slide'] ||
        oldWidget.settings['card_height'] != widget.settings['card_height']) {
      _page = 0;
      if (_controller?.hasClients == true) {
        _controller!.jumpToPage(0);
      }
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    if (!mounted ||
        widget.settings['auto_flip'] != true ||
        _pages.length <= 1 ||
        _controller == null) {
      return;
    }
    final seconds = _secondsForPage(_page);
    _timer = Timer(Duration(seconds: seconds), () {
      if (!mounted || _controller == null || !_controller!.hasClients) return;
      final next = (_page + 1) % _pages.length;
      _controller!.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _pageChanged(int value) {
    if (!mounted) return;
    setState(() => _page = value);
    _schedule();
  }

  Color _color(dynamic value, Color fallback) {
    final raw = sxText(value);
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) return fallback;
    return Color(
      int.tryParse('FF' + raw.substring(1), radix: 16) ?? fallback.value,
    );
  }

  IconData _icon(String type) {
    switch (type) {
      case 'gift':
        return Icons.card_giftcard_outlined;
      case 'tag':
        return Icons.local_offer_outlined;
      case 'star':
        return Icons.star_outline;
      case 'truck':
        return Icons.local_shipping_outlined;
      case 'shield':
        return Icons.verified_user_outlined;
      case 'zap':
        return Icons.bolt_outlined;
      case 'shopping_bag':
        return Icons.shopping_bag_outlined;
      case 'delivery':
        return Icons.delivery_dining_outlined;
      case 'redeem':
        return Icons.redeem_outlined;
      case 'favorite':
        return Icons.favorite_border;
      case 'percent':
      default:
        return Icons.percent_outlined;
    }
  }

  Future<void> _openCoupon(
    BuildContext context,
    Map<String, dynamic> coupon,
  ) async {
    final type = sxText(coupon['display_type'], 'code');
    if (type == 'code') {
      final code = sxText(coupon['code']);
      if (code.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم نسخ الكود: $code'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1300),
          ),
        );
      }
      return;
    }

    final target = coupon['target'];
    if (target is! Map) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد وجهة لهذا العرض.')),
        );
      }
      return;
    }
    final targetType = sxText(target['type']);
    final id = sxInt(target['id']);
    if ((targetType == 'category' ||
            targetType == 'product' ||
            targetType == 'hashtag') &&
        id <= 0) {
      return;
    }

    if (targetType == 'product') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SxProductScreen(id: id)),
      );
    } else if (targetType == 'category') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SxResults(
            title: sxText(target['name'], 'العروض'),
            categoryId: id,
          ),
        ),
      );
    } else if (targetType == 'hashtag') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SxResults(
            title: sxText(target['name'], 'العروض'),
            hashtagId: id,
          ),
        ),
      );
    } else if (targetType == 'url') {
      final uri = Uri.tryParse(sxText(target['url']));
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط.')),
        );
      }
    }
  }

  Widget _cell(
    BuildContext context,
    Map<String, dynamic> coupon,
    double height,
  ) {
    final bg = _color(coupon['background_color'], Colors.white);
    final text = _color(coupon['text_color'], Colors.black87);
    final badgeBg =
        _color(coupon['badge_background_color'], Colors.black);
    final badgeText = _color(coupon['badge_text_color'], Colors.white);
    final radius =
        sxDouble(widget.settings['card_radius'], 14).clamp(0.0, 100.0).toDouble();
    final compact = height <= 66;
    final iconSize = compact ? 25.0 : 32.0;
    final badge = sxText(
      coupon['badge_text'],
      sxText(coupon['display_type']) == 'code' ? sxText(coupon['code']) : '',
    );
    final actionIcon = sxText(coupon['display_type']) == 'code'
        ? Icons.content_copy_outlined
        : Icons.arrow_back_ios_new;
    final widthAction = sxText(coupon['display_type']) == 'code';

    final title = Text(
      sxText(coupon['headline'], 'عرض خاص'),
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: text,
        fontSize: sxDouble(
          widget.settings['title_font_size'],
          compact ? 13 : 16,
        ).clamp(8.0, 32.0).toDouble(),
        height: 1.02,
        fontWeight: FontWeight.w900,
      ),
    );

    final subtitleRaw = sxText(coupon['subtitle']);
    final subtitle = subtitleRaw.isEmpty
        ? null
        : Text(
            subtitleRaw,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: text.withOpacity(.72),
              fontSize: sxDouble(
                widget.settings['subtitle_font_size'],
                compact ? 9 : 11,
              ).clamp(7.0, 24.0).toDouble(),
              height: 1.0,
              fontWeight: FontWeight.w600,
            ),
          );

    final badgeFont = sxDouble(
      widget.settings['badge_font_size'],
      compact ? 8 : 10,
    ).clamp(7.0, 22.0).toDouble();

    return Expanded(
      child: InkWell(
        onTap: () => _openCoupon(context, coupon),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: bg,
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(
                _icon(sxText(coupon['icon_type'])),
                size: iconSize,
                color: text,
              ),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badge.isNotEmpty)
                      Text(
                        badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: badgeText,
                          fontSize: badgeFont,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    if (badge.isNotEmpty && subtitle != null)
                      SizedBox(height: compact ? 2 : 3),
                    title,
                    if (subtitle != null) SizedBox(height: compact ? 2 : 3),
                    if (subtitle != null) subtitle,
                  ],
                ),
              ),
              if (widthAction) ...[
                SizedBox(width: compact ? 4 : 6),
                Icon(
                  actionIcon,
                  size: compact ? 13 : 15,
                  color: text.withOpacity(.55),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageView(BuildContext context, List<Map<String, dynamic>> page) {
    final height =
        sxDouble(widget.settings['card_height'], 64).clamp(48.0, 300.0).toDouble();

    if (page.length == 1) {
      final card = page.first;
      final bg = _color(card['background_color'], Colors.white);
      final borderRaw = sxText(card['border_color']);
      final border = borderRaw.isEmpty
          ? Colors.black.withOpacity(.06)
          : _color(borderRaw, Colors.black.withOpacity(.06));
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(
            sxDouble(widget.settings['card_radius'], 14)
                .clamp(0.0, 100.0)
                .toDouble(),
          ),
          border: Border.all(color: border, width: .7),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            sxDouble(widget.settings['card_radius'], 14)
                .clamp(0.0, 100.0)
                .toDouble(),
          ),
          child: _buildSingle(context, page.first, height),
        ),
      );
    }

    final left = page[0];
    final right = page[1];
    final dividerColor = _color(
      right['text_color'],
      _color(left['text_color'], Colors.black87),
    ).withOpacity(.18);
    final radius =
        sxDouble(widget.settings['card_radius'], 14).clamp(0.0, 100.0).toDouble();
    final borderRaw = sxText(left['border_color']);
    final border = borderRaw.isEmpty
        ? Colors.black.withOpacity(.06)
        : _color(borderRaw, Colors.black.withOpacity(.06));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 7),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: .7),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          _cell(context, right, height),
          Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: dividerColor),
          _cell(context, left, height),
        ],
      ),
    );
  }

  Widget _buildSingle(BuildContext context, Map<String, dynamic> coupon, double height) {
    final bg = _color(coupon['background_color'], Colors.white);
    final text = _color(coupon['text_color'], Colors.black87);
    final badgeText = _color(coupon['badge_text_color'], Colors.white);
    final badge = sxText(
      coupon['badge_text'],
      sxText(coupon['display_type']) == 'code' ? sxText(coupon['code']) : '',
    );
    final subtitleRaw = sxText(coupon['subtitle']);
    final compact = height <= 66;
    final titleSize = sxDouble(widget.settings['title_font_size'], compact ? 13 : 16)
        .clamp(8.0, 32.0).toDouble();
    final subtitleSize = sxDouble(widget.settings['subtitle_font_size'], compact ? 9 : 11)
        .clamp(7.0, 24.0).toDouble();
    final badgeSize = sxDouble(widget.settings['badge_font_size'], compact ? 8 : 10)
        .clamp(7.0, 22.0).toDouble();

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => _openCoupon(context, coupon),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 13, vertical: compact ? 5 : 8),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(_icon(sxText(coupon['icon_type'])), size: compact ? 26 : 34, color: text),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge.isNotEmpty)
                      Text(
                        badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: badgeText,
                          fontSize: badgeSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    Text(
                      sxText(coupon['headline'], 'عرض خاص'),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitleRaw.isNotEmpty)
                      Text(
                        subtitleRaw,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withOpacity(.72),
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                sxText(coupon['display_type']) == 'code'
                    ? Icons.content_copy_outlined
                    : Icons.arrow_back_ios_new,
                size: compact ? 13 : 15,
                color: text.withOpacity(.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coupons.isEmpty) return const SizedBox.shrink();
    final pages = _pages;
    final height =
        sxDouble(widget.settings['card_height'], 64).clamp(48.0, 300.0).toDouble();

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: pages.length > 1 ? 4 : 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: _controller,
              scrollDirection: Axis.vertical,
              pageSnapping: true,
              itemCount: pages.length,
              onPageChanged: _pageChanged,
              itemBuilder: (_, index) => _pageView(context, pages[index]),
            ),
          ),
          if (pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: i == _page ? 15 : 4,
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Colors.black
                          : const Color(0xFFBDBDBD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SxHomeLookCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> looks;
  final ValueChanged<Map<String, dynamic>> onTap;

  const SxHomeLookCarousel({
    super.key,
    required this.looks,
    required this.onTap,
  });

  Color _color(dynamic value, Color fallback) {
    final raw = sxText(value);
    if (!raw.startsWith('#') || raw.length != 7) return fallback;
    return Color(
      int.tryParse('FF' + raw.substring(1), radix: 16) ?? fallback.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (looks.isEmpty) return const SizedBox.shrink();
    final maxCardHeight = looks
        .map((look) => sxDouble(look['card_height'], 110))
        .fold<double>(40, (maxValue, value) =>
            value > maxValue ? value : maxValue);
    final sectionHeight = maxCardHeight.clamp(40.0, 500.0) + 24;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 7, 0, 8),
      child: SizedBox(
        height: sectionHeight,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          itemCount: looks.length,
          separatorBuilder: (_, index) {
            final spacing = sxDouble(
              looks[index]['card_spacing'],
              8,
            ).clamp(0.0, 30.0).toDouble();
            return SizedBox(width: spacing);
          },
          itemBuilder: (_, i) {
            final look = looks[i];
            final width = sxDouble(look['card_width'], 90)
                .clamp(40.0, 500.0)
                .toDouble();
            final height = sxDouble(look['card_height'], 110)
                .clamp(40.0, 500.0)
                .toDouble();
            final radius = sxDouble(look['card_radius'], 14)
                .clamp(0.0, 80.0)
                .toDouble();
            final shape = sxText(look['card_shape'], 'rounded');
            final clipRadius = shape == 'circle' ? width / 2 : radius;
            final captionBg = _color(
              look['caption_background_color'],
              Colors.black,
            );
            final captionText = _color(
              look['caption_text_color'],
              Colors.white,
            );
            final captionHeight = sxDouble(
              look['caption_height'],
              28,
            ).clamp(12.0, 120.0).toDouble();
            final captionFontSize = sxDouble(
              look['caption_font_size'],
              12,
            ).clamp(6.0, 40.0).toDouble();
            return InkWell(
              onTap: () => onTap(look),
              borderRadius: BorderRadius.circular(clipRadius),
              child: SizedBox(
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(clipRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SxImage(url: look['cover_url'], fit: BoxFit.cover),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          height: captionHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          color: captionBg,
                          child: Text(
                            sxText(look['name'], 'إطلالة'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: captionText,
                              fontSize: captionFontSize,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          ),
        ),
      ),
    );
  }
}

class SxHomeCategoryGrid extends StatelessWidget {
  final List<CategoryModel> rootCategories;
  final List<CategoryModel> allCategories;
  final int selectedRootId;
  final int gridRows;
  final String itemShape;
  final double itemSize;
  final double itemWidth;
  final double itemHeight;
  final double itemSpacing;
  final double itemCornerRadius;
  final double itemLabelFontSize;
  final bool itemLabelBold;
  final ValueChanged<CategoryModel> onRootTap;
  final ValueChanged<CategoryModel> onCategoryTap;

  const SxHomeCategoryGrid({
    super.key,
    required this.rootCategories,
    required this.allCategories,
    required this.selectedRootId,
    required this.gridRows,
    required this.itemShape,
    required this.itemSize,
    required this.itemWidth,
    required this.itemHeight,
    required this.itemSpacing,
    required this.itemCornerRadius,
    required this.itemLabelFontSize,
    required this.itemLabelBold,
    required this.onRootTap,
    required this.onCategoryTap,
  });

  List<CategoryModel> _childrenOf(int parentId) {
    return allCategories
        .where((category) => category.parentId == parentId)
        .toList()
      ..sort((a, b) => a.sortOrder == b.sortOrder
          ? a.id.compareTo(b.id)
          : a.sortOrder.compareTo(b.sortOrder));
  }

  List<CategoryModel> _descendantsOf(int rootId) {
    final result = <CategoryModel>[];
    final queue = <int>[rootId];
    final visited = <int>{rootId};

    while (queue.isNotEmpty) {
      final parent = queue.removeAt(0);
      for (final child in _childrenOf(parent)) {
        if (visited.add(child.id)) {
          result.add(child);
          queue.add(child.id);
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    // The root tabs already represent parent categories. With "الكل",
    // include every descendant branch of every root; when a root is selected,
    // include that root's complete descendant tree.
    final categories = selectedRootId < 0
        ? (rootCategories
              .expand((root) => _descendantsOf(root.id))
              .toList()
            ..sort((a, b) => a.sortOrder == b.sortOrder
                ? a.id.compareTo(b.id)
                : a.sortOrder.compareTo(b.sortOrder)))
        : _descendantsOf(selectedRootId);

    return _CategoryCircleGrid(
      // Keep all available subcategories. The grid is horizontally scrollable
      // whenever there are more columns than fit in the viewport.
      categories: categories.toList(),
      itemShape: itemShape,
      itemSize: itemSize,
      itemWidth: itemWidth,
      itemHeight: itemHeight,
      itemSpacing: itemSpacing,
      itemCornerRadius: itemCornerRadius,
      itemLabelFontSize: itemLabelFontSize,
      itemLabelBold: itemLabelBold,
      gridRows: gridRows,
      onTap: onCategoryTap,
    );
  }
}

class _CategoryCircleGrid extends StatelessWidget {
  final List<CategoryModel> categories;
  final String itemShape;
  final double itemSize;
  final double itemWidth;
  final double itemHeight;
  final double itemSpacing;
  final double itemCornerRadius;
  final double itemLabelFontSize;
  final bool itemLabelBold;
  final int gridRows;
  final ValueChanged<CategoryModel> onTap;

  const _CategoryCircleGrid({
    required this.categories,
    required this.itemShape,
    required this.itemSize,
    required this.itemWidth,
    required this.itemHeight,
    required this.itemSpacing,
    required this.itemCornerRadius,
    required this.itemLabelFontSize,
    required this.itemLabelBold,
    required this.gridRows,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox(height: 8);
    }

    final width = itemWidth.clamp(42.0, 240.0).toDouble();
    final height = itemHeight.clamp(42.0, 240.0).toDouble();
    final effectiveWidth = itemShape == 'circle'
        ? width < height ? width : height
        : width;
    final effectiveHeight = itemShape == 'circle'
        ? width < height ? width : height
        : height;
    final radius = itemShape == 'circle'
        ? effectiveWidth / 2
        : itemCornerRadius.clamp(0.0, 100.0).toDouble();
    // The configured dimensions are the actual visual tile dimensions.
    // Horizontal overflow is intentional so increasing the size never gets
    // silently clamped to the phone viewport.
    final rowCount = gridRows.clamp(1, 6).toInt();
    final cellWidth = effectiveWidth + itemSpacing;
    final cellHeight = effectiveHeight + 40;
    final gridHeight = cellHeight * rowCount +
        (rowCount - 1) * itemSpacing +
        11;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        7,
        7,
        7,
        itemSpacing.clamp(4.0, 12.0).toDouble(),
      ),
      child: SizedBox(
        height: gridHeight,
        child: GridView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: categories.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: rowCount,
            mainAxisSpacing: itemSpacing,
            crossAxisSpacing: itemSpacing,
            mainAxisExtent: cellWidth,
          ),
          itemBuilder: (_, i) => InkWell(
            onTap: () => onTap(categories[i]),
            borderRadius: BorderRadius.circular(radius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: effectiveWidth,
                  height: effectiveHeight,
                  decoration: BoxDecoration(
                    shape: itemShape == 'circle'
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    color: const Color(0xFFF4F4F4),
                    borderRadius: itemShape == 'circle'
                        ? null
                        : BorderRadius.circular(radius),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: .8,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SxImage(
                    url: categories[i].iconUrl,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: cellWidth,
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Text(
                      categories[i].name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: itemLabelFontSize.clamp(7.0, 24.0).toDouble(),
                        height: 1.05,
                        fontWeight: itemLabelBold
                            ? FontWeight.w900
                            : FontWeight.w500,
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

class SxDiscoveryTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const SxDiscoveryTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const labels = [
      ('العروض', Icons.local_offer_outlined),
      ('جديد', Icons.auto_awesome_outlined),
      ('لك', Icons.favorite_border),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(
          top: BorderSide(color: Color(0xFFE9E9E9), width: .7),
          bottom: BorderSide(color: Color(0xFFE9E9E9), width: .7),
        ),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: InkWell(
                onTap: () => onChanged(i),
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[i].$1,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.black,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        labels[i].$2,
                        size: 15,
                        color: active ? Colors.white : Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}



class SxFeatureTiles extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const SxFeatureTiles({super.key, required this.rows});
  @override Widget build(BuildContext context) {
    const labels = ['إطلالات يومية', 'محتشمة', 'عمل', 'حفلات'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 15, 12, 0),
      child: Row(children: List.generate(rows.length, (i) => Expanded(child: Padding(
        padding: EdgeInsets.only(left: i == rows.length - 1 ? 0 : 6),
        child: ClipRRect(borderRadius: BorderRadius.circular(17), child: SizedBox(height: 136, child: Stack(fit: StackFit.expand, children: [
          SxImage(url: rows[i]['cover_url']),
          Positioned(left: 0, right: 0, bottom: 0, child: Container(color: Colors.black.withOpacity(.62), padding: const EdgeInsets.symmetric(vertical: 7), child: Text(i < labels.length ? labels[i] : sxText(rows[i]['name']), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)))),
        ]))),
      )))),
    );
  }
}

class SxCircleRail extends StatelessWidget {
  final String title; final List<Map<String, dynamic>> rows; final ValueChanged<Map<String, dynamic>> onTap;
  const SxCircleRail({super.key, required this.title, required this.rows, required this.onTap});
  @override Widget build(BuildContext context) => Column(children: [
    SxSectionTitle(title: title),
    SizedBox(height: 118, child: ListView.separated(
      reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) => InkWell(onTap: () => onTap(rows[i]), child: SizedBox(width: 73, child: Column(children: [
        Container(width: 66, height: 66, decoration: const BoxDecoration(color: ClientTheme.soft, shape: BoxShape.circle), clipBehavior: Clip.antiAlias, child: SxImage(url: rows[i]['image_url'])),
        const SizedBox(height: 6),
        Text(sxText(rows[i]['name']), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
      ]))),
    )),
  ]);
}

class SxTrendRail extends StatelessWidget {
  final List<Map<String, dynamic>> trends;
  const SxTrendRail({super.key, required this.trends});
  @override Widget build(BuildContext context) => Column(children: [
    SxSectionTitle(title: 'ترندات', onMore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxTrendsScreen()))),
    SizedBox(height: 183, child: ListView.separated(
      reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: trends.length, separatorBuilder: (_, __) => const SizedBox(width: 7),
      itemBuilder: (_, i) {
        final t = trends[i]; final sec = sxInt((t['timer'] as Map?)?['seconds']);
        return InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxTrendDetailScreen(trend: t))), child: Container(
          width: 238, decoration: BoxDecoration(color: const Color(0xFF272727), borderRadius: BorderRadius.circular(10)), clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(child: SxImage(url: (t['background'] as Map?)?['url'])),
            Positioned(left: 0, right: 0, bottom: 0, child: Container(color: Colors.black.withOpacity(.68), padding: const EdgeInsets.all(8), child: Row(children: [
              Expanded(child: Text(sxText((t['hashtag'] as Map?)?['display_name']), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900))),
              SxPill(text: sec <= 0 ? 'مستمر' : 'خلال ' + ((sec / 86400).ceil()).toString() + ' يوم', background: ClientTheme.accent, foreground: Colors.white),
            ]))),
          ]),
        ));
      },
    )),
  ]);
}

double sxProductImageRatio(ProductModel product) {
  final direct = product.imageAspectRatio;
  if (direct != null && direct > 0) {
    return direct.clamp(.56, 1.45).toDouble();
  }
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

class SxProductGrid extends StatelessWidget {
  final List<ProductModel> products;
  final bool masonry;
  final Map<String, dynamic>? displaySettings;

  const SxProductGrid({
    super.key,
    required this.products,
    this.masonry = true,
    this.displaySettings,
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

  const _SxMasonryProductGrid({
    required this.products,
    this.displaySettings,
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

  const SxProductCard({
    super.key,
    required this.product,
    this.masonry = false,
    this.displaySettings,
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

  Map<String, dynamic> get _cardSettings => widget.displaySettings ?? const {};

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
                child: SxImage(
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

        if (_cardBool('show_product_badges', true) &&
            product.badges.isNotEmpty)
          _cornerPositioned(
            badgePosition,
            Padding(
              padding: EdgeInsets.only(
                top: badgePosition == 'top_right' ? badgeTopOffset - 6 : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: product.badges
                    .take(
                      _cardNumber('product_badge_max', 2)
                          .round()
                          .clamp(1, 4)
                          .toInt(),
                    )
                    .map(_badgeChip)
                    .toList(),
              ),
            ),
            offset: 6,
          ),

        if (_cardBool('colors_show', true) && product.colors.isNotEmpty)
          _cornerPositioned(
            colorPosition,
            colorSwatches(),
            bottomOffset: discount > 0 ? 32 : 6,
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
    final tab = sxText(badge['storefront_tab']);
    final fallback = tab == 'new'
        ? const Color(0xFF16A34A)
        : tab == 'offers'
            ? const Color(0xFFDC2626)
            : const Color(0xFF111827);
    final bg = sxColor(sxText(badge['bg_color']), fallback);
    final fg = sxColor(
      sxText(badge['text_color']),
      Colors.white,
    );
    final text = sxText(
      badge['custom_text'],
      sxText(badge['name'], sxText(badge['code'])),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          _cardNumber('product_badge_radius', 3),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: _cardNumber('product_badge_font_size', 8),
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final old = sxDouble(product.oldPrice);
    final now = sxDouble(product.price);
    final discount =
        old > now && old > 0 ? ((1 - now / old) * 100).round() : 0;
    final ratio = sxProductImageRatio(product);
    final gallery = _gallery;
    final rating = product.rating;
    final hasRating = rating != null && rating > 0;

    return Container(
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SxProductScreen(id: product.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _imageStack(
              ratio: ratio,
              masonry: widget.masonry,
              discount: discount,
              gallery: gallery,
            ),
          const SizedBox(height: 4),
          _trendRibbon(),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (discount > 0) ...[
                Text(
                  '-' + discount.toString() + '%',
                  style: const TextStyle(
                    color: ClientTheme.promo,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                product.price + ' ' + state.currencySymbol,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (product.oldPrice != null && product.oldPrice!.isNotEmpty)
            Text(
              product.oldPrice! + ' ' + state.currencySymbol,
              style: const TextStyle(
                fontSize: 8.5,
                color: ClientTheme.muted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          if (hasRating)
            Row(
              children: [
                const Icon(Icons.star, size: 12.5, color: Color(0xFFFFB400)),
                Text(
                  ' ' + rating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (product.reviewCount > 0)
                  Text(
                    ' (' + product.reviewCount.toString() + ')',
                    style: const TextStyle(
                      fontSize: 8,
                      color: ClientTheme.muted,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 4),
        ],
      ),
      ),
    );
  }
}

// Categories mirrors the Shein-style discovery layout using server-managed side categories and circle groups.
class SxCategoriesScreen extends StatefulWidget {
  const SxCategoriesScreen({super.key});

  @override
  State<SxCategoriesScreen> createState() => _SxCategoriesScreenState();
}

class _SxCategoriesScreenState extends State<SxCategoriesScreen> {
  Map<String, dynamic> home = <String, dynamic>{};
  List<CategoryModel> roots = <CategoryModel>[];
  List<Map<String, dynamic>> side = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> groups = <Map<String, dynamic>>[];
  Map<String, dynamic> circleDisplay = <String, dynamic>{};
  int selectedRoot = -1;
  int? selectedSideCategoryId;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      // Load the complete storefront once. Root/side/group navigation below
      // is intentionally local so switching tabs never makes another request.
      final h = await api.home();
      final nextAllCategories = sxMaps(h['categories'])
          .map(CategoryModel.fromJson)
          .toList();
      final nextRoots = nextAllCategories
          .where((x) => x.parentId == null)
          .toList()
        ..sort(
          (a, b) => a.sortOrder == b.sortOrder
              ? a.id.compareTo(b.id)
              : a.sortOrder.compareTo(b.sortOrder),
        );

      final nextSide = sxMaps(h['side_categories']);
      final nextGroups = sxMaps(h['side_circle_groups']);
      final nextDisplay = h['side_circle_display'] is Map
          ? Map<String, dynamic>.from(h['side_circle_display'] as Map)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        home = h;
        roots = nextRoots;
        side = nextSide;
        groups = nextGroups;
        circleDisplay = nextDisplay;
        loading = false;
      });
      _ensureValidSideSelection();
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e, 'تعذر تحميل الفئات'))),
      );
    }
  }

  List<Map<String, dynamic>> get _visibleSideCategories {
    final rows = side
        .where((row) => row['is_active'] != false)
        .where((row) {
          if (selectedRoot < 0) return true;
          return sxInt(row['root_category_id']) == selectedRoot;
        })
        .toList();

    rows.sort((a, b) {
      final ao = sxInt(a['sort_order']);
      final bo = sxInt(b['sort_order']);
      return ao == bo
          ? sxInt(a['id']).compareTo(sxInt(b['id']))
          : ao.compareTo(bo);
    });
    return rows;
  }

  List<Map<String, dynamic>> get _visibleGroups {
    final selectedSide = _selectedSide;
    final selectedSideId =
        selectedSide == null ? null : sxInt(selectedSide['id']);

    final rows = <Map<String, dynamic>>[];
    for (final row in groups) {
      if (row['is_active'] == false) continue;

      final root = row['root_category_id'];
      if (selectedRoot >= 0 &&
          root != null &&
          sxInt(root) != selectedRoot) {
        continue;
      }

      final sourceCircles = sxMaps(row['circles']);
      final visibleCircles = selectedSideId == null
          ? sourceCircles
          : sourceCircles
              .where((circle) =>
                  sxInt(circle['side_category_id']) == selectedSideId)
              .toList();

      if (visibleCircles.isEmpty) continue;

      final next = Map<String, dynamic>.from(row)
        ..['circles'] = visibleCircles;
      rows.add(next);
    }

    rows.sort((a, b) {
      final ao = sxInt(a['sort_order']);
      final bo = sxInt(b['sort_order']);
      return ao == bo
          ? sxInt(a['id']).compareTo(sxInt(b['id']))
          : ao.compareTo(bo);
    });
    return rows;
  }

  Map<String, dynamic>? get _selectedSide {
    for (final row in _visibleSideCategories) {
      if (sxInt(row['id']) == selectedSideCategoryId) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> get _visibleCircles {
    final selectedRow = _selectedSide;
    if (selectedRow != null) {
      final selectedId = sxInt(selectedRow['id']);
      return sxMaps(selectedRow['circles'])
          .where((circle) => sxInt(circle['side_category_id']) == selectedId)
          .toList();
    }

    final result = <Map<String, dynamic>>[];
    for (final row in _visibleSideCategories) {
      final sideId = sxInt(row['id']);
      result.addAll(
        sxMaps(row['circles'])
            .where((circle) => sxInt(circle['side_category_id']) == sideId),
      );
    }
    return result;
  }

  void _ensureValidSideSelection() {
    final visible = _visibleSideCategories;
    if (visible.isEmpty) {
      if (selectedSideCategoryId != null && mounted) {
        setState(() => selectedSideCategoryId = null);
      }
      return;
    }

    final valid = visible.any((row) => sxInt(row['id']) == selectedSideCategoryId);
    if (!valid && mounted) {
      setState(() => selectedSideCategoryId = sxInt(visible.first['id']));
    }
  }

  void _selectRoot(int id) {
    if (selectedRoot == id) return;
    setState(() {
      selectedRoot = id;
      selectedSideCategoryId = null;
    });
    _ensureValidSideSelection();
  }

  void _selectSide(Map<String, dynamic>? item) {
    if (item == null) {
      _ensureValidSideSelection();
      return;
    }
    final id = sxInt(item['id']);
    if (id <= 0 || id == selectedSideCategoryId) return;

    // Side categories are navigation context only. Tapping the side item
    // changes the circles shown beside it; only a circle opens results.
    setState(() => selectedSideCategoryId = id);
  }

  void _openCircle(BuildContext context, Map<String, dynamic> circle) {
    final id = sxInt(circle['id']);
    if (id <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SxResults(
          title: sxText(circle['name'], 'الفئة'),
          // The circle is the result scope. The side category stays on the
          // categories screen as UI context and is intentionally not passed.
          circleId: id,
        ),
      ),
    );
  }

  void _openGroup(BuildContext context, Map<String, dynamic> group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SxCircleGroupScreen(
          group: group,
          displaySettings: circleDisplay,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.of(context).padding.top + 90;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: SizedBox(height: headerHeight),
                        ),
                        SliverToBoxAdapter(
                          child: _SideCategoryExplorer(
                            sideCategories: _visibleSideCategories,
                            selectedId: selectedSideCategoryId,
                            circles: _visibleCircles,
                            groups: _visibleGroups,
                            settings: circleDisplay,
                            onSideSelected: _selectSide,
                            onCircleTap: (circle) => _openCircle(context, circle),
                            onGroupTap: (group) => _openGroup(context, group),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: headerHeight,
            bottom: 0,
            right: 115,
            child: IgnorePointer(
              child: Container(
                width: 1,
                color: const Color(0xFFE6E6E6),
              ),
            ),
          ),
          _HomeFixedHeader(
            roots: roots,
            selected: selectedRoot,
            solidBackground: true,
            categoryTextColor: Colors.black,
            categoryActiveColor: Colors.black,
            onSelected: _selectRoot,
            onSearch: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SxSearchScreen()),
            ),
            onWishlist: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SxWishlistScreen()),
            ),
            onNotifications: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SxNotificationsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class SxRootTabs extends StatelessWidget {
  final List<CategoryModel> categories;
  final int? selected;
  final ValueChanged<int?> onChanged;

  const SxRootTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            children: [
              _tab('الكل', selected == null, () => onChanged(null)),
              ...categories.map(
                (c) => _tab(
                  c.name,
                  selected == c.id,
                  () => onChanged(c.id),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _tab(String t, bool active, VoidCallback tap) => InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                t,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: active ? 33 : 0,
                height: 2,
                color: Colors.black,
              ),
            ],
          ),
        ),
      );
}

class _SideCategoryExplorer extends StatelessWidget {
  final List<Map<String, dynamic>> sideCategories;
  final int? selectedId;
  final List<Map<String, dynamic>> circles;
  final List<Map<String, dynamic>> groups;
  final Map<String, dynamic> settings;
  final ValueChanged<Map<String, dynamic>?> onSideSelected;
  final ValueChanged<Map<String, dynamic>> onCircleTap;
  final ValueChanged<Map<String, dynamic>> onGroupTap;

  const _SideCategoryExplorer({
    required this.sideCategories,
    required this.selectedId,
    required this.circles,
    required this.groups,
    required this.settings,
    required this.onSideSelected,
    required this.onCircleTap,
    required this.onGroupTap,
  });

  int _int(String key, int fallback) => sxInt(settings[key], fallback);

  double _double(String key, double fallback) =>
      sxDouble(settings[key], fallback);

  String _text(String key, String fallback) =>
      sxText(settings[key], fallback);

  @override
  Widget build(BuildContext context) {
    // Apply the selected side category scope one final time at the rendering
    // boundary. This prevents circles belonging to sibling side categories
    // under the same root from leaking into the visible grid/groups.
    final scopedCircles = selectedId == null
        ? circles
        : circles
            .where((circle) => sxInt(circle['side_category_id']) == selectedId)
            .toList();

    final scopedGroups = groups
        .map((group) {
          final items = sxMaps(group['circles']);
          final filteredItems = selectedId == null
              ? items
              : items
                  .where((circle) =>
                      sxInt(circle['side_category_id']) == selectedId)
                  .toList();
          if (filteredItems.isEmpty) return null;
          return <String, dynamic>{
            ...group,
            'circles': filteredItems,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final railWidth = 116.0;
    final columns = _int('grid_columns', 3).clamp(2, 5).toInt();
    final spacing = _double('item_spacing', 8).clamp(0, 30).toDouble();
    final widthSetting =
        _double('item_width', 88).clamp(48, 180).toDouble();
    final heightSetting =
        _double('item_height', 88).clamp(48, 180).toDouble();
    final labelSize =
        _double('item_label_font_size', 10).clamp(7, 24).toDouble();
    final titleSize =
        _double('title_font_size', 15).clamp(10, 28).toDouble();
    final radius =
        _double('item_corner_radius', 18).clamp(0, 90).toDouble();
    final shape = _text('item_shape', 'circle');
    final bold = settings['item_label_bold'] != false;
    final sectionSpacing =
        _double('section_spacing', 14).clamp(4, 40).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth =
            (constraints.maxWidth - railWidth).clamp(0.0, constraints.maxWidth);
        final available = leftWidth - 14;
        final adaptiveWidth =
            ((available - spacing * (columns - 1)) / columns)
                .clamp(48.0, widthSetting)
                .toDouble();
        final adaptiveHeight =
            shape == 'circle' ? adaptiveWidth : heightSetting;

        Widget circleTile(
          Map<String, dynamic> circle, {
          double? forcedWidth,
        }) {
          return _SideCircleTile(
            circle: circle,
            width: forcedWidth ?? widthSetting,
            height: heightSetting,
            shape: shape,
            radius: radius,
            labelFontSize: labelSize,
            labelBold: bold,
            onTap: () => onCircleTap(circle),
          );
        }

        return Container(
          color: Colors.white,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 7, 7, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (scopedCircles.isNotEmpty)
                        _SideCircleGrid(
                          circles: scopedCircles,
                          columns: columns,
                          spacing: spacing,
                          width: adaptiveWidth,
                          height: adaptiveHeight,
                          shape: shape,
                          radius: radius,
                          labelFontSize: labelSize,
                          labelBold: bold,
                          onTap: onCircleTap,
                        )
                      else if (settings['show_empty_state'] != false)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 48,
                            horizontal: 18,
                          ),
                          child: Text(
                            'لا توجد دوائر لهذا القسم حاليًا',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: ClientTheme.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (scopedGroups.isNotEmpty) ...[
                        SizedBox(height: sectionSpacing),
                        for (final group in scopedGroups) ...[
                          _SideCircleGroupHeader(
                            title: sxText(group['name'], 'مجموعة'),
                            fontSize: titleSize,
                            showViewAll: group['show_view_all'] != false,
                            onViewAll: () => onGroupTap(group),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: adaptiveHeight + 48,
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                physics: const BouncingScrollPhysics(),
                                itemCount: sxMaps(group['circles']).length,
                                separatorBuilder: (_, __) =>
                                    SizedBox(width: spacing),
                                itemBuilder: (_, i) {
                                  final row = sxMaps(group['circles'])[i];
                                  return circleTile(
                                    row,
                                    forcedWidth: adaptiveWidth,
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(height: sectionSpacing),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: railWidth,
                child: _SideCategoryRail(
                  categories: sideCategories,
                  selectedId: selectedId,
                  onSelected: onSideSelected,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SideCategoryRail extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final int? selectedId;
  final ValueChanged<Map<String, dynamic>?> onSelected;

  const _SideCategoryRail({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 440),
        color: const Color(0xFFF8F8F8),
        child: Column(
          children: [
            for (final row in categories)
              InkWell(
                onTap: () => onSelected(row),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11),
                  decoration: BoxDecoration(
                    color: sxInt(row['id']) == selectedId
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    sxText(row['name']),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: sxInt(row['id']) == selectedId
                          ? FontWeight.w900
                          : FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _SideCircleGrid extends StatelessWidget {
  final List<Map<String, dynamic>> circles;
  final int columns;
  final double spacing;
  final double width;
  final double height;
  final String shape;
  final double radius;
  final double labelFontSize;
  final bool labelBold;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _SideCircleGrid({
    required this.circles,
    required this.columns,
    required this.spacing,
    required this.width,
    required this.height,
    required this.shape,
    required this.radius,
    required this.labelFontSize,
    required this.labelBold,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cellHeight = height + 42;
    return GridView.builder(
      primary: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: circles.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: width / cellHeight,
      ),
      itemBuilder: (_, i) => _SideCircleTile(
        circle: circles[i],
        width: width,
        height: height,
        shape: shape,
        radius: radius,
        labelFontSize: labelFontSize,
        labelBold: labelBold,
        onTap: () => onTap(circles[i]),
      ),
    );
  }
}

class _SideCircleTile extends StatelessWidget {
  final Map<String, dynamic> circle;
  final double width;
  final double height;
  final String shape;
  final double radius;
  final double labelFontSize;
  final bool labelBold;
  final VoidCallback onTap;

  const _SideCircleTile({
    required this.circle,
    required this.width,
    required this.height,
    required this.shape,
    required this.radius,
    required this.labelFontSize,
    required this.labelBold,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visualWidth = width;
    final visualHeight = shape == 'circle' ? width : height;
    final clipRadius = shape == 'circle'
        ? visualWidth / 2
        : shape == 'square'
            ? 0.0
            : radius;

    return SizedBox(
      width: visualWidth,
      height: visualHeight + 40,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(clipRadius),
        child: Column(
          children: [
            Container(
              width: visualWidth,
              height: visualHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F1),
                shape: shape == 'circle' ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: shape == 'circle'
                    ? null
                    : BorderRadius.circular(clipRadius),
              ),
              child: SxImage(
                url: circle['image_url'],
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: visualWidth + 2,
              height: 34,
              child: Text(
                sxText(circle['name'], 'فئة'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: labelFontSize,
                  fontWeight:
                      labelBold ? FontWeight.w900 : FontWeight.w600,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideCircleGroupHeader extends StatelessWidget {
  final String title;
  final double fontSize;
  final bool showViewAll;
  final VoidCallback onViewAll;

  const _SideCircleGroupHeader({
    required this.title,
    required this.fontSize,
    required this.showViewAll,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) => Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (showViewAll)
            TextButton(
              onPressed: onViewAll,
              child: const Text(
                'عرض الكل',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      );
}

class SxCircleGroupScreen extends StatelessWidget {
  final Map<String, dynamic> group;
  final Map<String, dynamic> displaySettings;

  const SxCircleGroupScreen({
    super.key,
    required this.group,
    required this.displaySettings,
  });

  @override
  Widget build(BuildContext context) {
    final circles = sxMaps(group['circles']);
    final columns =
        sxInt(displaySettings['grid_columns'], 3).clamp(2, 5).toInt();
    final spacing =
        sxDouble(displaySettings['item_spacing'], 8).clamp(0, 30).toDouble();
    final width =
        sxDouble(displaySettings['item_width'], 88).clamp(48, 180).toDouble();
    final height =
        sxDouble(displaySettings['item_height'], 88).clamp(48, 180).toDouble();
    final shape = sxText(displaySettings['item_shape'], 'circle');
    final radius =
        sxDouble(displaySettings['item_corner_radius'], 18).clamp(0, 90).toDouble();
    final font =
        sxDouble(displaySettings['item_label_font_size'], 10).clamp(7, 24).toDouble();
    final bold = displaySettings['item_label_bold'] != false;

    return SxShellPage(
      title: sxText(group['name'], 'مجموعة الدوائر'),
      back: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(7, 10, 7, 24),
        children: [
          if (sxText(group['root_category_name']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 0, 5, 10),
              child: Text(
                sxText(group['root_category_name']),
                style: const TextStyle(
                  fontSize: 11,
                  color: ClientTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (circles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(child: Text('لا توجد دوائر داخل هذه المجموعة')),
            )
          else
            GridView.builder(
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: circles.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: width / (height + 42),
              ),
              itemBuilder: (_, i) => _SideCircleTile(
                circle: circles[i],
                width: width,
                height: height,
                shape: shape,
                radius: radius,
                labelFontSize: font,
                labelBold: bold,
                onTap: () {
                  final id = sxInt(circles[i]['id']);
                  if (id <= 0) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SxResults(
                        title: sxText(circles[i]['name'], 'الفئة'),
                        // A circle opens by circle ID only.
                        circleId: id,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
    );
  }
}


class SxResults extends StatefulWidget {
  final String title;
  final String? query;
  final int? categoryId, circleId, hashtagId, sideCategoryId;
  final List<int>? categoryIds, hashtagIds;

  const SxResults({
    super.key,
    required this.title,
    this.query,
    this.categoryId,
    this.categoryIds,
    this.circleId,
    this.hashtagId,
    this.hashtagIds,
    this.sideCategoryId,
  });

  @override State<SxResults> createState() => _SxResultsState();
}

class _SxResultsState extends State<SxResults> {
  static const int _viewGrid = 0;
  static const int _viewList = 1;

  List<ProductModel> products = [];
  List<CategoryModel> categories = [];
  List<CategoryModel> roots = [];
  List<CategoryModel> allCategories = [];
  List<Map<String, dynamic>> filters = [];
  List<Map<String, dynamic>> sideCircles = [];
  Map<String, dynamic> home = {};

  final Set<int> values = {};
  String sort = 'recommended';
  String? minPrice, maxPrice, minRating;
  int? selectedCategoryId;
  int? activeCircleId;
  int? resolvedSideCategoryId;
  bool loading = true;
  bool changingCategory = false;
  int viewMode = _viewGrid;

  late final ValueNotifier<int?> _activeCircleNotifier;
  late final ValueNotifier<int?> _selectedCategoryNotifier;
  late final ValueNotifier<List<ProductModel>> _visibleProductsNotifier;
  late final ValueNotifier<bool> _changingCategoryNotifier;

  @override
  void initState() {
    super.initState();
    activeCircleId = widget.circleId;
    _activeCircleNotifier = ValueNotifier<int?>(activeCircleId);
    _selectedCategoryNotifier = ValueNotifier<int?>(null);
    _visibleProductsNotifier = ValueNotifier<List<ProductModel>>(const []);
    _changingCategoryNotifier = ValueNotifier<bool>(false);
    load();
  }

  @override
  void dispose() {
    _activeCircleNotifier.dispose();
    _selectedCategoryNotifier.dispose();
    _visibleProductsNotifier.dispose();
    _changingCategoryNotifier.dispose();
    super.dispose();
  }

  void _resolveSideContext() {
    sideCircles = [];
    resolvedSideCategoryId = null;

    // When opening a result from a circle, the circle itself is the source
    // of truth. Do not let a stale/mismatched sideCategoryId make us resolve
    // a sibling side category under the same root.
    Map<String, dynamic>? matchedSide;
    final sides = sxMaps(home['side_categories']);

    if (widget.circleId != null && widget.circleId! > 0) {
      for (final side in sides) {
        final circles = sxMaps(side['circles']);
        if (circles.any((circle) => sxInt(circle['id']) == widget.circleId)) {
          matchedSide = side;
          break;
        }
      }
    } else if (widget.sideCategoryId != null &&
        widget.sideCategoryId! > 0) {
      for (final side in sides) {
        if (sxInt(side['id']) == widget.sideCategoryId) {
          matchedSide = side;
          break;
        }
      }
    }

    if (matchedSide == null) {
      resolvedSideCategoryId = widget.sideCategoryId;
      return;
    }

    resolvedSideCategoryId = sxInt(matchedSide['id']);
    // The root category is context for taxonomy only; it is not part of the
    // result scope and is deliberately not carried into product filtering.
    final circles = sxMaps(matchedSide['circles']);

    // Result-page circle rail belongs to the resolved side category only.
    sideCircles = circles
        .where(
          (circle) =>
              sxInt(circle['side_category_id']) == resolvedSideCategoryId,
        )
        .toList()
      ..sort((a, b) {
        final ao = sxInt(a['sort_order']);
        final bo = sxInt(b['sort_order']);
        return ao == bo
            ? sxInt(a['id']).compareTo(sxInt(b['id']))
            : ao.compareTo(bo);
      });
  }

  List<int> _entryCategoryIds() {
    // Side-category/circle results do not inherit their root category.
    // The side category (and circle when selected) is their own storefront
    // scope. Normal category entry points keep their explicit category IDs.
    if (widget.circleId != null ||
        widget.sideCategoryId != null ||
        resolvedSideCategoryId != null) {
      return <int>[
        ...?widget.categoryIds?.where((id) => id > 0),
        if (widget.categoryId != null && widget.categoryId! > 0)
          widget.categoryId!,
      ].toSet().toList()..sort();
    }

    final ids = <int>{};
    for (final id in widget.categoryIds ?? const <int>[]) {
      if (id > 0) ids.add(id);
    }
    if (widget.categoryId != null && widget.categoryId! > 0) {
      ids.add(widget.categoryId!);
    }
    return ids.toList()..sort();
  }

  List<int> _currentCategoryScopeIds() {
    // Filters and the result-page rail belong to the original entry scope.
    // Selecting a circle/category below it changes products only.
    return _entryCategoryIds();
  }

  void _buildCategoryRail() {
    allCategories = sxMaps(home['categories'])
        .map(CategoryModel.fromJson)
        .toList()
      ..sort(
        (a, b) => a.sortOrder == b.sortOrder
            ? a.id.compareTo(b.id)
            : a.sortOrder.compareTo(b.sortOrder),
      );
    roots = allCategories.where((x) => x.parentId == null).toList();

    // Side-category/circle results are scoped by the side taxonomy only.
    // Do not derive or display a normal catalog-category rail from the parent
    // root on this screen.
    final sideScoped = widget.circleId != null ||
        widget.sideCategoryId != null ||
        resolvedSideCategoryId != null;
    if (sideScoped) {
      categories = [];
      return;
    }

    final scopeIds = _currentCategoryScopeIds();
    if (scopeIds.isEmpty) {
      categories = roots;
      return;
    }

    final scope = scopeIds.toSet();
    final unique = <int, CategoryModel>{};
    for (final category in allCategories) {
      if (category.parentId != null && scope.contains(category.parentId)) {
        unique[category.id] = category;
      }
    }
    categories = unique.values.toList()
      ..sort(
        (a, b) => a.sortOrder == b.sortOrder
            ? a.id.compareTo(b.id)
            : a.sortOrder.compareTo(b.sortOrder),
      );
  }

  Future<void> _loadFiltersForCurrentScope() async {
    filters = [];

    final categoryIds = _currentCategoryScopeIds();
    final sideScoped = widget.circleId != null ||
        widget.sideCategoryId != null ||
        resolvedSideCategoryId != null;
    final effectiveSideCategoryId =
        resolvedSideCategoryId ?? widget.sideCategoryId;

    try {
      filters = await api.scopedFilters(
        categoryIds: sideScoped ? null : categoryIds,
        circleId: sideScoped ? activeCircleId : null,
        sideCategoryId: sideScoped ? effectiveSideCategoryId : null,
        hashtagIds: [
          if (widget.hashtagId != null && widget.hashtagId! > 0)
            widget.hashtagId!,
          ...?widget.hashtagIds,
        ],
      );
    } catch (_) {
      // Compatibility fallback applies only to normal catalog-category
      // results. Side/circle results must never fall back to the root taxonomy.
      if (!sideScoped && categoryIds.isNotEmpty) {
        try {
          filters = await api.categoryFiltersForCategories(
            categoryIds,
            includeDescendants: true,
          );
        } catch (_) {
          filters = [];
        }
      }
    }

    if (filters.isEmpty && !sideScoped && categoryIds.isNotEmpty) {
      try {
        filters = await api.categoryFiltersForCategories(
          categoryIds,
          includeDescendants: true,
        );
      } catch (_) {}
    }
  }

  Future<List<ProductModel>> _fetch() {
    // Circle results must remain inside their resolved side-category scope.
    // This is important both for a direct circle entry and when switching
    // between sibling circles on a side-category result screen.
    final effectiveSideCategoryId =
        resolvedSideCategoryId ?? widget.sideCategoryId;
    final sideScope = widget.circleId != null ||
        widget.sideCategoryId != null ||
        effectiveSideCategoryId != null ||
        activeCircleId != null;

    return api.feed(
      category: sideScope
          ? null
          : selectedCategoryId ??
              ((widget.categoryIds == null || widget.categoryIds!.isEmpty)
                  ? widget.categoryId
                  : null),
      categoryIds: sideScope
          ? null
          : (selectedCategoryId == null ? widget.categoryIds : null),
      circleId: activeCircleId,
      hashtagId: widget.hashtagId,
      hashtagIds: widget.hashtagIds,
      sideCategoryId: sideScope ? effectiveSideCategoryId : null,
      q: widget.query ?? '',
      filterValueIds: values.toList(),
      sort: sort,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minRating: minRating,
      currencyId: state.currencyId,
    );
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      home = await api.home();
      _resolveSideContext();
      selectedCategoryId = null;
      _selectedCategoryNotifier.value = null;
      activeCircleId = widget.circleId;
      _activeCircleNotifier.value = activeCircleId;

      await _loadFiltersForCurrentScope();
      products = await _fetch();
      _visibleProductsNotifier.value = products;
      _buildCategoryRail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(e, 'تعذر تحميل النتائج'))),
        );
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _selectCategory(int? id) async {
    if (_changingCategoryNotifier.value) return;

    // Category chips on the results page are product filters, not navigation.
    // Keep the rail and server-defined filter taxonomy unchanged.
    selectedCategoryId = id;
    activeCircleId = null;
    _selectedCategoryNotifier.value = id;
    _activeCircleNotifier.value = null;
    _changingCategoryNotifier.value = true;

    try {
      final next = await _fetch();
      if (mounted) {
        products = next;
        _visibleProductsNotifier.value = next;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(e, 'تعذر تحديث النتائج'))),
        );
      }
    } finally {
      if (mounted) _changingCategoryNotifier.value = false;
    }
  }

  Future<void> _selectSideCircle(int? id) async {
    if (_changingCategoryNotifier.value || activeCircleId == id) return;

    // Keep the result-page chrome mounted. Only the circle rail selection
    // and product pane react to this state change.
    if (mounted) {
      setState(() {
        activeCircleId = id;
        selectedCategoryId = null;
      });
    } else {
      activeCircleId = id;
      selectedCategoryId = null;
    }
    _activeCircleNotifier.value = id;
    _selectedCategoryNotifier.value = null;
    _changingCategoryNotifier.value = true;

    try {
      // Rebuild the filter sheet for the newly selected circle, not just
      // the parent side-category scope.
      await _loadFiltersForCurrentScope();
      final next = await _fetch();
      if (mounted) {
        products = next;
        _visibleProductsNotifier.value = next;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(e, 'تعذر تحديث المنتجات'))),
        );
      }
    } finally {
      if (mounted) _changingCategoryNotifier.value = false;
    }
  }

  Future<void> _reloadResults() async {
    if (mounted) setState(() => loading = true);
    try {
      products = await _fetch();
      _visibleProductsNotifier.value = products;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(e, 'تعذر تحديث المنتجات'))),
        );
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> filterSheet() async {
    if (filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد خيارات تصفية متاحة لهذا النطاق حاليًا')),
      );
      return;
    }

    final result = await showModalBottomSheet<SxFilterSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => SxFilterSheet(
        filters: filters,
        selected: values,
        minPrice: minPrice,
        maxPrice: maxPrice,
        minRating: minRating,
      ),
    );
    if (result == null) return;

    values
      ..clear()
      ..addAll(result.valueIds);
    minPrice = result.minPrice;
    maxPrice = result.maxPrice;
    minRating = result.minRating;
    await _reloadResults();
  }

  Future<void> recommendationSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) => SxSortSheet(current: sort),
    );
    if (result == null) return;
    setState(() => sort = result);
    await _reloadResults();
  }

  Future<void> discoveryToggle() async {
    final next = sort == 'popular' ? 'newest' : 'popular';
    setState(() => sort = next);
    await _reloadResults();
  }

  Future<void> priceToggle() async {
    final next = sort == 'price_desc' ? 'price_asc' : 'price_desc';
    setState(() => sort = next);
    await _reloadResults();
  }

  String get _sortLabel {
    switch (sort) {
      case 'popular': return 'الأكثر انتشاراً';
      case 'rating_desc': return 'الأعلى تقييماً';
      case 'newest': return 'الأحدث';
      case 'price_asc': return 'السعر ↑';
      case 'price_desc': return 'السعر ↓';
      default: return 'التوصية';
    }
  }

  String get _scopeLabel =>
      widget.query != null && widget.query!.trim().isNotEmpty
          ? widget.query!.trim()
          : widget.title;

  String _filterLabel(int id) {
    for (final f in filters) {
      for (final v in sxMaps(f['values'])) {
        if (sxInt(v['id']) == id) return sxText(v['label'], 'فلتر');
      }
    }
    return 'فلتر';
  }

  @override
  Widget build(BuildContext context) {
    final filterCount = values.length +
        (minPrice != null ? 1 : 0) +
        (maxPrice != null ? 1 : 0) +
        (minRating != null ? 1 : 0);

    if (loading && products.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _ResultsTopBar(
              title: _scopeLabel,
              viewMode: viewMode,
              onViewMode: () => setState(() => viewMode = (viewMode + 1) % 2),
              onBack: () => Navigator.pop(context),
              onSearch: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SxSearchScreen()),
              ),
              onWishlist: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SxWishlistScreen()),
              ),
            ),
            const Expanded(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _ResultHeaderDelegate(
              // Keep the visible toolbar at 58px and add Android's status-bar
              // inset instead of forcing SafeArea to shrink the toolbar.
              height: 58 + MediaQuery.of(context).padding.top,
              child: _ResultsTopBar(
                title: _scopeLabel,
                viewMode: viewMode,
                onViewMode: () => setState(() => viewMode = (viewMode + 1) % 2),
                onBack: () => Navigator.pop(context),
                onSearch: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SxSearchScreen()),
                ),
                onWishlist: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SxWishlistScreen()),
                ),
              ),
            ),
          ),
          // A parent side-category may show its child circles.
          // A direct circle entry must NOT show its sibling circles or a
          // normal category rail; its products are the result scope itself.
          if (widget.circleId == null && sideCircles.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ResultHeaderDelegate(
                height: 94,
                child: ValueListenableBuilder<int?>(
                  valueListenable: _activeCircleNotifier,
                  builder: (context, selectedCircle, _) => _ResultsCircleRail(
                    circles: sideCircles,
                    selected: selectedCircle,
                    onSelected: _selectSideCircle,
                  ),
                ),
              ),
            )
          else if (widget.sideCategoryId == null &&
              categories.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ResultHeaderDelegate(
                height: 94,
                child: ValueListenableBuilder<int?>(
                  valueListenable: _selectedCategoryNotifier,
                  builder: (context, selectedCategory, _) =>
                      _ResultsCategoryRail(
                        categories: categories,
                        selected: selectedCategory,
                        onSelected: _selectCategory,
                      ),
                ),
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ResultHeaderDelegate(
              height: 56,
              child: _ResultsFilterBar(
                filterCount: filterCount,
                priceDescending: sort == 'price_desc',
                discoveryLabel: sort == 'newest' ? 'الأحدث' : 'الأكثر انتشاراً',
                onRecommendation: recommendationSheet,
                onDiscovery: discoveryToggle,
                onPrice: priceToggle,
                onFilter: filterSheet,
              ),
            ),
          ),

          if (filterCount > 0)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 39,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                  children: [
                    const SxPill(
                      text: 'فلاتر',
                      background: Colors.black,
                      foreground: Colors.white,
                    ),
                    for (final id in values)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: SxPill(text: _filterLabel(id)),
                      ),
                    if (minPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: SxPill(text: 'من ' + minPrice!),
                      ),
                    if (maxPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: SxPill(text: 'إلى ' + maxPrice!),
                      ),
                    if (minRating != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: SxPill(text: minRating! + ' ★ فأعلى'),
                      ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: ValueListenableBuilder<List<ProductModel>>(
              valueListenable: _visibleProductsNotifier,
              builder: (context, visibleProducts, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _changingCategoryNotifier,
                  builder: (context, isChanging, _) {
                    return Stack(
                      children: [
                        viewMode == _viewList
                            ? _ResultsList(products: visibleProducts)
                            : SxProductGrid(
                                products: visibleProducts,
                                masonry: false,
                                displaySettings:
                                    home['product_card_settings'] is Map
                                        ? Map<String, dynamic>.from(
                                            home['product_card_settings'] as Map,
                                          )
                                        : null,
                              ),
                        if (isChanging)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  _ResultHeaderDelegate({required this.height, required this.child});
  @override double get minExtent => height;
  @override double get maxExtent => height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Material(color: Colors.white, elevation: overlapsContent ? .55 : 0, child: child);
  @override bool shouldRebuild(covariant _ResultHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

class _ResultsTopBar extends StatelessWidget {
  final String title;
  final int viewMode;
  final VoidCallback onViewMode;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onWishlist;

  const _ResultsTopBar({
    required this.title,
    required this.viewMode,
    required this.onViewMode,
    required this.onBack,
    required this.onSearch,
    required this.onWishlist,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 2, 6, 2),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: SxCircleIcon(
                icon: Icons.favorite_border,
                onTap: onWishlist,
              ),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: 'تغيير طريقة العرض',
                onPressed: onViewMode,
                icon: Icon(
                  viewMode == _SxResultsState._viewList
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                  size: 21,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 39,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFCFCFCF),
                      width: .8,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Container(
                        width: 39,
                        height: double.infinity,
                        color: Colors.black,
                        child: const Icon(
                          Icons.search,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              title.isEmpty ? 'ابحث عن المنتجات' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 7),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: 'رجوع',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


class _ResultsCircleRail extends StatelessWidget {
  final List<Map<String, dynamic>> circles;
  final int? selected;
  final Future<void> Function(int?) onSelected;

  const _ResultsCircleRail({
    required this.circles,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Column(
      children: [
        const SizedBox(height: 2),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: circles.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (i == 0) {
                return _ResultsCategoryChip(
                  name: 'الكل',
                  image: null,
                  selected: selected == null,
                  onTap: () => onSelected(null),
                );
              }
              final row = circles[i - 1];
              return _ResultsCategoryChip(
                name: sxText(row['name']),
                image: sxText(row['image_url']).isEmpty
                    ? null
                    : sxText(row['image_url']),
                selected: sxInt(row['id']) == selected,
                onTap: () => onSelected(sxInt(row['id'])),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ResultsCategoryRail extends StatelessWidget {
  final List<CategoryModel> categories;
  final int? selected;
  final Future<void> Function(int?) onSelected;

  const _ResultsCategoryRail({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Column(
      children: [
        const SizedBox(height: 2),
        SizedBox(
          height: 84,
          child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: categories.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            if (i == 0) {
              return _ResultsCategoryChip(
                name: 'الكل',
                image: null,
                selected: selected == null,
                onTap: () => onSelected(null),
              );
            }
            final row = categories[i - 1];
            return _ResultsCategoryChip(
              name: row.name,
              image: row.iconUrl,
              selected: row.id == selected,
              onTap: () => onSelected(row.id),
            );
          },
        ),
          ),
        ],
      ),
    );
}

class _ResultsCategoryChip extends StatelessWidget {
  final String name;
  final String? image;
  final bool selected;
  final VoidCallback onTap;

  const _ResultsCategoryChip({
    required this.name,
    required this.image,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              shape: image == null ? BoxShape.rectangle : BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.black : const Color(0xFFE0E0E0),
                width: selected ? 2.0 : .6,
              ),
              borderRadius: image == null ? BorderRadius.circular(3) : null,
            ),
            child: image == null
                ? const Center(child: Icon(Icons.apps_outlined, size: 20))
                : SxImage(url: image, fit: BoxFit.cover),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              height: 1.03,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ResultsFilterBar extends StatelessWidget {
  final int filterCount;
  final bool priceDescending;
  final String discoveryLabel;
  final VoidCallback onRecommendation;
  final VoidCallback onDiscovery;
  final VoidCallback onPrice;
  final VoidCallback onFilter;

  const _ResultsFilterBar({
    required this.filterCount,
    required this.priceDescending,
    required this.discoveryLabel,
    required this.onRecommendation,
    required this.onDiscovery,
    required this.onPrice,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(color: Color(0xFFE7E7E7), width: .7),
        bottom: BorderSide(color: Color(0xFFE7E7E7), width: .7),
      ),
    ),
    child: Row(
      textDirection: TextDirection.rtl,
      children: [
        Expanded(child: _FilterButton('التوصية', Icons.keyboard_arrow_down, onRecommendation)),
        const SizedBox(width: 5),
        Expanded(child: _FilterButton(discoveryLabel, Icons.local_fire_department_outlined, onDiscovery)),
        const SizedBox(width: 5),
        Expanded(child: _FilterButton('السعر', priceDescending ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, onPrice)),
        const SizedBox(width: 5),
        Expanded(
          child: _FilterButton(
            filterCount > 0 ? 'تصفية ' + filterCount.toString() : 'تصفية',
            Icons.tune,
            onFilter,
          ),
        ),
      ],
    ),
  );
}

class _ResultsList extends StatelessWidget {
  final List<ProductModel> products;
  const _ResultsList({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 70),
        child: Center(
          child: Text('لا توجد منتجات مطابقة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
    }
    return Column(
      children: [
        for (final product in products)
          _ResultsListCard(key: ValueKey(product.id), product: product),
      ],
    );
  }
}

class _ResultsListCard extends StatelessWidget {
  final ProductModel product;
  const _ResultsListCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final old = sxDouble(product.oldPrice);
    final now = sxDouble(product.price);
    final discount = old > now && old > 0 ? ((1 - now / old) * 100).round() : 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 2, 6, 7),
      padding: const EdgeInsets.all(6),
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SxProductScreen(id: product.id)),
        ),
        child: SizedBox(
          height: 150,
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(
                width: 118,
                height: 138,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SxImage(url: product.image, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Expanded(
                        child: Text(
                          'SHEIN STYLE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const Icon(Icons.more_horiz, size: 15),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.22),
                    ),
                    const Spacer(),
                    Row(children: [
                      if (discount > 0)
                        Text(
                          '-' + discount.toString() + '%',
                          style: const TextStyle(color: ClientTheme.promo, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        product.price + ' ' + state.currencySymbol,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ]),
                    if (product.oldPrice != null && product.oldPrice!.isNotEmpty)
                      Text(
                        product.oldPrice! + ' ' + state.currencySymbol,
                        style: const TextStyle(fontSize: 9, color: ClientTheme.muted, decoration: TextDecoration.lineThrough),
                      ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.star, size: 13, color: Color(0xFFFFB400)),
                      const Text(' 4.8', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFD9D9D9)),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, size: 17),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String text; final IconData icon; final VoidCallback onTap;
  const _FilterButton(this.text, this.icon, this.onTap);
  @override Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 1), side: const BorderSide(color: Color(0xFFD2D2D2), width: .7), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 15), const SizedBox(width: 3), Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)))]),
  );
}

class _FilterHeader extends SliverPersistentHeaderDelegate {
  final Widget child; _FilterHeader({required this.child});
  @override double get minExtent => 52; @override double get maxExtent => 52;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: Colors.white, padding: const EdgeInsets.all(6), child: child);
  @override bool shouldRebuild(covariant _FilterHeader oldDelegate) => false;
}

String sxResultFilterName(Map<String, dynamic> filter) {
  final raw = sxText(filter['name']).trim();
  final key = raw.toLowerCase();
  const map = {
    'category': 'الفئات',
    'categories': 'الفئات',
    'product category': 'الفئات',
    'size': 'المقاس',
    'sizes': 'المقاس',
    'color': 'اللون',
    'colour': 'اللون',
    'material': 'الخامة',
    'details': 'التفاصيل',
    'type': 'النوع',
    'product type': 'نوع المنتج',
    'features': 'المميزات',
    'feature': 'المميزات',
    'style': 'الستايل',
    'occasion': 'المناسبة',
    'festivals': 'المناسبات',
    'pattern type': 'نوع النقشة',
  };
  return map[key] ?? (raw.isEmpty ? 'فلتر' : raw);
}

class SxFilterSelection {
  final Set<int> valueIds;
  final String? minPrice, maxPrice, minRating;
  const SxFilterSelection({required this.valueIds, this.minPrice, this.maxPrice, this.minRating});
}

class SxFilterSheet extends StatefulWidget {
  final List<Map<String, dynamic>> filters;
  final Set<int> selected;
  final String? minPrice, maxPrice, minRating;
  const SxFilterSheet({super.key, required this.filters, required this.selected, this.minPrice, this.maxPrice, this.minRating});
  @override State<SxFilterSheet> createState() => _SxFilterSheetState();
}

class _SxFilterSheetState extends State<SxFilterSheet> {
  late Set<int> values;
  late TextEditingController min, max;
  late String? rating;
  int selectedGroup = 0;

  @override
  void initState() {
    super.initState();
    values = {...widget.selected};
    min = TextEditingController(text: widget.minPrice ?? '');
    max = TextEditingController(text: widget.maxPrice ?? '');
    rating = widget.minRating;
  }

  @override
  void dispose() {
    min.dispose();
    max.dispose();
    super.dispose();
  }

  String _groupName(int index) {
    if (index < widget.filters.length) return sxResultFilterName(widget.filters[index]);
    if (index == widget.filters.length) return 'السعر';
    return 'التقييم';
  }

  int get _groupCount => widget.filters.length + 2;

  void _clear() {
    setState(() {
      values.clear();
      min.clear();
      max.clear();
      rating = null;
    });
  }

  Widget _choice(int id, String label) {
    final active = values.contains(id);
    return InkWell(
      onTap: () => setState(() {
        if (active) {
          values.remove(id);
        } else {
          values.add(id);
        }
      }),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        constraints: const BoxConstraints(minWidth: 82, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.black : const Color(0xFFF5F5F5),
          border: Border.all(color: active ? Colors.black : const Color(0xFFE3E3E3)),
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : Colors.black,
        )),
      ),
    );
  }

  Widget _valuesContent() {
    if (selectedGroup == widget.filters.length) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 20),
          children: [
            const Text('نطاق السعر', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(child: TextField(controller: min, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'من'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'إلى'))),
            ]),
          ],
        ),
      );
    }

    if (selectedGroup == widget.filters.length + 1) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 20),
          children: [
            const Text('التقييم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            for (final value in const ['4', '3', '2', '1'])
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: InkWell(
                  onTap: () => setState(() => rating = rating == value ? null : value),
                  child: Container(
                    height: 43,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: rating == value ? const Color(0xFFF0F0F0) : Colors.white,
                      border: Border.all(color: rating == value ? Colors.black : const Color(0xFFE5E5E5)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      children: [
                        Text('& up', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: rating == value ? Colors.black : Colors.black87)),
                        const SizedBox(width: 8),
                        for (int i = 0; i < int.parse(value); i++) const Icon(Icons.star, size: 17),
                        const Spacer(),
                        if (rating == value) const Icon(Icons.check, size: 17),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final rows = sxMaps(widget.filters[selectedGroup]['values']);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 20),
        children: [
          Text(_groupName(selectedGroup), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 8,
            children: [
              for (final row in rows) _choice(sxInt(row['id']), sxText(row['label'])),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      maxChildSize: .97,
      minChildSize: .62,
      builder: (_, __) => Column(
        children: [
          const _Handle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 9),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                const Expanded(child: Text('تصفية', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
                TextButton(onPressed: _clear, child: const Text('مسح الكل')),
              ],
            ),
          ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Container(
                    width: 122,
                    color: const Color(0xFFF4F4F4),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 6),
                      itemCount: _groupCount,
                      itemBuilder: (_, index) {
                        final active = index == selectedGroup;
                        return InkWell(
                          onTap: () => setState(() => selectedGroup = index),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 58),
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                            decoration: BoxDecoration(
                              color: active ? Colors.white : const Color(0xFFF4F4F4),
                              border: Border(
                                right: BorderSide(color: active ? Colors.black : Colors.transparent, width: 3),
                                bottom: const BorderSide(color: Color(0xFFE9E9E9), width: .5),
                              ),
                            ),
                            alignment: Alignment.centerRight,
                            child: Text(
                              _groupName(index),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w900 : FontWeight.w500),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(child: _valuesContent()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(49), side: const BorderSide(color: Color(0xFFD0D0D0)), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                    child: const Text('مسح', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, SxFilterSelection(
                      valueIds: values,
                      minPrice: min.text.trim().isEmpty ? null : min.text.trim(),
                      maxPrice: max.text.trim().isEmpty ? null : max.text.trim(),
                      minRating: rating,
                    )),
                    style: FilledButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size.fromHeight(49), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                    child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class SxSortSheet extends StatelessWidget {
  final String current;
  const SxSortSheet({super.key, required this.current});
  @override
  Widget build(BuildContext context) {
    const options = [('popular', 'الأكثر انتشاراً'), ('rating_desc', 'الأعلى تقييماً')];
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Handle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 5, 16, 8),
            child: Align(alignment: Alignment.centerRight, child: Text('التوصية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          ),
          for (final x in options)
            ListTile(
              title: Text(x.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              trailing: current == x.$1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, x.$1),
            ),
          const SizedBox(height: 5),
        ]),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFBEBEBE), borderRadius: BorderRadius.circular(10))));
}

class SxSearchScreen extends StatefulWidget {
  const SxSearchScreen({super.key});
  @override State<SxSearchScreen> createState() => _SxSearchScreenState();
}

class _SxSearchScreenState extends State<SxSearchScreen> {
  final search = TextEditingController();
  bool loading = false;

  Future<void> submit(String value) async {
    final q = value.trim();
    if (q.isEmpty) return;
    setState(() => loading = true);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SxResults(title: q, query: q)),
    );
    if (mounted) setState(() => loading = false);
  }

  void useSuggestion(String value) {
    search
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    submit(value);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 7, 6, 7),
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_forward_ios, size: 17),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SxSearchBar(
                    controller: search,
                    hint: 'ابحث عن منتج أو علامة',
                    autofocus: true,
                    onSubmitted: submit,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.camera_alt_outlined, size: 20),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                const SxSectionTitle(title: 'عمليات البحث الشائعة'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final label in const ['جينز', 'فساتين', 'أحذية', 'ملابس نسائية', 'مقاسات كبيرة'])
                      GestureDetector(
                        onTap: () => useSuggestion(label),
                        child: SxPill(text: label),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const SxSectionTitle(title: 'اكتشف'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: const [
                    SxPill(text: 'الأكثر مبيعًا'),
                    SxPill(text: 'وصل حديثًا'),
                    SxPill(text: 'العروض'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class SxProductScreen extends StatefulWidget {
  final int id;
  const SxProductScreen({super.key, required this.id});
  @override State<SxProductScreen> createState() => _SxProductScreenState();
}

class _SxProductScreenState extends State<SxProductScreen> {
  Map<String, dynamic> data = {}; bool loading = true; int page = 0; int? colorId, sizeId;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final d = await api.product(widget.id, currencyId: state.currencyId);
      data = Map<String, dynamic>.from(d['item'] is Map ? d['item'] : d);
      final variants = sxMaps(data['variants']);
      if (variants.isNotEmpty) {
        final c = sxInt(variants.first['color_id']); final s = sxInt(variants.first['size_id']);
        colorId = c == 0 ? null : c; sizeId = s == 0 ? null : s;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e))));
    }
    if (mounted) setState(() => loading = false);
  }
  List<Map<String, dynamic>> media() {
    final all = sxMaps(data['media']);
    if (colorId == null) return all;
    return [...all.where((x) => x['color_id'] == null), ...all.where((x) => sxInt(x['color_id']) == colorId)];
  }
  Map<int, String> optionNames(String key) {
    final out = <int, String>{};
    for (final o in sxMaps(data['options'])) for (final v in sxMaps(o['values'])) {
      final id = sxInt(v[key]); if (id > 0) out[id] = sxText(v['label']);
    }
    return out;
  }
  int? selectedVariant() {
    final variants = sxMaps(data['variants']);
    for (final v in variants) {
      final c = colorId == null || sxInt(v['color_id']) == colorId;
      final s = sizeId == null || sxInt(v['size_id']) == sizeId;
      if (c && s) return sxInt(v['id']);
    }
    return variants.isEmpty ? null : sxInt(variants.first['id']);
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final p = Map<String, dynamic>.from((data['product'] as Map?) ?? {});
    final imgs = media(); final colors = optionNames('color_id'); final sizes = optionNames('size_id');
    final price = sxText(p['price'], sxText(p['base_price_sar'], '0')); final old = sxText(p['compare_at_price']);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: false, child: Column(children: [
        Expanded(child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true, backgroundColor: Colors.white, automaticallyImplyLeading: false,
            title: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_ios, size: 18)),
              const Spacer(), IconButton(onPressed: () {}, icon: const Icon(Icons.share_outlined)), IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
            ]),
          ),
          SliverToBoxAdapter(child: SxGallery(rows: imgs, page: page, changed: (v) => setState(() => page = v))),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(sxText(p['name'], 'منتج'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, height: 1.3))),
                const SxPill(text: 'علامة تجارية', background: Colors.black, foreground: Colors.white),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text(price + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                if (old.isNotEmpty) ...[const SizedBox(width: 8), Text(old + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 11, color: ClientTheme.muted, decoration: TextDecoration.lineThrough))],
                const Spacer(), const Icon(Icons.star, size: 15, color: Color(0xFFFFB400)), const Text(' 4.8', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
              ]),
              if (old.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: SxPill(text: 'توفير كبير', background: Color(0xFFFFEEF2), foreground: ClientTheme.promo)),
              const SizedBox(height: 13),
              const _Trust(),
              if (colors.isNotEmpty) ...[
                const SizedBox(height: 17),
                const Text('اللون', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(spacing: 7, children: colors.entries.map((e) => GestureDetector(
                  onTap: () => setState(() { colorId = e.key; page = 0; }),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: colorId == e.key ? Colors.black : ClientTheme.border, width: colorId == e.key ? 2 : .7)),
                    child: Container(width: 35, height: 35, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFBDBDBD)), child: colorId == e.key ? const Icon(Icons.check, color: Colors.white, size: 15) : null),
                  ),
                )).toList()),
              ],
              if (sizes.isNotEmpty) ...[
                const SizedBox(height: 17),
                Row(children: [
                  const Expanded(child: Text('المقاس', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900))),
                  TextButton(onPressed: () => showModalBottomSheet(context: context, backgroundColor: Colors.white, builder: (_) => const _SizeGuide()), child: const Text('دليل المقاسات')),
                ]),
                Wrap(spacing: 7, runSpacing: 7, children: sizes.entries.map((e) => ChoiceChip(
                  selected: sizeId == e.key, label: Text(e.value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), onSelected: (_) => setState(() => sizeId = e.key),
                )).toList()),
              ],
              const SizedBox(height: 17),
              _Accordion(title: 'تفاصيل المنتج', text: [
                sxText(p['description']),
                if (sxText(p['material']).isNotEmpty) 'الخامة: ' + sxText(p['material']),
                if (sxText(p['care_instructions']).isNotEmpty) 'العناية: ' + sxText(p['care_instructions']),
                'SKU: ' + sxText(p['sku']),
              ].where((x) => x.isNotEmpty).join('\\n\\n')),
              const _Accordion(title: 'الشحن والإرجاع', text: 'تظهر تفاصيل الشحن والإرجاع حسب عنوانك والسوق المختار.'),
              const _Accordion(title: 'المراجعات', text: 'التقييم الحالي 4.8 من 5.'),
            ]),
          )),
        ])),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: ClientTheme.border))),
          child: Row(children: [
            SizedBox(width: 92, child: Text(price + ' ' + state.currencySymbol, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
            Expanded(child: OutlinedButton(onPressed: add, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(47), side: const BorderSide(color: Colors.black), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), child: const Text('أضف إلى الحقيبة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)))),
            const SizedBox(width: 6),
            Expanded(child: FilledButton(onPressed: buy, style: FilledButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size.fromHeight(47), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), child: const Text('اشترِ الآن', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)))),
          ]),
        )),
      ])),
    );
  }
  Future<void> add() async {
    final v = selectedVariant(); if (v == null) return;
    try {
      await api.addCart(v);
      final c = await api.cart(currencyId: state.currencyId); _CartBadge.value.value = sxMaps(c['item']?['items']).length;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى الحقيبة')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
  }
  Future<void> buy() async { await add(); if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const SxCartScreen())); }
}

class SxGallery extends StatelessWidget {
  final List<Map<String, dynamic>> rows; final int page; final ValueChanged<int> changed;
  const SxGallery({super.key, required this.rows, required this.page, required this.changed});
  @override Widget build(BuildContext context) {
    final data = rows.isEmpty ? [{}] : rows;
    return Column(children: [
      AspectRatio(aspectRatio: .83, child: Stack(children: [
        PageView.builder(itemCount: data.length, onPageChanged: changed, itemBuilder: (_, i) => SxImage(url: data[i]['url'])),
        if (data.length > 1) Positioned(right: 10, bottom: 10, child: SxPill(text: (page + 1).toString() + '/' + data.length.toString(), background: Colors.black54, foreground: Colors.white)),
      ])),
      if (data.length > 1) SizedBox(height: 78, child: ListView.separated(
        reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(7), itemCount: data.length, separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Container(width: 62, decoration: BoxDecoration(border: Border.all(color: i == page ? Colors.black : ClientTheme.border, width: i == page ? 1.5 : .7)), child: SxImage(url: data[i]['url'])),
      )),
    ]);
  }
}

class _Trust extends StatelessWidget {
  const _Trust();
  @override Widget build(BuildContext context) => Container(color: ClientTheme.soft, padding: const EdgeInsets.symmetric(vertical: 10), child: const Row(children: [
    Expanded(child: _TrustItem(Icons.local_shipping_outlined, 'شحن حسب العنوان')),
    Expanded(child: _TrustItem(Icons.assignment_return_outlined, 'إرجاع وفق السياسة')),
    Expanded(child: _TrustItem(Icons.lock_outline, 'دفع آمن')),
  ]));
}
class _TrustItem extends StatelessWidget {
  final IconData icon; final String text;
  const _TrustItem(this.icon, this.text);
  @override Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 15), const SizedBox(width: 4), Flexible(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700)))]);
}
class _Accordion extends StatelessWidget {
  final String title, text;
  const _Accordion({required this.title, required this.text});
  @override Widget build(BuildContext context) => ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)), children: [Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(bottom: 9), child: Text(text, style: const TextStyle(fontSize: 10.5, height: 1.5))))]);
}
class _SizeGuide extends StatelessWidget {
  const _SizeGuide();
  @override Widget build(BuildContext context) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(15, 9, 15, 18), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const _Handle(), const Text('دليل المقاسات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
    const Text('اختر المقاس اعتمادًا على القياسات المتاحة لهذا المنتج.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, height: 1.5)),
    const SizedBox(height: 12), Container(color: ClientTheme.soft, padding: const EdgeInsets.all(10), child: const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Text('المقاس'), Text('الصدر'), Text('الخصر')])),
  ])));
}

double _sxTrendNumber(
  Map<String, dynamic> ui,
  String key,
  double fallback,
) => sxDouble(ui[key], fallback);

Color _sxTrendHex(
  dynamic value,
  Color fallback,
) => sxColor(value, fallback);

FontWeight _sxTrendWeight(
  dynamic value,
  FontWeight fallback,
) {
  final fallbackNumber = fallback == FontWeight.w900
      ? 900
      : fallback == FontWeight.w800
          ? 800
          : fallback == FontWeight.w700
              ? 700
              : fallback == FontWeight.w600
                  ? 600
                  : fallback == FontWeight.w500
                      ? 500
                      : 400;
  final n = sxInt(value, fallbackNumber);
  if (n >= 900) return FontWeight.w900;
  if (n >= 800) return FontWeight.w800;
  if (n >= 700) return FontWeight.w700;
  if (n >= 600) return FontWeight.w600;
  if (n >= 500) return FontWeight.w500;
  return FontWeight.w400;
}

BoxFit _sxTrendFit(dynamic value) {
  switch (sxText(value)) {
    case 'contain':
      return BoxFit.contain;
    case 'fill':
      return BoxFit.fill;
    default:
      return BoxFit.cover;
  }
}

TextAlign _sxTrendTextAlign(dynamic value, [TextAlign fallback = TextAlign.center]) {
  switch (sxText(value).toLowerCase()) {
    case 'right':
    case 'end':
      return TextAlign.right;
    case 'left':
    case 'start':
      return TextAlign.left;
    case 'center':
      return TextAlign.center;
    default:
      return fallback;
  }
}

Alignment _sxTrendAlignment(dynamic value, [Alignment fallback = Alignment.center]) {
  switch (sxText(value).toLowerCase()) {
    case 'right':
    case 'end':
      return Alignment.centerRight;
    case 'left':
    case 'start':
      return Alignment.centerLeft;
    case 'center':
      return Alignment.center;
    default:
      return fallback;
  }
}

TextSpan _sxTrendTitleSpan(
  String title,
  Map<String, dynamic> ui, {
  Color fallbackTitleColor = Colors.white,
  Color fallbackHashColor = Colors.white,
}) {
  final raw = title.trim();
  final clean = raw.startsWith('#') ? raw.substring(1) : raw;
  final hash = sxText(ui['title_hash_text'], '#');
  return TextSpan(
    children: [
      if (ui['show_title_hash'] != false)
        TextSpan(
          text: hash.isEmpty ? '#' : hash,
          style: TextStyle(
            color: _sxTrendHex(ui['title_hash_color'], fallbackHashColor),
          ),
        ),
      TextSpan(
        text: clean,
        style: TextStyle(
          color: _sxTrendHex(ui['title_color'], fallbackTitleColor),
        ),
      ),
    ],
  );
}

class SxTrendsScreen extends StatefulWidget {
  const SxTrendsScreen({super.key});

  @override
  State<SxTrendsScreen> createState() => _SxTrendsScreenState();
}

class _SxTrendsScreenState extends State<SxTrendsScreen> {
  final PageController _trendPager = PageController(viewportFraction: .82);
  final ScrollController _scroll = ScrollController();

  List<Map<String, dynamic>> trends = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> trendTags = <Map<String, dynamic>>[];
  List<ProductModel> picks = <ProductModel>[];
  Map<String, dynamic> ui = <String, dynamic>{};
  Map<String, dynamic> productCardSettings = <String, dynamic>{};

  int trendIndex = 0;
  int? hashtagId;
  bool loading = true;
  bool loadingPicks = false;
  bool _collapsedHeader = false;
  double _pullExtent = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_handleScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_handleScroll);
    _trendPager.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!mounted || ui['header_collapse_enabled'] == false) return;
    final threshold = _sxTrendNumber(ui, 'header_collapse_offset', 46);
    final next = _scroll.hasClients && _scroll.offset >= threshold;
    if (next != _collapsedHeader) {
      setState(() => _collapsedHeader = next);
    }
  }

  Future<void> _load() async {
    try {
      final payload = await api.trendsPage();
      final nextTrends = sxMaps(payload['items']);
      final rawTags = sxMaps(payload['hashtags']);
      final byId = <int, Map<String, dynamic>>{};
      for (final tag in rawTags) {
        final id = sxInt(tag['id']);
        if (id > 0) byId[id] = tag;
      }
      final nextTags = byId.values.toList();

      final nextUi = payload['settings'] is Map
          ? Map<String, dynamic>.from(payload['settings'] as Map)
          : <String, dynamic>{};
      final nextProductCardSettings = payload['product_card_settings'] is Map
          ? Map<String, dynamic>.from(
              payload['product_card_settings'] as Map,
            )
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        trends = nextTrends;
        trendTags = nextTags.isNotEmpty
            ? nextTags
            : nextTrends
                .map((trend) => trend['hashtag'])
                .whereType<Map>()
                .map((tag) => Map<String, dynamic>.from(tag))
                .toList();
        ui = nextUi;
        productCardSettings = nextProductCardSettings;
        trendIndex = nextTrends.isEmpty ? 0 : 0;
        loading = false;
        _collapsedHeader = false;
        _pullExtent = 0;
      });

      await _loadPicks();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        _pullExtent = 0;
      });
    }
  }

  Future<void> _loadPicks() async {
    if (mounted) setState(() => loadingPicks = true);
    try {
      final rows = hashtagId == null
          ? await api.feed(
              currencyId: state.currencyId,
              sort: 'popular',
              discoveryTab: 'trends',
            )
          : await api.feed(
              currencyId: state.currencyId,
              sort: 'popular',
              hashtagId: hashtagId,
            );

      if (!mounted) return;
      setState(() => picks = rows);
    } catch (_) {
      if (mounted) setState(() => picks = <ProductModel>[]);
    } finally {
      if (mounted) setState(() => loadingPicks = false);
    }
  }

  Future<void> _selectHashtag(int? id) async {
    if (hashtagId == id) return;
    setState(() => hashtagId = id);
    await _loadPicks();
  }

  String _tagText(Map<String, dynamic> tag) {
    final value = sxText(tag['display_name'], '#' + sxText(tag['name']));
    return value.startsWith('#') ? value : '#' + value;
  }

  String _heroTitle(Map<String, dynamic> trend) {
    final raw = sxText(
      (trend['hashtag'] as Map?)?['display_name'],
      '#Trending',
    );
    return raw.startsWith('#') ? raw.substring(1) : raw;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (ui['pull_enabled'] == false) return false;

    if (notification is OverscrollNotification &&
        notification.depth == 0 &&
        notification.overscroll < 0) {
      final maxPull = _sxTrendNumber(ui, 'pull_distance', 70) * 1.65;
      final next =
          (_pullExtent + (-notification.overscroll)).clamp(0.0, maxPull);
      if ((next - _pullExtent).abs() > .5 && mounted) {
        setState(() => _pullExtent = next.toDouble());
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.depth == 0 &&
        notification.metrics.pixels > 0 &&
        _pullExtent > 0) {
      setState(() => _pullExtent = 0);
    } else if (notification is ScrollEndNotification &&
        notification.depth == 0 &&
        _pullExtent > 0 &&
        mounted) {
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (mounted && !loading) setState(() => _pullExtent = 0);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 360.0).clamp(.86, 1.15).toDouble();
    final heroHeight =
        (_sxTrendNumber(ui, 'hero_height', 238) * scale).clamp(218.0, 380.0);
    final cardHeight =
        (_sxTrendNumber(ui, 'hero_card_height', 168) * scale)
            .clamp(135.0, 240.0);
    final cardWidth =
        (_sxTrendNumber(ui, 'hero_card_width', 282) * scale)
            .clamp(210.0, width - 22.0)
            .toDouble();
    final contentRadius = _sxTrendNumber(ui, 'content_top_radius', 14);
    final picksExtent =
        (_sxTrendNumber(ui, 'picks_card_extent', 350) * scale)
            .clamp(300.0, 520.0);
    final compactHeaderHeight =
        _sxTrendNumber(ui, 'compact_header_height', 58) * scale;

    return Scaffold(
      backgroundColor:
          _sxTrendHex(ui['page_background_color'], Colors.white),
      body: Stack(
        children: [
          RefreshIndicator(
            color: _sxTrendHex(
              ui['pull_indicator_color'],
              Colors.black,
            ),
            backgroundColor: _sxTrendHex(
              ui['pull_background_color'],
              Colors.white,
            ),
            displacement: _sxTrendNumber(ui, 'pull_height', 48),
            strokeWidth: 2.2,
            onRefresh: _load,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _TrendsHero(
                      trends: trends,
                      pageController: _trendPager,
                      currentIndex: trendIndex,
                      height: heroHeight.toDouble(),
                      cardWidth: cardWidth,
                      cardHeight: cardHeight,
                      ui: ui,
                      titleFor: _heroTitle,
                      onPageChanged: (index) {
                        if (!mounted) return;
                        setState(() => trendIndex = index);
                      },
                      onSearch: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SxSearchScreen(),
                        ),
                      ),
                      onWishlist: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SxWishlistScreen(),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(contentRadius),
                        ),
                      ),
                      child: Column(
                        children: [
                          _TrendHashtagStrip(
                            tags: trendTags,
                            selectedId: hashtagId,
                            ui: ui,
                            tagText: _tagText,
                            onMenu: () {
                              showModalBottomSheet<void>(
                                context: context,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(18),
                                  ),
                                ),
                                builder: (_) => SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      10,
                                      16,
                                      20,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD6D6D6),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        const SizedBox(height: 15),
                                        const Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            'استكشف الترندات',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        for (final tag in trendTags)
                                          ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              _tagText(tag),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            trailing: const Icon(
                                              Icons.chevron_left,
                                              size: 18,
                                            ),
                                            onTap: () {
                                              Navigator.pop(context);
                                              _selectHashtag(
                                                sxInt(tag['id']),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            onSelect: _selectHashtag,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      6 * scale,
                      8 * scale,
                      6 * scale,
                      20 * scale,
                    ),
                    sliver: loadingPicks
                        ? const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 34),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          )
                        : picks.isEmpty
                            ? const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 34),
                                  child: Center(
                                    child: Text(
                                      'لا توجد منتجات لهذا الترند حالياً',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ClientTheme.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : SliverToBoxAdapter(
                                child: Container(
                                  color: _sxTrendHex(
                                    ui['picks_section_background_color'],
                                    const Color(0xFFF3F3F3),
                                  ),
                                  padding: EdgeInsets.only(
                                    top: 6 * scale,
                                    bottom: 6 * scale,
                                  ),
                                  child: GridView.builder(
                                    primary: false,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    itemCount: picks.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 4 * scale,
                                      mainAxisSpacing: 5 * scale,
                                      mainAxisExtent: picksExtent,
                                    ),
                                    itemBuilder: (_, i) => Container(
                                      color: Colors.white,
                                      child: _TrendProductTile(
                                        product: picks[i],
                                        hashtag: hashtagId == null
                                            ? null
                                            : trendTags.firstWhere(
                                                (x) =>
                                                    sxInt(x['id']) == hashtagId,
                                                orElse: () =>
                                                    <String, dynamic>{},
                                              ),
                                        ui: ui,
                                        displaySettings: productCardSettings,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
          if (_collapsedHeader && ui['header_collapse_enabled'] != false)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 7,
                color: Colors.black,
                child: SafeArea(
                  bottom: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: compactHeaderHeight,
                    padding: EdgeInsets.symmetric(
                      horizontal: _sxTrendNumber(
                        ui,
                        'search_horizontal_padding',
                        10,
                      ) * scale,
                      vertical: 5 * scale,
                    ),
                    child: _TrendCompactHeader(
                      ui: ui,
                      onSearch: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SxSearchScreen(),
                        ),
                      ),
                      onWishlist: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SxWishlistScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (ui['pull_enabled'] != false && _pullExtent > 1)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 80),
                    opacity: (_pullExtent / 48).clamp(.25, 1.0).toDouble(),
                    child: Container(
                      height:
                          (_pullExtent * .72).clamp(1.0, 74.0).toDouble(),
                      color: _sxTrendHex(
                        ui['pull_background_color'],
                        Colors.white,
                      ),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        _pullExtent >=
                                _sxTrendNumber(ui, 'pull_distance', 70)
                            ? sxText(
                                ui['pull_release_text'],
                                'حرر للتحديث',
                              )
                            : sxText(
                                ui['pull_text'],
                                'اسحب للتحديث',
                              ),
                        style: TextStyle(
                          color: _sxTrendHex(
                            ui['pull_text_color'],
                            const Color(0xFF555555),
                          ),
                          fontSize:
                              _sxTrendNumber(ui, 'pull_font_size', 11),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendCompactHeader extends StatelessWidget {
  final Map<String, dynamic> ui;
  final VoidCallback onSearch;
  final VoidCallback onWishlist;

  const _TrendCompactHeader({
    required this.ui,
    required this.onSearch,
    required this.onWishlist,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 360.0).clamp(.86, 1.15).toDouble();
    final horizontal = _sxTrendNumber(ui, 'search_horizontal_padding', 10) * scale;
    final ratio = _sxTrendNumber(ui, 'search_width_ratio', .72);
    final available = width - horizontal * 2;
    final searchWidth = (available * ratio).clamp(190.0, available - 92.0);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          SizedBox(
            width: searchWidth,
            child: GestureDetector(
              onTap: onSearch,
              child: Container(
                height: _sxTrendNumber(ui, 'search_height', 42) * scale,
                decoration: BoxDecoration(
                  color: _sxTrendHex(
                    ui['search_background_color'],
                    Colors.white,
                  ),
                  borderRadius: BorderRadius.circular(
                    _sxTrendNumber(ui, 'search_radius', 13),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: _sxTrendHex(
                        ui['search_icon_color'],
                        Colors.black,
                      ),
                      size: _sxTrendNumber(ui, 'search_icon_size', 22) * scale,
                    ),
                    Container(
                      width: _sxTrendNumber(
                        ui,
                        'search_divider_width',
                        1,
                      ),
                      height: 21 * scale,
                      margin: EdgeInsets.symmetric(horizontal: 8 * scale),
                      color: _sxTrendHex(
                        ui['search_divider_color'],
                        const Color(0xFFDDDDDD),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        sxText(ui['search_hint'], 'فساتين'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _sxTrendHex(
                            ui['search_text_color'],
                            const Color(0xFF222222),
                          ),
                          fontSize:
                              _sxTrendNumber(ui, 'search_font_size', 13),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            sxText(ui['logo_text'], 'Trends'),
            style: TextStyle(
              color: _sxTrendHex(ui['logo_color'], Colors.white),
              fontSize: _sxTrendNumber(ui, 'logo_font_size', 26) * scale,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: _sxTrendNumber(ui, 'logo_letter_spacing', -1.4),
            ),
          ),
          SizedBox(width: 4 * scale),
        ],
      ),
    );
  }
}

class _TrendsHero extends StatelessWidget {
  final List<Map<String, dynamic>> trends;
  final PageController pageController;
  final int currentIndex;
  final double height;
  final double cardWidth;
  final double cardHeight;
  final Map<String, dynamic> ui;
  final String Function(Map<String, dynamic>) titleFor;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onSearch;
  final VoidCallback onWishlist;

  const _TrendsHero({
    required this.trends,
    required this.pageController,
    required this.currentIndex,
    required this.height,
    required this.cardWidth,
    required this.cardHeight,
    required this.ui,
    required this.titleFor,
    required this.onPageChanged,
    required this.onSearch,
    required this.onWishlist,
  });

  @override
  Widget build(BuildContext context) {
    final active = trends.isEmpty
        ? const <String, dynamic>{}
        : trends[currentIndex.clamp(0, trends.length - 1).toInt()];
    final backgroundOverlay = _sxTrendHex(
      ui['hero_background_overlay_color'],
      Colors.black,
    );
    final backgroundOpacity =
        _sxTrendNumber(ui, 'hero_background_overlay_opacity', .47);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (active['background'] is Map)
            SxImage(
              url: active['background']['url'],
              fit: BoxFit.cover,
            )
          else
            Container(color: const Color(0xFF35312F)),
          Container(
            color: backgroundOverlay.withOpacity(backgroundOpacity),
          ),
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 54,
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: 4,
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        _heroIcon(
                          Icons.favorite_border,
                          onWishlist,
                        ),
                        const SizedBox(width: 7),
                        _heroIcon(Icons.search, onSearch),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 11,
                    child: Transform.rotate(
                      angle: -.06,
                      child: Text(
                        sxText(ui['logo_text'], 'Trends'),
                        style: TextStyle(
                          color: _sxTrendHex(ui['logo_color'], Colors.white),
                          fontSize: _sxTrendNumber(ui, 'logo_font_size', 26),
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          letterSpacing: _sxTrendNumber(ui, 'logo_letter_spacing', -1.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (trends.isNotEmpty)
            Positioned(
              top: _sxTrendNumber(ui, 'hero_card_top', 68),
              left: 0,
              right: 0,
              height: cardHeight,
              child: PageView.builder(
                controller: pageController,
                itemCount: trends.length,
                onPageChanged: onPageChanged,
                clipBehavior: Clip.none,
                itemBuilder: (_, index) {
                  final trend = trends[index];
                  final activePage = index == currentIndex;
                  final trendWidth = cardWidth;
                  final trendHeight = cardHeight;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _TrendHeroCard(
                        trend: trend,
                        width: trendWidth.toDouble(),
                        height: trendHeight,
                        active: activePage,
                        titleFor: titleFor,
                        ui: ui,
                      ),
                    ),
                  );
                },
              ),
            ),
          if (trends.isNotEmpty && ui['show_counter'] != false)
            Positioned(
              bottom: _sxTrendNumber(ui, 'counter_bottom', 8),
              left: 0,
              right: 0,
              child: Align(
                alignment: _sxTrendAlignment(
                  ui['counter_align'],
                  Alignment.center,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    (currentIndex + 1).toString() +
                        ' / ' +
                        trends.length.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _sxTrendHex(ui['counter_color'], Colors.white),
                      fontSize: _sxTrendNumber(ui, 'counter_font_size', 12),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heroIcon(IconData icon, VoidCallback tap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: tap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: Icon(
                icon,
                color: _sxTrendHex(ui['top_icon_color'], Colors.white),
                size: 29,
              ),
            ),
          ),
        ),
      );
}

class _TrendCountdownBadge extends StatefulWidget {
  final Map<String, dynamic> trend;
  final Map<String, dynamic> ui;

  const _TrendCountdownBadge({
    required this.trend,
    required this.ui,
  });

  @override
  State<_TrendCountdownBadge> createState() => _TrendCountdownBadgeState();
}

class _TrendCountdownBadgeState extends State<_TrendCountdownBadge> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _syncRemaining();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncRemaining(),
    );
  }

  @override
  void didUpdateWidget(covariant _TrendCountdownBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEnds = sxText((oldWidget.trend['timer'] as Map?)?['ends_at']);
    final newEnds = sxText((widget.trend['timer'] as Map?)?['ends_at']);
    if (oldEnds != newEnds) _syncRemaining();
  }

  void _syncRemaining() {
    final timer = widget.trend['timer'];
    if (timer is! Map || timer['enabled'] != true) {
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
    final endsText = sxText(timer['ends_at']);
    if (endsText.isEmpty) return;
    final ends = DateTime.tryParse(endsText);
    if (ends == null) return;
    final remaining = ends.difference(DateTime.now().toUtc());
    if (!mounted) return;
    setState(() {
      _remaining = remaining.isNegative ? Duration.zero : remaining;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration value) {
    final total = value.inSeconds;
    final days = total ~/ 86400;
    final hours = (total % 86400) ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (days > 0) {
      return days.toString().padLeft(2, '0') +
          ':' +
          hours.toString().padLeft(2, '0') +
          ':' +
          minutes.toString().padLeft(2, '0');
    }
    return hours.toString().padLeft(2, '0') +
        ':' +
        minutes.toString().padLeft(2, '0') +
        ':' +
        seconds.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final timer = widget.trend['timer'];
    if (timer is! Map ||
        timer['enabled'] != true ||
        widget.ui['show_timer'] == false ||
        _remaining == Duration.zero) {
      return const SizedBox.shrink();
    }
    final top = sxText(widget.ui['timer_position']) == 'top_right'
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Align(
      alignment: top,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: sxColor(
            widget.ui['timer_background_color'],
            const Color(0xFF111827),
          ),
          borderRadius: BorderRadius.circular(
            _sxTrendNumber(widget.ui, 'timer_radius', 4),
          ),
        ),
        child: Text(
          _format(_remaining),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: sxColor(
              widget.ui['timer_text_color'],
              Colors.white,
            ),
            fontSize: _sxTrendNumber(widget.ui, 'timer_font_size', 9),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TrendHeroCard extends StatelessWidget {
  final Map<String, dynamic> trend;
  final double width;
  final double height;
  final bool active;
  final String Function(Map<String, dynamic>) titleFor;
  final Map<String, dynamic> ui;

  const _TrendHeroCard({
    required this.trend,
    required this.width,
    required this.height,
    required this.active,
    required this.titleFor,
    required this.ui,
  });

  @override
  Widget build(BuildContext context) {
    final products = sxMaps(trend['products']);
    final promo = sxText(
      trend['promo_text'],
      sxText((trend['overlay'] as Map?)?['text']),
    );
    final title = titleFor(trend);
    final overlay = trend['overlay'] is Map
        ? Map<String, dynamic>.from(trend['overlay'] as Map)
        : const <String, dynamic>{};
    final overlayText = sxText(overlay['text']);
    final badgeText = sxText(ui['badge_text']).isNotEmpty
        ? sxText(ui['badge_text'])
        : overlayText;
    final cardRadius = _sxTrendNumber(ui, 'hero_card_radius', 9);
    final cardBorderWidth =
        _sxTrendNumber(ui, 'hero_card_border_width', 1);
    final cardOverlayColor =
        _sxTrendHex(ui['hero_card_overlay_color'], Colors.black);
    final cardOverlayOpacity =
        _sxTrendNumber(ui, 'hero_card_overlay_opacity', .48);
    final contentPadding = _sxTrendNumber(ui, 'content_padding', 10);
    final productGap = _sxTrendNumber(ui, 'product_gap', 4);
    final configuredProductWidth =
        _sxTrendNumber(ui, 'product_width', 0);
    final configuredProductHeight =
        _sxTrendNumber(ui, 'product_height', 0);
    final availableWidth =
        width - (contentPadding * 2).clamp(0.0, width / 2).toDouble();
    final safeWidth = availableWidth > 0 ? availableWidth : width;
    final productWidth = configuredProductWidth > 0
        ? (configuredProductWidth <
                (safeWidth - productGap * 2) / 3
            ? configuredProductWidth
            : (safeWidth - productGap * 2) / 3)
        : (safeWidth - productGap * 2) / 3;
    final configuredTopSpacing =
        _sxTrendNumber(ui, 'product_top_spacing', 72);
    final baseProductTop = contentPadding + configuredTopSpacing;
    final baseAvailableHeight =
        (height - baseProductTop - contentPadding).clamp(70.0, height);
    double productTop = baseProductTop;
    double productHeight;
    if (configuredProductHeight > 0) {
      // Allow a taller product card to consume the gap above it before
      // reducing the requested height. Keep a small visual breathing room.
      const minimumTopSpacing = 10.0;
      final extraNeeded =
          (configuredProductHeight - baseAvailableHeight).clamp(0.0, height);
      final reducedTopSpacing =
          (configuredTopSpacing - extraNeeded).clamp(
        minimumTopSpacing,
        configuredTopSpacing,
      );
      productTop = contentPadding + reducedTopSpacing;
      productHeight = configuredProductHeight.clamp(
        70.0,
        (height - productTop - contentPadding).clamp(70.0, height),
      );
    } else {
      productHeight = baseAvailableHeight;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2827),
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(
          color: _sxTrendHex(ui['hero_card_border_color'], Colors.white),
          width: cardBorderWidth,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if ((trend['background'] as Map?)?['url'] != null)
            SxImage(
              url: (trend['background'] as Map?)?['url'],
              fit: BoxFit.cover,
            ),
          Container(
            color: cardOverlayColor.withOpacity(cardOverlayOpacity),
          ),
          Positioned(
            top: contentPadding,
            left: contentPadding,
            right: contentPadding,
            child: Column(
              children: [
                _TrendCountdownBadge(
                  trend: trend,
                  ui: ui,
                ),
                SizedBox(
                  height: ui['show_timer'] == false ? 0 : 4,
                ),
                if (badgeText.isNotEmpty)
                  Align(
                    alignment: sxText(ui['badge_position']) == 'top_left'
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _sxTrendHex(
                          ui['badge_background_color'],
                          const Color(0xFF111827),
                        ),
                        borderRadius: BorderRadius.circular(
                          _sxTrendNumber(ui, 'badge_radius', 4),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: _sxTrendHex(
                            ui['badge_text_color'],
                            Colors.white,
                          ),
                          fontSize:
                              _sxTrendNumber(ui, 'badge_font_size', 9.5),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (ui['show_title'] != false)
                  Align(
                    alignment: _sxTrendAlignment(ui['title_align']),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text.rich(
                              _sxTrendTitleSpan(title, ui),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: _sxTrendTextAlign(ui['title_align']),
                              style: TextStyle(
                                fontSize: _sxTrendNumber(
                                  ui,
                                  'title_font_size',
                                  18,
                                ),
                                fontWeight: _sxTrendWeight(
                                  ui['title_font_weight'],
                                  FontWeight.w900,
                                ),
                                height: 1.05,
                              ),
                            ),
                          ),
                          if (ui['title_show_arrow'] != false)
                            SizedBox(
                              width: _sxTrendNumber(
                                ui,
                                'title_arrow_gap',
                                4,
                              ),
                            ),
                          if (ui['title_show_arrow'] != false)
                            Text(
                              sxText(ui['title_arrow'], '>'),
                              style: TextStyle(
                                color: _sxTrendHex(
                                  ui['title_arrow_color'],
                                  Colors.white,
                                ),
                                fontSize: _sxTrendNumber(
                                  ui,
                                  'title_arrow_font_size',
                                  16,
                                ),
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (ui['show_title'] != false &&
                    ui['show_description'] != false &&
                    promo.isNotEmpty)
                  SizedBox(
                    height: _sxTrendNumber(ui, 'title_spacing', 5),
                  ),
                if (ui['show_description'] != false && promo.isNotEmpty)
                  Align(
                    alignment: _sxTrendAlignment(ui['description_align']),
                    child: Text(
                      promo,
                      maxLines: sxInt(ui['promo_max_lines'], 2),
                      overflow: TextOverflow.ellipsis,
                      textAlign: _sxTrendTextAlign(ui['description_align']),
                      style: TextStyle(
                        color: _sxTrendHex(ui['promo_color'], Colors.white),
                        fontSize: _sxTrendNumber(
                          ui,
                          'promo_font_size',
                          10.5,
                        ),
                        height: 1.25,
                        fontWeight: _sxTrendWeight(
                          ui['promo_font_weight'],
                          FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                contentPadding,
                productTop,
                contentPadding,
                contentPadding,
              ),
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  height: productHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    textDirection: TextDirection.ltr,
                    children: [
                      for (int i = 0; i < 3; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            right: i == 2 ? 0 : productGap,
                          ),
                          child: SizedBox(
                            width: productWidth,
                            child: _MiniTrendProduct(
                              row: i < products.length ? products[i] : null,
                              ui: ui,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTrendProduct extends StatelessWidget {
  final Map<String, dynamic>? row;
  final Map<String, dynamic> ui;

  const _MiniTrendProduct({
    this.row,
    required this.ui,
  });

  @override
  Widget build(BuildContext context) {
    final product = row?['product'] is Map
        ? Map<String, dynamic>.from(row!['product'])
        : null;
    final image = sxText(product?['image_url']);
    final radius = _sxTrendNumber(ui, 'hero_product_radius', 7);
    final infoHeight = _sxTrendNumber(ui, 'hero_product_info_height', 27);
    final showName = ui['hero_show_product_name'] != false;
    final showPrice = ui['hero_show_product_price'] != false;
    final name = sxText(product?['name']);
    final price = sxText(product?['price']);
    final productId = sxInt(product?['id']);

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: const Color(0xFFEDEDED),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.isEmpty)
              const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: Color(0xFF9A9A9A),
                ),
              )
            else
              SxImage(
                url: image,
                fit: _sxTrendFit(ui['hero_product_image_fit']),
              ),
            if (showName || showPrice)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  constraints: BoxConstraints(minHeight: infoHeight),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  color: _sxTrendHex(
                    ui['hero_product_info_background_color'],
                    Colors.white,
                  ).withOpacity(.92),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showName && name.isNotEmpty)
                        Text(
                          name,
                          maxLines: sxInt(ui['hero_product_name_max_lines'], 2),
                          overflow: TextOverflow.ellipsis,
                          textAlign: _sxTrendTextAlign(
                            ui['hero_product_name_align'],
                            TextAlign.right,
                          ),
                          style: TextStyle(
                            color: _sxTrendHex(
                              ui['hero_product_name_color'],
                              _sxTrendHex(
                                ui['hero_product_text_color'],
                                Colors.black,
                              ),
                            ),
                            fontSize: _sxTrendNumber(
                              ui,
                              'hero_product_name_font_size',
                              8.5,
                            ),
                            fontWeight: _sxTrendWeight(
                              ui['hero_product_name_font_weight'],
                              FontWeight.w800,
                            ),
                            height: 1.1,
                          ),
                        ),
                      if (showName && showPrice && name.isNotEmpty && price.isNotEmpty)
                        const SizedBox(height: 2),
                      if (showPrice && price.isNotEmpty)
                        Align(
                          alignment: _sxTrendAlignment(
                            ui['hero_product_price_align'],
                            Alignment.centerRight,
                          ),
                          child: Text(
                            price + ' ' + state.currencySymbol,
                            textDirection: TextDirection.ltr,
                            textAlign: _sxTrendTextAlign(
                              ui['hero_product_price_align'],
                              TextAlign.right,
                            ),
                            style: TextStyle(
                              color: _sxTrendHex(
                                ui['hero_product_price_color'],
                                _sxTrendHex(
                                  ui['hero_product_text_color'],
                                  Colors.black,
                                ),
                              ),
                              fontSize: _sxTrendNumber(
                                ui,
                                'hero_product_price_font_size',
                                9.5,
                              ),
                              fontWeight: _sxTrendWeight(
                                ui['hero_product_price_font_weight'],
                                FontWeight.w900,
                              ),
                              height: 1.05,
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
    );

    if (productId <= 0) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SxProductScreen(id: productId),
          ),
        );
      },
      child: content,
    );
  }
}

class _TrendHashtagStrip extends StatelessWidget {
  final List<Map<String, dynamic>> tags;
  final int? selectedId;
  final String Function(Map<String, dynamic>) tagText;
  final Map<String, dynamic> ui;
  final VoidCallback onMenu;
  final ValueChanged<int?> onSelect;

  const _TrendHashtagStrip({
    required this.tags,
    required this.selectedId,
    required this.tagText,
    required this.ui,
    required this.onMenu,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final chipHeight = _sxTrendNumber(ui, 'hashtag_height', 31).clamp(24, 48).toDouble();
    final rowHeight = chipHeight + 8;

    return SizedBox(
      height: rowHeight,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          children: [
            _menu(chipHeight),
            const SizedBox(width: 6),
            _chip(
              label: 'لك',
              selected: selectedId == null,
              purple: true,
              onTap: () => onSelect(null),
              height: chipHeight,
            ),
            const SizedBox(width: 6),
            for (final tag in tags) ...[
              _chip(
                label: tagText(tag),
                selected: sxInt(tag['id']) == selectedId,
                onTap: () => onSelect(sxInt(tag['id'])),
                height: chipHeight,
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _menu(double height) => Material(
        color: _sxTrendHex(
          ui['hashtag_background_color'],
          const Color(0xFFF7F7F7),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _sxTrendNumber(ui, 'hashtag_radius', 0),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(
            _sxTrendNumber(ui, 'hashtag_radius', 0),
          ),
          onTap: onMenu,
          child: SizedBox(
            width: height + 4,
            height: height,
            child: Center(
              child: Icon(
                Icons.menu,
                size: (_sxTrendNumber(ui, 'hashtag_font_size', 11.5) + 9)
                    .clamp(17, 28),
                color: _sxTrendHex(
                  ui['hashtag_text_color'],
                  const Color(0xFF8B8B8B),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required double height,
    bool purple = false,
  }) =>
      Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _sxTrendNumber(ui, 'hashtag_radius', 0),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(
            _sxTrendNumber(ui, 'hashtag_radius', 0),
          ),
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: _sxTrendNumber(
                ui,
                'hashtag_horizontal_padding',
                13,
              ),
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? _sxTrendHex(
                      ui['hashtag_active_background_color'],
                      const Color(0xFFF0E6FF),
                    )
                  : _sxTrendHex(
                      ui['hashtag_background_color'],
                      const Color(0xFFF3F4F7),
                    ),
              borderRadius: BorderRadius.circular(
                _sxTrendNumber(ui, 'hashtag_radius', 0),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? _sxTrendHex(
                        ui['hashtag_active_text_color'],
                        const Color(0xFF8355E6),
                      )
                    : _sxTrendHex(
                        ui['hashtag_text_color'],
                        const Color(0xFF4C4C4C),
                      ),
                fontSize: _sxTrendNumber(ui, 'hashtag_font_size', 11.5),
                fontWeight:
                    selected || purple ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
}

class _TrendProductTile extends StatefulWidget {
  final ProductModel product;
  final Map<String, dynamic>? hashtag;
  final Map<String, dynamic> ui;
  final Map<String, dynamic>? displaySettings;

  const _TrendProductTile({
    required this.product,
    this.hashtag,
    required this.ui,
    this.displaySettings,
  });

  @override
  State<_TrendProductTile> createState() => _TrendProductTileState();
}

class _TrendProductTileState extends State<_TrendProductTile> {
  late List<String> gallery;
  int imageIndex = 0;

  @override
  void initState() {
    super.initState();
    gallery = _unique(widget.product.images, widget.product.image);
  }

  @override
  void didUpdateWidget(covariant _TrendProductTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      gallery = _unique(widget.product.images, widget.product.image);
      imageIndex = 0;
    }
  }

  List<String> _unique(Iterable<String> images, String? primary) {
    final rows = <String>[
      ...images.where((x) => x.isNotEmpty),
      if (primary != null && primary.isNotEmpty) primary,
    ];
    return rows.toSet().toList();
  }

  int _discount() {
    final old = sxDouble(widget.product.oldPrice);
    final current = sxDouble(widget.product.price);
    if (old <= current || old <= 0) return 0;
    return ((1 - current / old) * 100).round();
  }

  Future<void> _addToCart(BuildContext context) async {
    try {
      if (widget.product.variantId == null) return;
      await api.addCart(widget.product.variantId!);
      _CartBadge.value.value += 1;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة المنتج إلى الحقيبة'),
          duration: Duration(milliseconds: 850),
        ),
      );
    } catch (_) {}
  }

  Map<String, dynamic> get _cardSettings =>
      widget.displaySettings ?? const <String, dynamic>{};

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
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value.toString());
    return (parsed == null || !parsed.isFinite) ? fallback : parsed;
  }

  String _cardText(String key, String fallback) {
    final value = _cardValue(key, fallback).toString().trim();
    return value.isEmpty ? fallback : value;
  }

  Widget _cornerPositioned(
    String position,
    Widget child, {
    double offset = 7,
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

  Widget _colorSwatches() {
    final colors = widget.product.colors;
    if (!_cardBool('colors_show', true) || colors.isEmpty) {
      return const SizedBox.shrink();
    }

    final swatchSize = _cardNumber('colors_size', 13);
    final containerSize =
        _cardNumber('colors_container_size', 16)
            .clamp(swatchSize, 28)
            .toDouble();
    final gap = _cardNumber('colors_gap', 2);
    final max = _cardNumber('colors_max', 6).round().clamp(1, 8).toInt();

    final items = colors.take(max).map((color) {
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

    final direction = _cardText('colors_direction', 'vertical');
    if (direction == 'vertical') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == items.length - 1 ? 0 : gap,
              ),
              child: items[i],
            ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              left: i == items.length - 1 ? 0 : gap,
            ),
            child: items[i],
          ),
      ],
    );
  }

  Widget _badgeChip(Map<String, dynamic> badge) {
    final tab = sxText(badge['storefront_tab']);
    final fallback = tab == 'new'
        ? const Color(0xFF16A34A)
        : tab == 'offers'
            ? const Color(0xFFDC2626)
            : const Color(0xFF111827);
    final bg = sxColor(sxText(badge['bg_color']), fallback);
    final fg = sxColor(sxText(badge['text_color']), Colors.white);
    final text = sxText(
      badge['custom_text'],
      sxText(badge['name'], sxText(badge['code'])),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          _cardNumber('product_badge_radius', 3),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: _cardNumber('product_badge_font_size', 8),
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale =
        (MediaQuery.sizeOf(context).width / 360.0).clamp(.86, 1.15).toDouble();
    final imageHeight =
        _sxTrendNumber(widget.ui, 'picks_image_height', 258) * scale;
    final contentHeight =
        _sxTrendNumber(widget.ui, 'picks_content_height', 92) * scale;
    final discount = _discount();
    final hashtagLabel = widget.hashtag == null
        ? '#ترندات'
        : sxText(widget.hashtag?['display_name'], '#ترندات');

    return Container(
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SxProductScreen(id: widget.product.id),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (gallery.isEmpty)
                    Container(
                      color: const Color(0xFFEDEDED),
                      child: const Icon(Icons.image_outlined),
                    )
                  else
                    GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if (gallery.length <= 1) return;
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity.abs() < 30) return;
                        final direction = velocity < 0 ? 1 : -1;
                        final next =
                            (imageIndex + direction) % gallery.length;
                        setState(() {
                          imageIndex =
                              next < 0 ? next + gallery.length : next;
                        });
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(
                            widget.product.id.toString() +
                                '-' +
                                imageIndex.toString(),
                          ),
                          child: SxImage(
                            url: gallery[imageIndex],
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  if (_cardBool('show_product_badges', true) &&
                      widget.product.badges.isNotEmpty)
                    _cornerPositioned(
                      _cardText('product_badge_position', 'top_right'),
                      Padding(
                        padding: const EdgeInsets.only(top: 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: widget.product.badges
                              .take(
                                _cardNumber('product_badge_max', 2)
                                    .round()
                                    .clamp(1, 4)
                                    .toInt(),
                              )
                              .map(_badgeChip)
                              .toList(),
                        ),
                      ),
                    ),
                  if (_cardBool('colors_show', true) &&
                      widget.product.colors.isNotEmpty)
                    _cornerPositioned(
                      _cardText('colors_position', 'bottom_right'),
                      _colorSwatches(),
                      bottomOffset: 10,
                    ),
                  if (gallery.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 6,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          gallery.length.clamp(0, 7).toInt(),
                          (i) => Container(
                            width: i == imageIndex ? 12 : 4,
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(
                                i == imageIndex ? .95 : .55,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: contentHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 0, 7, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 25,
                      color: const Color(0xFFF1EAFE),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          const Icon(
                            Icons.chevron_left,
                            size: 17,
                            color: Color(0xFF8D65E8),
                          ),
                          Expanded(
                            child: Text(
                              hashtagLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF7751CA),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Text(
                            'ترندات',
                            style: TextStyle(
                              color: Color(0xFF8C5AE8),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (widget.ui['show_product_name'] != false)
                      Text(
                        widget.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: _sxTrendTextAlign(
                          widget.ui['product_name_align'],
                          TextAlign.right,
                        ),
                        style: TextStyle(
                          color: _sxTrendHex(
                            widget.ui['product_name_color'],
                            _sxTrendHex(
                              widget.ui['product_text_color'],
                              Colors.black,
                            ),
                          ),
                          fontSize: _sxTrendNumber(
                            widget.ui,
                            'product_name_font_size',
                            8.5,
                          ),
                          fontWeight: _sxTrendWeight(
                            widget.ui['product_name_font_weight'],
                            FontWeight.w800,
                          ),
                          height: 1.15,
                        ),
                      ),
                    if (widget.product.soldQty > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'sold +' + widget.product.soldQty.toString(),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        Material(
                          color: const Color(0xFFF6F6F6),
                          child: InkWell(
                            onTap: () => _addToCart(context),
                            child: const SizedBox(
                              width: 33,
                              height: 33,
                              child: Center(
                                child: Icon(
                                  Icons.add_shopping_cart_outlined,
                                  size: 19,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (discount > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              'خصم $discount%',
                              style: const TextStyle(
                                color: Color(0xFFDF5B37),
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (widget.ui['show_product_price'] != false)
                          Expanded(
                            child: Align(
                              alignment: _sxTrendAlignment(
                                widget.ui['product_price_align'],
                                Alignment.centerRight,
                              ),
                              child: Text(
                                widget.product.price +
                                    ' ' +
                                    state.currencySymbol,
                                textDirection: TextDirection.ltr,
                                textAlign: _sxTrendTextAlign(
                                  widget.ui['product_price_align'],
                                  TextAlign.right,
                                ),
                                style: TextStyle(
                                  color: _sxTrendHex(
                                    widget.ui['product_price_color'],
                                    _sxTrendHex(
                                      widget.ui['product_text_color'],
                                      Colors.black,
                                    ),
                                  ),
                                  fontSize: _sxTrendNumber(
                                    widget.ui,
                                    'product_price_font_size',
                                    9.5,
                                  ),
                                  fontWeight: _sxTrendWeight(
                                    widget.ui['product_price_font_weight'],
                                    FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SxTrendDetailScreen extends StatelessWidget {
  final Map<String, dynamic> trend;

  const SxTrendDetailScreen({super.key, required this.trend});

  @override
  Widget build(BuildContext context) {
    final products = sxMaps(trend['products'])
        .map((x) => x['product'])
        .whereType<Map>()
        .map((x) => ProductModel.fromJson(Map<String, dynamic>.from(x)))
        .toList();

    return SxShellPage(
      title: sxText(
        (trend['hashtag'] as Map?)?['display_name'],
        'الترند',
      ),
      back: true,
      child: ListView(
        children: [
          SizedBox(
            height: 285,
            child: SxImage(
              url: (trend['background'] as Map?)?['url'],
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Text(
              sxText(trend['promo_text']),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SxSectionTitle(title: 'منتجات الترند'),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 0, 7, 20),
            child: SxProductGrid(products: products),
          ),
        ],
      ),
    );
  }
}

class SxCartScreen extends StatefulWidget {
  const SxCartScreen({super.key});
  @override State<SxCartScreen> createState() => _SxCartScreenState();
}

class _SxCartScreenState extends State<SxCartScreen> {
  Map<String, dynamic>? cart; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (!state.loggedIn) { setState(() => loading = false); return; }
    try { cart = await api.cart(currencyId: state.currencyId); _CartBadge.value.value = sxMaps(cart?['item']?['items']).length; } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    if (!state.loggedIn) return const Scaffold(body: Center(child: Text('سجل الدخول أولًا')));
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final rows = sxMaps(cart?['item']?['items']); final subtotal = sxText(cart?['item']?['subtotal'], '0');
    return Scaffold(
      appBar: const SxAppBar(title: 'حقيبة التسوق'),
      body: rows.isEmpty ? const _EmptyCart() : Column(children: [
        Expanded(child: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(8), children: [
          Container(color: const Color(0xFFFFF4E9), padding: const EdgeInsets.all(10), child: const Row(children: [
            Icon(Icons.local_shipping_outlined, size: 18), SizedBox(width: 7),
            Expanded(child: Text('أكمل طلبك للحصول على أفضل عرض شحن متاح لعنوانك.', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
          ])),
          const SizedBox(height: 7),
          for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 7), child: _CartRow(
            row: r,
            plus: () => change(r, sxInt(r['qty'], 1) + 1),
            minus: () { final q = sxInt(r['qty'], 1) - 1; if (q <= 0) api.removeCart(sxInt(r['id'])).then((_) => load()); else change(r, q); },
            remove: () async { await api.removeCart(sxInt(r['id'])); await load(); },
          )),
        ]))),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: ClientTheme.border))),
          child: Column(children: [
            const Row(children: [Expanded(child: Text('كود الخصم', style: TextStyle(fontSize: 11))), Text('إضافة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 7),
            Row(children: [const Expanded(child: Text('الإجمالي', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))), Text(subtotal + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]),
            const SizedBox(height: 8),
            SizedBox(height: 49, width: double.infinity, child: FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxCheckoutScreen())), style: FilledButton.styleFrom(backgroundColor: Colors.black), child: const Text('المتابعة للدفع', style: TextStyle(fontWeight: FontWeight.w900)))),
          ]),
        )),
      ]),
    );
  }
  Future<void> change(Map<String, dynamic> row, int q) async { try { await api.cartQty(sxInt(row['id']), q); await load(); } catch (_) {} }
}

class _CartRow extends StatelessWidget {
  final Map<String, dynamic> row; final VoidCallback plus, minus, remove;
  const _CartRow({required this.row, required this.plus, required this.minus, required this.remove});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(7),
    decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: ClientTheme.border))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 99, height: 123, child: ClipRRect(borderRadius: BorderRadius.circular(6), child: SxImage(url: row['image_url']))),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(sxText(row['product_name'], 'منتج'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5), Text(sxText(row['variant_display']), style: const TextStyle(fontSize: 9, color: ClientTheme.muted)),
        const SizedBox(height: 8), Text(sxText(row['unit_price'], '0') + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Row(children: [
          InkWell(onTap: remove, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 18))), const Spacer(),
          Container(height: 34, decoration: BoxDecoration(border: Border.all(color: ClientTheme.border), borderRadius: BorderRadius.circular(4)), child: Row(children: [
            InkWell(onTap: plus, child: const SizedBox(width: 32, child: Center(child: Text('+', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 9), child: Text(sxText(row['qty'], '1'), style: const TextStyle(fontWeight: FontWeight.w900))),
            InkWell(onTap: minus, child: const SizedBox(width: 32, child: Center(child: Text('−', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))))),
          ])),
        ]),
      ])),
    ]),
  );
}
class _EmptyCart extends StatelessWidget {
  const _EmptyCart();
  @override Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.shopping_bag_outlined, size: 50, color: Color(0xFF929292)), SizedBox(height: 10),
    Text('حقيبة التسوق فارغة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), SizedBox(height: 5),
    Text('أضف منتجاتك المفضلة وابدأ طلبك.', style: TextStyle(fontSize: 10, color: ClientTheme.muted)),
  ]));
}

class SxCheckoutScreen extends StatefulWidget {
  const SxCheckoutScreen({super.key});
  @override State<SxCheckoutScreen> createState() => _SxCheckoutScreenState();
}

class _SxCheckoutScreenState extends State<SxCheckoutScreen> {
  List<Map<String, dynamic>> addresses = [], shipping = [], payments = [];
  Map<String, dynamic>? cart;
  int? addressId, shippingId, paymentId;
  bool loading = true, busy = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      addresses = await api.addresses(); shipping = await api.shippingMethods(); payments = await api.paymentMethods(); cart = await api.cart(currencyId: state.currencyId);
      if (addresses.isNotEmpty) addressId = sxInt((addresses.firstWhere((x) => x['is_default'] == true, orElse: () => addresses.first))['id']);
      if (shipping.isNotEmpty) shippingId = sxInt(shipping.first['id']);
      if (payments.isNotEmpty) paymentId = sxInt(payments.first['id']);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  Future<void> addAddress() async {
    final b = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, backgroundColor: Colors.white, builder: (_) => const SxAddressForm());
    if (b == null) return;
    try { final item = await api.addAddress(b); await load(); addressId = sxInt(item['id']); setState(() {}); } catch (_) {}
  }
  Future<void> submit() async {
    final rows = sxMaps(cart?['item']?['items']); if (addressId == null || rows.isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await api.createOrder(addressId!, rows.map((e) => {'variant_id': e['variant_id'], 'qty': e['qty']}).toList(), shippingMethodId: shippingId, paymentMethodId: paymentId);
      final item = r['item'];
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => SxOrderSuccess(no: sxText(item is Map ? item['order_no'] : ''))), (r) => r.isFirst);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final subtotal = sxText(cart?['item']?['subtotal'], '0');
    final address = addressId == null ? null : addresses.firstWhere((x) => sxInt(x['id']) == addressId, orElse: () => addresses.first);
    return Scaffold(
      appBar: const SxAppBar(title: 'إتمام الطلب'),
      body: ListView(padding: const EdgeInsets.all(10), children: [
        const SxSectionTitle(title: 'عنوان التسليم'),
        address == null ? OutlinedButton.icon(onPressed: addAddress, icon: const Icon(Icons.add), label: const Text('إضافة عنوان')) : ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 3), leading: const Icon(Icons.location_on_outlined),
          title: Text(sxText(address['recipient_name']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          subtitle: Text(sxText(address['district']) + ' ' + sxText(address['street']), style: const TextStyle(fontSize: 9)),
          trailing: const Icon(Icons.chevron_left), onTap: addAddress,
        ),
        const SxSectionTitle(title: 'طريقة الشحن'),
        _Choices(rows: shipping, selected: shippingId, sub: (x) => sxText(x['delivery_days_min']) + '-' + sxText(x['delivery_days_max']) + ' يوم', tap: (id) => setState(() => shippingId = id)),
        const SxSectionTitle(title: 'طريقة الدفع'),
        _Choices(rows: payments, selected: paymentId, sub: (x) => sxText(x['provider']), tap: (id) => setState(() => paymentId = id)),
        const SxSectionTitle(title: 'ملخص الطلب'),
        Container(color: ClientTheme.soft, padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [const Expanded(child: Text('المنتجات', style: TextStyle(fontSize: 10))), Text(subtotal + ' ' + state.currencySymbol, style: const TextStyle(fontWeight: FontWeight.w900))]),
          const SizedBox(height: 8),
          const Row(children: [Expanded(child: Text('الشحن', style: TextStyle(fontSize: 10))), Text('حسب العنوان', style: TextStyle(fontSize: 9))]),
          const Divider(height: 17),
          Row(children: [const Expanded(child: Text('الإجمالي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900))), Text(subtotal + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))]),
        ])),
        const SizedBox(height: 13),
        SizedBox(height: 49, child: FilledButton(onPressed: busy ? null : submit, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: busy ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('تأكيد الطلب', style: TextStyle(fontWeight: FontWeight.w900)))),
      ]),
    );
  }
}

class _Choices extends StatelessWidget {
  final List<Map<String, dynamic>> rows; final int? selected; final String Function(Map<String, dynamic>) sub; final ValueChanged<int> tap;
  const _Choices({required this.rows, required this.selected, required this.sub, required this.tap});
  @override Widget build(BuildContext context) => Column(children: [
    for (final x in rows) InkWell(onTap: () => tap(sxInt(x['id'])), child: Container(
      margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(border: Border.all(color: sxInt(x['id']) == selected ? Colors.black : ClientTheme.border, width: sxInt(x['id']) == selected ? 1.2 : .7), borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(sxText(x['name']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)), const SizedBox(height: 3),
          Text(sub(x), style: const TextStyle(fontSize: 9, color: ClientTheme.muted)),
        ])), if (sxInt(x['id']) == selected) const Icon(Icons.check_circle, size: 19),
      ]),
    )),
  ]);
}

class SxAddressForm extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const SxAddressForm({super.key, this.initial});
  @override State<SxAddressForm> createState() => _SxAddressFormState();
}

class _SxAddressFormState extends State<SxAddressForm> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final district = TextEditingController();
  final street = TextEditingController();
  final landmark = TextEditingController();

  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> regions = [];
  List<Map<String, dynamic>> cities = [];
  List<Map<String, dynamic>> areas = [];
  int? countryId;
  int? regionId;
  int? cityId;
  int? areaId;
  bool isDefault = false;
  bool loadingGeo = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      name.text = sxText(initial['recipient_name']);
      phone.text = sxText(initial['phone']);
      district.text = sxText(initial['district']);
      street.text = sxText(initial['street']);
      landmark.text = sxText(initial['landmark']);
      countryId = sxInt(initial['country_id']);
      regionId = sxInt(initial['region_id']);
      cityId = sxInt(initial['city_id']);
      areaId = sxInt(initial['city_area_id']);
      isDefault = initial['is_default'] == true;
    }
    _loadGeo();
  }

  Future<void> _loadGeo() async {
    try {
      countries = await api.countries();
      final allRegions = await api.regions();
      if ((countryId == null || countryId! <= 0) && countries.isNotEmpty) {
        countryId = sxInt(countries.first['id']);
      }
      if (regionId != null && regionId! > 0) {
        final selectedRegion = allRegions.firstWhere(
          (x) => sxInt(x['id']) == regionId,
          orElse: () => <String, dynamic>{},
        );
        final selectedCountryId = sxInt(selectedRegion['country_id']);
        if (selectedCountryId > 0) countryId = selectedCountryId;
      }
      regions = countryId != null && countryId! > 0
          ? await api.regions(countryId: countryId)
          : allRegions;
      if ((regionId == null || regionId! <= 0) && cityId != null && cityId! > 0) {
        final allCities = await api.cities();
        final selectedCity = allCities.firstWhere(
          (x) => sxInt(x['id']) == cityId,
          orElse: () => <String, dynamic>{},
        );
        final rid = sxInt(selectedCity['region_id']);
        if (rid > 0) {
          regionId = rid;
          final region = allRegions.firstWhere(
            (x) => sxInt(x['id']) == rid,
            orElse: () => <String, dynamic>{},
          );
          final cid = sxInt(region['country_id']);
          if (cid > 0) {
            countryId = cid;
            regions = await api.regions(countryId: cid);
          }
        }
      }
      cities = regionId != null && regionId! > 0
          ? await api.cities(regionId: regionId)
          : await api.cities();
      if (cityId != null && cityId! > 0 &&
          !cities.any((x) => sxInt(x['id']) == cityId)) {
        cityId = null;
        areaId = null;
      }
      areas = cityId != null && cityId! > 0
          ? await api.cityAreas(cityId: cityId)
          : <Map<String, dynamic>>[];
      if (areaId != null && areaId! > 0 &&
          !areas.any((x) => sxInt(x['id']) == areaId)) {
        areaId = null;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loadingGeo = false);
    }
  }

  Future<void> _countryChanged(int id) async {
    setState(() {
      countryId = id;
      regionId = null;
      cityId = null;
      areaId = null;
      cities = [];
      areas = [];
    });
    try {
      final v = await api.regions(countryId: id);
      if (mounted) setState(() => regions = v);
    } catch (_) {}
  }

  Future<void> _regionChanged(int id) async {
    setState(() {
      regionId = id;
      cityId = null;
      areaId = null;
      areas = [];
    });
    try {
      final v = await api.cities(regionId: id);
      if (mounted) setState(() => cities = v);
    } catch (_) {}
  }

  Future<void> _cityChanged(int id) async {
    setState(() {
      cityId = id;
      areaId = null;
      areas = [];
    });
    try {
      final v = await api.cityAreas(cityId: id);
      if (mounted) setState(() => areas = v);
    } catch (_) {}
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    district.dispose();
    street.dispose();
    landmark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .65,
      maxChildSize: .98,
      builder: (_, scroll) => Column(
        children: [
          const _Handle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 2, 15, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: ClientTheme.soft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_outlined, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.initial == null ? 'إضافة عنوان' : 'تعديل العنوان',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'اختر الموقع من الخادم ثم أضف التفاصيل الأدق مثل الحي والشارع.',
                        style: TextStyle(fontSize: 9.5, color: ClientTheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 18),
              children: [
                const _AddressFormSectionTitle(title: 'بيانات المستلم'),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستلم',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                const _AddressFormSectionTitle(title: 'الموقع من الخادم'),
                if (loadingGeo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  if (countries.isNotEmpty) ...[
                    DropdownButtonFormField<int>(
                      value: countries.any((x) => sxInt(x['id']) == countryId) ? countryId : null,
                      decoration: const InputDecoration(
                        labelText: 'الدولة',
                        prefixIcon: Icon(Icons.public_outlined, size: 20),
                      ),
                      items: countries.map((x) => DropdownMenuItem(
                        value: sxInt(x['id']),
                        child: Text(
                          sxText(x['name_ar'], sxText(x['name_en'])),
                          style: const TextStyle(fontSize: 11),
                        ),
                      )).toList(),
                      onChanged: (v) { if (v != null) _countryChanged(v); },
                    ),
                    const SizedBox(height: 8),
                  ],
                  DropdownButtonFormField<int>(
                    value: regions.any((x) => sxInt(x['id']) == regionId) ? regionId : null,
                    decoration: const InputDecoration(
                      labelText: 'المنطقة / المحافظة',
                      prefixIcon: Icon(Icons.map_outlined, size: 20),
                    ),
                    items: regions.map((x) => DropdownMenuItem(
                      value: sxInt(x['id']),
                      child: Text(sxText(x['name']), style: const TextStyle(fontSize: 11)),
                    )).toList(),
                    onChanged: (v) { if (v != null) _regionChanged(v); },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: cities.any((x) => sxInt(x['id']) == cityId) ? cityId : null,
                    decoration: const InputDecoration(
                      labelText: 'المدينة',
                      prefixIcon: Icon(Icons.location_city_outlined, size: 20),
                    ),
                    items: cities.map((x) => DropdownMenuItem(
                      value: sxInt(x['id']),
                      child: Text(sxText(x['name']), style: const TextStyle(fontSize: 11)),
                    )).toList(),
                    onChanged: (v) { if (v != null) _cityChanged(v); },
                  ),
                  if (areas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: areas.any((x) => sxInt(x['id']) == areaId) ? areaId : null,
                      decoration: const InputDecoration(
                        labelText: 'المنطقة داخل المدينة',
                        prefixIcon: Icon(Icons.near_me_outlined, size: 20),
                      ),
                      items: areas.map((x) => DropdownMenuItem(
                        value: sxInt(x['id']),
                        child: Text(sxText(x['name']), style: const TextStyle(fontSize: 11)),
                      )).toList(),
                      onChanged: (v) => setState(() => areaId = v),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                const _AddressFormSectionTitle(title: 'عنوان أدق'),
                TextField(
                  controller: district,
                  decoration: const InputDecoration(
                    labelText: 'الحي',
                    hintText: 'مثال: حي المروج',
                    prefixIcon: Icon(Icons.domain_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: street,
                  decoration: const InputDecoration(
                    labelText: 'الشارع / رقم المبنى',
                    hintText: 'اسم الشارع أو رقم المبنى',
                    prefixIcon: Icon(Icons.signpost_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: landmark,
                  decoration: const InputDecoration(
                    labelText: 'معلم قريب',
                    hintText: 'بجوار المسجد أو المتجر أو أي علامة واضحة',
                    prefixIcon: Icon(Icons.place_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: ClientTheme.soft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    title: const Text(
                      'اجعل هذا العنوان افتراضيًا',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'سيُستخدم تلقائيًا عند إتمام الطلب.',
                      style: TextStyle(fontSize: 8.5, color: ClientTheme.muted),
                    ),
                    value: isDefault,
                    onChanged: (v) => setState(() => isDefault = v),
                  ),
                ),
                const SizedBox(height: 13),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: cityId == null ||
                            name.text.trim().isEmpty ||
                            phone.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, <String, dynamic>{
                            'recipient_name': name.text.trim(),
                            'phone': phone.text.trim(),
                            if (countryId != null) 'country_id': countryId,
                            'city_id': cityId,
                            if (areaId != null) 'city_area_id': areaId,
                            'district': district.text.trim(),
                            'street': street.text.trim(),
                            'landmark': landmark.text.trim(),
                            'is_default': isDefault,
                          }),
                    style: FilledButton.styleFrom(backgroundColor: Colors.black),
                    child: Text(
                      widget.initial == null ? 'إضافة العنوان' : 'حفظ التعديلات',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AddressFormSectionTitle extends StatelessWidget {
  final String title;
  const _AddressFormSectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
  );
}

class SxOrderSuccess extends StatelessWidget {
  final String no; const SxOrderSuccess({super.key, required this.no});
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 74, height: 74, decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 36)),
    const SizedBox(height: 15), const Text('تم تأكيد طلبك', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
    const SizedBox(height: 5), Text(no.isEmpty ? 'تم إنشاء الطلب بنجاح' : 'رقم الطلب: ' + no, style: const TextStyle(fontSize: 10, color: ClientTheme.muted)),
    const SizedBox(height: 16), SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: () => Navigator.pop(context), style: FilledButton.styleFrom(backgroundColor: Colors.black), child: const Text('العودة للتسوق'))),
  ])))));
}

class SxAccountScreen extends StatefulWidget {
  const SxAccountScreen({super.key});
  @override State<SxAccountScreen> createState() => _SxAccountScreenState();
}

class _SxAccountScreenState extends State<SxAccountScreen> {
  Map<String, dynamic> me = {}; List<Map<String, dynamic>> orders = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      me = Map<String, dynamic>.from((await api.me())['item'] ?? {});
      orders = await api.orders();
      state.wishlist = (await api.wishlistIds()).toSet();
      await state.restorePreferences();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.fromLTRB(11, 13, 11, 18), children: [
        SafeArea(bottom: false, child: Row(children: [
          const Text('أنا', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const Spacer(),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxSettingsScreen(me: me))), icon: const Icon(Icons.settings_outlined)),
        ])),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15)),
          child: Row(children: [
            Container(width: 58, height: 58, decoration: const BoxDecoration(color: Color(0xFF4A4A4A), shape: BoxShape.circle), child: const Icon(Icons.person, color: Colors.white)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(sxText(me['name'], 'مرحبًا بك'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4), Text(sxText(me['phone_normalized']), style: const TextStyle(color: Colors.white70, fontSize: 9)),
              const SizedBox(height: 7), const Text('تعديل الحساب', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
            ])),
          ]),
        ),
        const SxSectionTitle(title: 'طلباتي'),
        const Row(children: [
          Expanded(child: _AccountMini(Icons.payment_outlined, 'بانتظار الدفع')),
          Expanded(child: _AccountMini(Icons.inventory_2_outlined, 'قيد التجهيز')),
          Expanded(child: _AccountMini(Icons.local_shipping_outlined, 'تم الشحن')),
          Expanded(child: _AccountMini(Icons.rate_review_outlined, 'للمراجعة')),
        ]),
        const SxSectionTitle(title: 'خدماتي'),
        GridView.count(primary: false, shrinkWrap: true, crossAxisCount: 4, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: .94, children: [
          _AccountTile(Icons.receipt_long_outlined, 'طلباتي', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxOrdersScreen()))),
          _AccountTile(Icons.favorite_border, 'المفضلة', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxWishlistScreen()))),
          _AccountTile(Icons.location_on_outlined, 'العناوين', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxAddressesScreen()))),
          _AccountTile(Icons.notifications_none, 'الإشعارات', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxNotificationsScreen()))),
          _AccountTile(Icons.chat_bubble_outline, 'الدعم', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxSupportScreen()))),
          _AccountTile(Icons.local_offer_outlined, 'الكوبونات', () {}),
          _AccountTile(Icons.stars_outlined, 'النقاط', () {}),
          _AccountTile(Icons.auto_awesome_outlined, 'الإطلالات', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxLooksScreen()))),
        ]),
        const SxSectionTitle(title: 'تفضيلات التسوق'),
        ListTile(leading: const Icon(Icons.currency_exchange), title: const Text('العملة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), subtitle: Text(state.currencyCode, style: const TextStyle(fontSize: 9, color: ClientTheme.muted)), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxCurrencyScreen()))),
        ListTile(leading: const Icon(Icons.location_city_outlined), title: const Text('المدينة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), subtitle: Text(state.cityName ?? 'اختيار المدينة', style: const TextStyle(fontSize: 9, color: ClientTheme.muted)), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxCityScreen()))),
        ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('العناوين', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxAddressesScreen()))),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () async { await state.clearSession(); if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SxAuthScreen()), (_) => false); }, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(47), side: const BorderSide(color: Colors.black), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)), child: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w900))),
      ]),
    ),
  );
}
class _AccountMini extends StatelessWidget {
  final IconData icon; final String label;
  const _AccountMini(this.icon, this.label);
  @override Widget build(BuildContext context) => Column(children: [Icon(icon, size: 19, color: const Color(0xFF586574)), const SizedBox(height: 4), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700))]);
}
class _AccountTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback tap;
  const _AccountTile(this.icon, this.label, this.tap);
  @override Widget build(BuildContext context) => InkWell(onTap: tap, child: Container(
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: ClientTheme.border), borderRadius: BorderRadius.circular(5)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 21), const SizedBox(height: 5), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.8, fontWeight: FontWeight.w700))]),
  ));
}

class SxSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> me;
  const SxSettingsScreen({super.key, required this.me});
  @override State<SxSettingsScreen> createState() => _SxSettingsScreenState();
}
class _SxSettingsScreenState extends State<SxSettingsScreen> {
  late TextEditingController name, email; bool busy = false;
  @override void initState() { super.initState(); name = TextEditingController(text: sxText(widget.me['name'])); email = TextEditingController(text: sxText(widget.me['email'])); }
  @override void dispose() { name.dispose(); email.dispose(); super.dispose(); }
  Future<void> save() async {
    setState(() => busy = true);
    try { await api.updateMe({'name': name.text.trim(), 'email': email.text.trim()}); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البيانات'))); Navigator.pop(context); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) => SxShellPage(title: 'الإعدادات', back: true, child: ListView(padding: const EdgeInsets.all(13), children: [
    const Text('الحساب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
    TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')), const SizedBox(height: 7),
    TextField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')), const SizedBox(height: 12),
    SizedBox(height: 48, child: FilledButton(onPressed: busy ? null : save, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: busy ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('حفظ التعديلات'))),
    const SizedBox(height: 18), const Text('الإعدادات السريعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
    ListTile(leading: const Icon(Icons.currency_exchange), title: const Text('العملة'), subtitle: Text(state.currencyCode), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxCurrencyScreen()))),
    ListTile(leading: const Icon(Icons.location_city_outlined), title: const Text('المدينة'), subtitle: Text(state.cityName ?? 'اختيار المدينة'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxCityScreen()))),
    ListTile(leading: const Icon(Icons.notifications_none), title: const Text('الإشعارات'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxNotificationsScreen()))),
  ]));
}

class SxCurrencyScreen extends StatefulWidget {
  const SxCurrencyScreen({super.key});
  @override State<SxCurrencyScreen> createState() => _SxCurrencyScreenState();
}
class _SxCurrencyScreenState extends State<SxCurrencyScreen> {
  List<Map<String, dynamic>> rows = []; bool loading = true;
  @override void initState() { super.initState(); api.currencies().then((v) { if (mounted) setState(() { rows = v; loading = false; }); }).catchError((_) { if (mounted) setState(() => loading = false); }); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'العملة', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView.builder(
    itemCount: rows.length,
    itemBuilder: (_, i) {
      final x = rows[i]; final id = sxInt(x['id']);
      final selected = state.currencyId == id || (state.currencyId == null && sxText(x['code']) == 'SAR');
      return ListTile(
        title: Text(sxText(x['name_ar'], sxText(x['code'])), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        subtitle: Text(sxText(x['code']), style: const TextStyle(fontSize: 9)),
        trailing: selected ? const Icon(Icons.check) : null,
        onTap: () async {
          try {
            await state.setCurrency(
              id: id,
              code: sxText(x['code'], 'SAR'),
              symbol: sxText(x['symbol'], sxText(x['code'], 'SAR')),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حفظ العملة')),
              );
              Navigator.pop(context);
            }
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(sxText(e))),
            );
          }
        },
      );
    },
  ));
}

class SxCityScreen extends StatefulWidget {
  const SxCityScreen({super.key});
  @override State<SxCityScreen> createState() => _SxCityScreenState();
}
class _SxCityScreenState extends State<SxCityScreen> {
  List<Map<String, dynamic>> rows = [], filtered = []; final search = TextEditingController(); bool loading = true;
  @override void initState() { super.initState(); api.cities().then((v) { if (mounted) setState(() { rows = v; filtered = v; loading = false; }); }).catchError((_) { if (mounted) setState(() => loading = false); }); }
  @override void dispose() { search.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'المدينة', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : Column(children: [
    Padding(padding: const EdgeInsets.all(10), child: SxSearchBar(controller: search, hint: 'ابحث عن مدينتك', onChanged: (q) => setState(() => filtered = q.trim().isEmpty ? rows : rows.where((x) => sxText(x['name']).contains(q.trim())).toList()))),
    Expanded(child: ListView.separated(itemCount: filtered.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) => ListTile(
      title: Text(sxText(filtered[i]['name']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      trailing: state.cityId == sxInt(filtered[i]['id']) ? const Icon(Icons.check) : null,
      onTap: () async {
        try { final id = sxInt(filtered[i]['id']); await state.setCity(id: id, name: sxText(filtered[i]['name'])); if (mounted) Navigator.pop(context); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
      },
    ))),
  ]));
}

class SxAddressesScreen extends StatefulWidget {
  const SxAddressesScreen({super.key});
  @override State<SxAddressesScreen> createState() => _SxAddressesScreenState();
}

class _SxAddressesScreenState extends State<SxAddressesScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await api.addresses();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> openForm({Map<String, dynamic>? initial}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => SxAddressForm(initial: initial),
    );
    if (result == null) return;
    try {
      if (initial == null) {
        await api.addAddress(result);
      } else {
        await api.updateAddress(sxInt(initial['id']), result);
      }
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(initial == null ? 'تمت إضافة العنوان' : 'تم حفظ العنوان')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e))),
      );
    }
  }

  Future<void> makeDefault(Map<String, dynamic> address) async {
    try {
      await api.updateAddress(sxInt(address['id']), {'is_default': true});
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e))),
      );
    }
  }

  Future<void> remove(Map<String, dynamic> address) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف العنوان', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text('هل تريد حذف هذا العنوان؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.deleteAddress(sxInt(address['id']));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e))),
      );
    }
  }

  String addressLine(Map<String, dynamic> x) {
    return [
      sxText(x['country_name']),
      sxText(x['region_name']),
      sxText(x['city_name']),
      sxText(x['city_area_name']),
      sxText(x['district']),
      sxText(x['street']),
      sxText(x['landmark']),
    ].where((v) => v.trim().isNotEmpty).join(' • ');
  }

  @override
  Widget build(BuildContext context) => SxShellPage(
    title: 'العناوين',
    back: true,
    child: loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : ListView(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: ClientTheme.soft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 19),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'احفظ أكثر من عنوان واختر عنوانًا افتراضيًا. يمكنك تحديد المدينة والمنطقة من بيانات الخادم وإضافة تفاصيل أدق يدويًا.',
                        style: TextStyle(fontSize: 9, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 55),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.location_off_outlined, size: 45, color: Color(0xFF909090)),
                      const SizedBox(height: 9),
                      const Text('لا توجد عناوين محفوظة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      const Text('أضف عنوانك الأول لتسهيل إتمام الطلبات.', style: TextStyle(fontSize: 9, color: ClientTheme.muted)),
                    ],
                  ),
                )
              else
                for (final x in rows)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(10, 11, 10, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: x['is_default'] == true ? Colors.black : ClientTheme.border,
                        width: x['is_default'] == true ? 1.1 : .7,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 39,
                              height: 39,
                              decoration: const BoxDecoration(
                                color: ClientTheme.soft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_on_outlined, size: 20),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          sxText(x['recipient_name'], 'المستلم'),
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                      if (x['is_default'] == true)
                                        const SxPill(
                                          text: 'العنوان الافتراضي',
                                          background: Colors.black,
                                          foreground: Colors.white,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    sxText(x['phone']),
                                    style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            addressLine(x).isEmpty ? 'لم تتم إضافة تفاصيل العنوان بعد' : addressLine(x),
                            style: const TextStyle(fontSize: 9, height: 1.55),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () => openForm(initial: x),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('تعديل', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: x['is_default'] == true ? null : () => makeDefault(x),
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: const Text('جعله افتراضيًا', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                              ),
                            ),
                            IconButton(
                              onPressed: () => remove(x),
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 2),
              SizedBox(
                height: 49,
                child: OutlinedButton.icon(
                  onPressed: () => openForm(),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 19),
                  label: const Text('إضافة عنوان جديد', style: TextStyle(fontWeight: FontWeight.w900)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                ),
              ),
            ],
          ),
  );
}


class SxOrdersScreen extends StatefulWidget {
  const SxOrdersScreen({super.key});
  @override State<SxOrdersScreen> createState() => _SxOrdersScreenState();
}

class _SxOrdersScreenState extends State<SxOrdersScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String filter = 'all';

  static const filters = <String, String>{
    'all': 'الكل',
    'payment': 'قيد الدفع',
    'processing': 'قيد التجهيز',
    'shipped': 'تم الشحن',
    'completed': 'مكتملة',
    'cancelled': 'ملغاة',
  };

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await api.orders();
      if (mounted) {
        setState(() {
          rows = next;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  bool matches(Map<String, dynamic> row, String key) {
    final status = sxText(row['status']);
    final payment = sxText(row['payment_status']);
    switch (key) {
      case 'payment':
        return status == 'awaiting_payment' || payment == 'unpaid';
      case 'processing':
        return status == 'created' || status == 'paid' || status == 'processing';
      case 'shipped':
        return status == 'shipped';
      case 'completed':
        return status == 'delivered' || status == 'returned';
      case 'cancelled':
        return status == 'cancelled';
      default:
        return true;
    }
  }

  String statusLabel(String status) {
    const labels = <String, String>{
      'created': 'تم إنشاء الطلب',
      'awaiting_payment': 'بانتظار الدفع',
      'paid': 'تم الدفع',
      'processing': 'قيد التجهيز',
      'shipped': 'تم الشحن',
      'delivered': 'تم التسليم',
      'returned': 'تمت الإعادة',
      'cancelled': 'ملغى',
    };
    return labels[status] ?? status;
  }

  Color statusBg(String status) {
    if (status == 'delivered') return const Color(0xFFEAF7F0);
    if (status == 'cancelled') return const Color(0xFFFFEEEE);
    if (status == 'shipped') return const Color(0xFFEFF4FF);
    return const Color(0xFFF5F5F5);
  }

  Color statusFg(String status) {
    if (status == 'delivered') return const Color(0xFF18794E);
    if (status == 'cancelled') return const Color(0xFFC62828);
    if (status == 'shipped') return const Color(0xFF315BA6);
    return const Color(0xFF4B4B4B);
  }

  String dateText(String value) {
    if (value.isEmpty) return '';
    try {
      final d = DateTime.parse(value).toLocal();
      return d.day.toString().padLeft(2, '0') + '/' +
          d.month.toString().padLeft(2, '0') + '/' +
          d.year.toString();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((x) => matches(x, filter)).toList();
    return SxShellPage(
      title: 'طلباتي',
      back: true,
      child: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 22),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: ClientTheme.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Row(
                        children: filters.entries.map((entry) {
                          final active = filter == entry.key;
                          final count = rows.where((x) => matches(x, entry.key)).length;
                          return Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: ChoiceChip(
                              label: Text(
                                entry.value + ' ' + count.toString(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: active ? Colors.white : Colors.black,
                                ),
                              ),
                              selected: active,
                              onSelected: (_) => setState(() => filter = entry.key),
                              selectedColor: Colors.black,
                              backgroundColor: ClientTheme.soft,
                              side: BorderSide.none,
                              showCheckmark: false,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (visible.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 46, color: Color(0xFF909090)),
                          const SizedBox(height: 10),
                          Text(
                            filter == 'all' ? 'لا توجد طلبات بعد' : 'لا توجد طلبات في هذا القسم',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'ستظهر هنا حالة طلباتك وتفاصيلها وتحديثات الشحن.',
                            style: TextStyle(fontSize: 9.5, color: ClientTheme.muted),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final row in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SxOrderDetailScreen(id: sxInt(row['id'])),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: ClientTheme.border),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: const BoxDecoration(
                                          color: ClientTheme.soft,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.shopping_bag_outlined, size: 18),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              'طلب ' + sxText(row['order_no'], '#'),
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              dateText(sxText(row['created_at'])),
                                              style: const TextStyle(fontSize: 8.2, color: ClientTheme.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusBg(sxText(row['status'])),
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        child: Text(
                                          statusLabel(sxText(row['status'])),
                                          style: TextStyle(fontSize: 8.2, fontWeight: FontWeight.w800, color: statusFg(sxText(row['status']))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  finalPreview(row),
                                  const Divider(height: 16),
                                  Row(
                                    children: [
                                      Text(
                                        sxInt(row['item_count']).toString() +
                                            (sxInt(row['item_count']) == 1 ? ' قطعة' : ' قطع'),
                                        style: const TextStyle(fontSize: 8.7, color: ClientTheme.muted),
                                      ),
                                      const Spacer(),
                                      Text(
                                        sxText(row['total'], '0') + ' ' +
                                            (row['currency'] is Map
                                                ? sxText((row['currency'] as Map)['symbol'], state.currencySymbol)
                                                : state.currencySymbol),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(width: 5),
                                      const Icon(Icons.chevron_left, size: 19),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget finalPreview(Map<String, dynamic> row) {
    final items = sxMaps(row['items_preview']);
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('تفاصيل المنتجات داخل الطلب', style: TextStyle(fontSize: 9, color: ClientTheme.muted)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            for (int i = 0; i < items.take(4).length; i++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(
                    color: ClientTheme.soft,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SxImage(url: items[i]['image_url'], fit: BoxFit.cover),
                ),
              ),
            if (items.length > 4)
              Container(
                width: 40,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ClientTheme.soft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '+' + (items.length - 4).toString(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SxOrderDetailScreen extends StatefulWidget {
  final int id;
  const SxOrderDetailScreen({super.key, required this.id});
  @override State<SxOrderDetailScreen> createState() => _SxOrderDetailScreenState();
}

class _SxOrderDetailScreenState extends State<SxOrderDetailScreen> {
  Map<String, dynamic> order = {};
  bool loading = true;

  static const stages = <String>[
    'created',
    'processing',
    'shipped',
    'delivered',
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final v = await api.order(widget.id);
      final item = v['item'] is Map ? v['item'] : v;
      if (mounted) setState(() {
        order = Map<String, dynamic>.from(item);
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  String statusLabel(String status) {
    const labels = <String, String>{
      'created': 'تم إنشاء الطلب',
      'awaiting_payment': 'بانتظار الدفع',
      'paid': 'تم الدفع',
      'processing': 'قيد التجهيز',
      'shipped': 'تم الشحن',
      'delivered': 'تم التسليم',
      'returned': 'تمت الإعادة',
      'cancelled': 'ملغى',
    };
    return labels[status] ?? status;
  }

  int progressIndex(String status) {
    if (status == 'delivered' || status == 'returned') return 3;
    if (status == 'shipped') return 2;
    if (status == 'paid' || status == 'processing') return 1;
    return 0;
  }

  Future<void> openOrderChat() async {
    try {
      final result = await api.newConversation(
        type: 'order',
        orderId: widget.id,
        subject: 'استفسار عن الطلب ' + sxText(order['order_no'], '#'),
      );
      final item = result['item'] is Map ? result['item'] : result;
      final id = sxInt(item is Map ? item['id'] : 0);
      if (!mounted || id <= 0) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SxConversationScreen(
            conversationId: id,
            title: 'طلب ' + sxText(order['order_no'], '#'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));

    final status = sxText(order['status']);
    final currency = order['currency'] is Map
        ? sxText((order['currency'] as Map)['symbol'], state.currencySymbol)
        : state.currencySymbol;
    final address = order['address_snapshot'] is Map
        ? Map<String, dynamic>.from(order['address_snapshot'])
        : <String, dynamic>{};
    final items = sxMaps(order['items']);
    final histories = sxMaps(order['status_history']);
    final shipments = sxMaps(order['shipments']);

    return SxShellPage(
      title: 'تفاصيل الطلب',
      back: true,
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 25),
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: ClientTheme.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'طلب ' + sxText(order['order_no'], '#'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                        ),
                      ),
                      SxPill(
                        text: statusLabel(status),
                        background: status == 'cancelled' ? const Color(0xFFFFEEEE) : ClientTheme.soft,
                        foreground: status == 'cancelled' ? const Color(0xFFC62828) : Colors.black,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (status == 'cancelled')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('تم إلغاء هذا الطلب.', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    )
                  else
                    Row(
                      children: List.generate(stages.length, (i) {
                        final active = progressIndex(status) >= i;
                        return Expanded(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  if (i > 0)
                                    Expanded(
                                      child: Container(
                                        height: 2,
                                        color: progressIndex(status) >= i ? Colors.black : ClientTheme.border,
                                      ),
                                    ),
                                  Container(
                                    width: 25,
                                    height: 25,
                                    decoration: BoxDecoration(
                                      color: active ? Colors.black : Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: active ? Colors.black : ClientTheme.border),
                                    ),
                                    child: active
                                        ? const Icon(Icons.check, color: Colors.white, size: 13)
                                        : Text((i + 1).toString(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800)),
                                  ),
                                  if (i < stages.length - 1)
                                    Expanded(
                                      child: Container(
                                        height: 2,
                                        color: progressIndex(status) > i ? Colors.black : ClientTheme.border,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                const ['الطلب', 'التجهيز', 'الشحن', 'التسليم'][i],
                                style: TextStyle(fontSize: 8.2, fontWeight: active ? FontWeight.w900 : FontWeight.w500, color: active ? Colors.black : ClientTheme.muted),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  const SizedBox(height: 9),
                  Text(
                    'الدفع: ' + sxText(order['payment_status'], 'غير محدد') +
                        '  •  الشحن: ' + sxText(order['shipping_status'], 'غير محدد'),
                    style: const TextStyle(fontSize: 8.7, color: ClientTheme.muted),
                  ),
                ],
              ),
            ),
            const SxSectionTitle(title: 'المنتجات'),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: ClientTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++)
                    Builder(builder: (_) {
                      final item = items[i];
                      final media = sxMaps(item['media']);
                      final image = media.isNotEmpty ? media.first['url'] : item['image_url'];
                      final variant = item['variant_display'] is Map
                          ? Map<String, dynamic>.from(item['variant_display'])
                          : <String, dynamic>{};
                      final color = variant['color'] is Map
                          ? Map<String, dynamic>.from(variant['color'])
                          : null;
                      final size = variant['size'] is Map
                          ? Map<String, dynamic>.from(variant['size'])
                          : null;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(9),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 78,
                                  height: 96,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: SxImage(url: image),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        sxText(item['name'], 'منتج'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10.8, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 6),
                                      if (color != null)
                                        Text('اللون: ' + sxText(color['name']), style: const TextStyle(fontSize: 8.7, color: ClientTheme.muted)),
                                      if (size != null)
                                        Text('المقاس: ' + sxText(size['label'], sxText(size['code'])), style: const TextStyle(fontSize: 8.7, color: ClientTheme.muted)),
                                      for (final option in sxMaps(item['options']))
                                        Text(
                                          sxText(option['name']) + ': ' + sxText(option['value']),
                                          style: const TextStyle(fontSize: 8.7, color: ClientTheme.muted),
                                        ),
                                      const SizedBox(height: 7),
                                      Row(
                                        children: [
                                          Text(
                                            '×' + sxInt(item['qty'], 1).toString(),
                                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
                                          ),
                                          const Spacer(),
                                          Text(
                                            sxText(item['sale_price_display'], '0') + ' ' + currency,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < items.length - 1) const Divider(height: 1),
                        ],
                      );
                    }),
                ],
              ),
            ),
            const SxSectionTitle(title: 'ملخص الدفع'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: ClientTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _OrderAmountRow('قيمة المنتجات', sxText(order['subtotal'], '0') + ' ' + currency),
                  _OrderAmountRow('الخصم', sxText(order['discount'], '0') + ' ' + currency),
                  _OrderAmountRow('الشحن', sxText(order['shipping'], '0') + ' ' + currency),
                  const Divider(height: 17),
                  _OrderAmountRow('الإجمالي', sxText(order['total'], '0') + ' ' + currency, strong: true),
                ],
              ),
            ),
            const SxSectionTitle(title: 'عنوان التسليم'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: ClientTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 19),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          sxText(address['recipient_name'], 'عنوان التسليم'),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      sxText(address['country_name']),
                      sxText(address['region_name']),
                      sxText(address['city_name']),
                      sxText(address['city_area_name']),
                      sxText(address['district']),
                      sxText(address['street']),
                      sxText(address['landmark']),
                    ].where((x) => x.trim().isNotEmpty).join(' • '),
                    style: const TextStyle(fontSize: 9, color: ClientTheme.muted, height: 1.55),
                  ),
                  const SizedBox(height: 3),
                  Text(sxText(address['phone']), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (histories.isNotEmpty) ...[
              const SxSectionTitle(title: 'تحديثات الطلب'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: ClientTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    for (final h in histories)
                      ListTile(
                        dense: true,
                        leading: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(color: ClientTheme.soft, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 14),
                        ),
                        title: Text(statusLabel(sxText(h['to_status'])), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                        subtitle: Text(sxText(h['note']), style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted)),
                        trailing: Text(_formatDateTime(sxText(h['created_at'])), style: const TextStyle(fontSize: 7.8, color: ClientTheme.muted)),
                      ),
                  ],
                ),
              ),
            ],
            if (shipments.isNotEmpty) ...[
              const SxSectionTitle(title: 'تتبع الشحنة'),
              for (final shipment in shipments)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: ClientTheme.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_shipping_outlined, size: 18),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              sxText(shipment['tracking_no'], 'الشحنة'),
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                            ),
                          ),
                          SxPill(
                            text: sxText(shipment['status'], 'قيد التجهيز'),
                            background: ClientTheme.soft,
                            foreground: Colors.black,
                          ),
                        ],
                      ),
                      if (sxText(shipment['tracking_no']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            'رقم التتبع: ' + sxText(shipment['tracking_no']),
                            style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted),
                          ),
                        ),
                      for (final event in sxMaps(shipment['events']))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.radio_button_checked, size: 11),
                          title: Text(sxText(event['status']), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            [sxText(event['location']), sxText(event['description'])]
                                .where((x) => x.trim().isNotEmpty)
                                .join(' • '),
                            style: const TextStyle(fontSize: 8, color: ClientTheme.muted),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              height: 47,
              child: OutlinedButton.icon(
                onPressed: openOrderChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text(
                  'التواصل مع خدمة العملاء حول الطلب',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderAmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _OrderAmountRow(this.label, this.value, {this.strong = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 9.5, fontWeight: strong ? FontWeight.w900 : FontWeight.w500),
          ),
        ),
        Text(value, style: TextStyle(fontSize: strong ? 15 : 10, fontWeight: FontWeight.w900)),
      ],
    ),
  );
}

class SxWishlistScreen extends StatefulWidget {
  const SxWishlistScreen({super.key});
  @override State<SxWishlistScreen> createState() => _SxWishlistScreenState();
}
class _SxWishlistScreenState extends State<SxWishlistScreen> {
  List<ProductModel> products = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final ids = await api.wishlistIds(); state.wishlist = ids.toSet(); final all = await api.feed(currencyId: state.currencyId); products = all.where((x) => ids.contains(x.id)).toList(); } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) => SxShellPage(title: 'المفضلة', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView(padding: const EdgeInsets.fromLTRB(7, 8, 7, 20), children: [SxProductGrid(products: products)]));
}

class SxNotificationsScreen extends StatefulWidget {
  const SxNotificationsScreen({super.key});
  @override State<SxNotificationsScreen> createState() => _SxNotificationsScreenState();
}
class _SxNotificationsScreenState extends State<SxNotificationsScreen> {
  List<Map<String, dynamic>> rows = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final me = Map<String, dynamic>.from((await api.me())['item'] ?? {}); final id = sxInt(me['id']); if (id > 0) rows = await api.notifications(id); } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) => SxShellPage(title: 'الإشعارات', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : rows.isEmpty ? const Center(child: Text('لا توجد إشعارات جديدة')) : ListView.separated(
    itemCount: rows.length, separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (_, i) => ListTile(
      leading: const CircleAvatar(backgroundColor: ClientTheme.soft, child: Icon(Icons.notifications_none, color: Colors.black)),
      title: Text(sxText(rows[i]['title'], 'إشعار'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
      subtitle: Text(sxText(rows[i]['body'], sxText(rows[i]['message'])), style: const TextStyle(fontSize: 9)),
    ),
  ));
}


class SxSupportScreen extends StatefulWidget {
  const SxSupportScreen({super.key});
  @override State<SxSupportScreen> createState() => _SxSupportScreenState();
}

class _SxSupportScreenState extends State<SxSupportScreen> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await api.conversations();
      if (mounted) setState(() {
        rows = next;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic>? get supportConversation {
    for (final row in rows) {
      if (sxText(row['type']) == 'customer_service' && row['order_id'] == null) {
        return row;
      }
    }
    return null;
  }

  Future<void> openSupport() async {
    try {
      var row = supportConversation;
      if (row == null) {
        final result = await api.newConversation();
        row = Map<String, dynamic>.from(result['item'] is Map ? result['item'] : result);
      }
      final id = sxInt(row?['id']);
      if (!mounted || id <= 0) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SxConversationScreen(
            conversationId: id,
            title: 'خدمة العملاء',
          ),
        ),
      );
      load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = supportConversation;
    final others = rows.where((x) => x != support).toList();

    return SxShellPage(
      title: 'المحادثات والدعم',
      back: true,
      child: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
                children: [
                  InkWell(
                    onTap: openSupport,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.black, Color(0xFF303030)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.support_agent, color: Colors.white, size: 25),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('خدمة العملاء', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                                SizedBox(height: 3),
                                Text('تواصل معنا مباشرة لأي استفسار أو مساعدة', style: TextStyle(color: Colors.white70, fontSize: 9.5, height: 1.35)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_left, color: Colors.white, size: 23),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('محادثاتي', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      ),
                      Text(
                        others.length.toString(),
                        style: const TextStyle(fontSize: 9, color: ClientTheme.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (others.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 35),
                      alignment: Alignment.center,
                      child: const Text(
                        'لا توجد محادثات إضافية.\nيمكنك بدء محادثة مرتبطة بأي طلب من تفاصيله.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9.5, color: ClientTheme.muted, height: 1.5),
                      ),
                    )
                  else
                    for (final row in others)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SxConversationScreen(
                                  conversationId: sxInt(row['id']),
                                  title: row['order_id'] == null
                                      ? sxText(row['subject'], 'محادثة')
                                      : 'طلب ' + sxText(row['order_id']),
                                ),
                              ),
                            );
                            load();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: ClientTheme.border),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: ClientTheme.soft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    row['order_id'] == null
                                        ? Icons.chat_bubble_outline
                                        : Icons.receipt_long_outlined,
                                    size: 21,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        row['order_id'] == null
                                            ? sxText(row['subject'], 'محادثة')
                                            : 'استفسار عن الطلب ' + sxText(row['order_id']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11.2, fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        sxText(row['status'], 'مفتوحة'),
                                        style: const TextStyle(fontSize: 8.8, color: ClientTheme.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_left, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

class SxConversationScreen extends StatefulWidget {
  final int conversationId;
  final String title;
  const SxConversationScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });
  @override State<SxConversationScreen> createState() => _SxConversationScreenState();
}

class _SxConversationScreenState extends State<SxConversationScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await api.messages(widget.conversationId);
      if (mounted) setState(() {
        messages = next;
        loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.jumpTo(scroll.position.maxScrollExtent);
    });
  }

  Future<void> send() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    setState(() => sending = true);
    input.clear();
    try {
      await api.sendMessage(widget.conversationId, body);
      await load();
    } catch (e) {
      input.text = body;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sxText(e))),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F6F6),
    appBar: AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
            child: const Icon(Icons.support_agent, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: load,
          icon: const Icon(Icons.refresh_outlined, size: 20),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'ابدأ المحادثة برسالة قصيرة، وسنرد عليك هنا.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: ClientTheme.muted),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(10, 15, 10, 18),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final message = messages[i];
                          final mine = sxText(message['sender_type']) == 'customer';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!mine)
                                    Container(
                                      width: 29,
                                      height: 29,
                                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                      child: const Icon(Icons.support_agent, color: Colors.white, size: 15),
                                    ),
                                  if (!mine) const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .76),
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
                                      decoration: BoxDecoration(
                                        color: mine ? Colors.black : Colors.white,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(14),
                                          topRight: const Radius.circular(14),
                                          bottomLeft: Radius.circular(mine ? 14 : 4),
                                          bottomRight: Radius.circular(mine ? 4 : 14),
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x11000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            sxText(message['body'], message['message_type'] == 'attachment' ? 'مرفق' : ''),
                                            style: TextStyle(
                                              color: mine ? Colors.white : Colors.black,
                                              fontSize: 10.5,
                                              height: 1.45,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _formatDateTime(sxText(message['created_at'])),
                                            textAlign: TextAlign.end,
                                            style: TextStyle(
                                              color: mine ? Colors.white70 : ClientTheme.muted,
                                              fontSize: 7.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: ClientTheme.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'اكتب رسالتك...',
                            suffixIcon: sending
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    onPressed: send,
                                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
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
  );
}

class SxLooksScreen extends StatefulWidget {
  const SxLooksScreen({super.key});
  @override State<SxLooksScreen> createState() => _SxLooksScreenState();
}
class _SxLooksScreenState extends State<SxLooksScreen> {
  List<Map<String, dynamic>> rows = []; bool loading = true;
  @override void initState() { super.initState(); api.home().then((v) { if (mounted) setState(() { rows = sxMaps(v['looks']); loading = false; }); }).catchError((_) { if (mounted) setState(() => loading = false); }); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'الإطلالات', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView(padding: const EdgeInsets.all(9), children: [
    GridView.builder(primary: false, shrinkWrap: true, itemCount: rows.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 7, mainAxisSpacing: 8, childAspectRatio: .68), itemBuilder: (_, i) => InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxLookDetail(look: rows[i]))),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Stack(fit: StackFit.expand, children: [
        SxImage(url: rows[i]['cover_url']),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(color: Colors.black.withOpacity(.62), padding: const EdgeInsets.all(8), child: Text(sxText(rows[i]['name']), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)))),
      ])),
    )),
  ]));
}
class SxLookDetail extends StatelessWidget {
  final Map<String, dynamic> look; const SxLookDetail({super.key, required this.look});
  @override Widget build(BuildContext context) {
    final products = sxMaps(look['products']).map((x) => x['product']).whereType<Map>().map((x) => ProductModel.fromJson(Map<String, dynamic>.from(x))).toList();
    return SxShellPage(title: sxText(look['name'], 'الإطلالة'), back: true, child: ListView(children: [
      SizedBox(height: 370, child: SxImage(url: look['cover_url'])),
      Padding(padding: const EdgeInsets.all(14), child: Text(sxText(look['description']), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.5))),
      const SxSectionTitle(title: 'تسوق الإطلالة'), Padding(padding: const EdgeInsets.fromLTRB(7, 0, 7, 20), child: SxProductGrid(products: products)),
    ]));
  }
}

String _formatDateTime(String value) {
  if (value.trim().isEmpty) return '';
  try {
    final d = DateTime.parse(value).toLocal();
    return d.day.toString().padLeft(2, '0') + '/' +
        d.month.toString().padLeft(2, '0') + ' ' +
        d.hour.toString().padLeft(2, '0') + ':' +
        d.minute.toString().padLeft(2, '0');
  } catch (_) {
    return '';
  }
}

class SxAuthScreen extends StatefulWidget {
  const SxAuthScreen({super.key});
  @override State<SxAuthScreen> createState() => _SxAuthScreenState();
}
class _SxAuthScreenState extends State<SxAuthScreen> {
  final phone = TextEditingController(); bool busy = false;
  Future<void> send() async {
    if (phone.text.trim().isEmpty) return; setState(() => busy = true);
    try { final r = await api.requestOtp(phone.text.trim()); final id = sxInt(r['otp_request_id']); if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => SxOtpScreen(requestId: id, phone: phone.text.trim()))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { phone.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.white, body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(22, 30, 22, 25), children: [
    const SizedBox(height: 70), const Text('التخفيض الصح', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8), const Text('تسوق سريع، اكتشاف أسهل، وعروض في مكان واحد.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: ClientTheme.muted)),
    const SizedBox(height: 45), const Text('تسجيل الدخول', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(prefixText: '+967 ', hintText: '7XXXXXXXX')),
    const SizedBox(height: 11), SizedBox(height: 50, child: FilledButton(onPressed: busy ? null : send, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: busy ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('إرسال رمز التحقق'))),
  ])));
}

class SxOtpScreen extends StatefulWidget {
  final int requestId; final String phone;
  const SxOtpScreen({super.key, required this.requestId, required this.phone});
  @override State<SxOtpScreen> createState() => _SxOtpScreenState();
}
class _SxOtpScreenState extends State<SxOtpScreen> {
  final code = TextEditingController(); bool busy = false;
  Future<void> verify() async {
    setState(() => busy = true);
    try { await api.verifyOtp(widget.requestId, code.text.trim(), phone: widget.phone); await state.restorePreferences(); if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SxAppShell()), (_) => false); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
    if (mounted) setState(() => busy = false);
  }
  @override void dispose() { code.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'التحقق', back: true, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SizedBox(height: 20), const Text('أدخل رمز التحقق', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 5),
    Text('تم الإرسال إلى ' + widget.phone, style: const TextStyle(fontSize: 11, color: ClientTheme.muted)), const SizedBox(height: 15),
    TextField(controller: code, maxLength: 6, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 8)),
    SizedBox(height: 49, child: FilledButton(onPressed: busy ? null : verify, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: busy ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('تأكيد الدخول'))),
  ])));
}
