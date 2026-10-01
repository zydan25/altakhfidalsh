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
  });
  @override Widget build(BuildContext context) => SizedBox(
    height: 43,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      readOnly: onTap != null && controller == null,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.black, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black54, fontSize: 13),
        // Keep the search icon on the visual left side of the RTL field.
        prefixIcon: null,
        suffixIcon: const Icon(Icons.search, size: 22, color: Colors.black),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        filled: true,
        fillColor: backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: borderColor, width: .8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: borderColor, width: .8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: borderColor, width: 1.1),
        ),
      ),
    ),
  );
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
                  rootCategories: roots.take(10).toList(),
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
                  child: SxProductGrid(products: products),
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
  final Color categoryTextColor;
  final Color categoryActiveColor;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch, onWishlist, onNotifications;

  const _HomeFixedHeader({
    required this.roots,
    required this.selected,
    required this.solidBackground,
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
              height: 48,
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
                            borderColor: solidBackground
                                ? const Color(0xFF111111)
                                : Colors.transparent,
                            backgroundColor:
                                solidBackground ? Colors.white : Colors.transparent,
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
            SizedBox(
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
    final target = targets.isEmpty ? <String, dynamic>{} : targets.first;
    final type = sxText(target['type']);
    final id = sxInt(target['id']);
    Widget destination;

    if (type == 'product' && id > 0) {
      destination = SxProductScreen(id: id);
    } else if (type == 'category' && id > 0) {
      destination = SxResults(
        title: sxText(target['name'], sxText(widget.banner['title'], 'العروض')),
        categoryId: id,
      );
    } else if ((type == 'circle' || type == 'side_category_circle') && id > 0) {
      destination = SxResults(
        title: sxText(target['name'], sxText(widget.banner['title'], 'العروض')),
        circleId: id,
      );
    } else if (type == 'hashtag' && id > 0) {
      destination = SxResults(
        title: sxText(target['name'], sxText(widget.banner['title'], 'العروض')),
        hashtagId: id,
      );
    } else {
      destination = SxResults(title: sxText(widget.banner['title'], 'العروض'));
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
    final rootIds = rootCategories.map((category) => category.id).toSet();

    // The root tabs already represent parent categories. The circle grid
    // therefore starts at their children; when a root is selected, every
    // descendant can be shown according to the configured row count.
    final categories = selectedRootId < 0
        ? (allCategories
              .where((category) =>
                  category.parentId != null &&
                  rootIds.contains(category.parentId))
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

  const SxProductGrid({
    super.key,
    required this.products,
    this.masonry = false,
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
      return _SxMasonryProductGrid(products: products);
    }

    return Container(
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
          ),
        ),
      ),
    );
  }
}

class _SxMasonryProductGrid extends StatelessWidget {
  final List<ProductModel> products;

  const _SxMasonryProductGrid({required this.products});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - 5) / 2;
        final columns = <List<ProductModel>>[[], []];
        final heights = <double>[0, 0];

        for (final product in products) {
          final ratio = sxProductImageRatio(product);
          final estimatedHeight = columnWidth / ratio + 112;
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
              ),
              if (i != rows.length - 1) const SizedBox(height: 7),
            ],
          ],
        );

        return Container(
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
        );
      },
    );
  }
}

class SxProductCard extends StatefulWidget {
  final ProductModel product;
  final bool masonry;

  const SxProductCard({
    super.key,
    required this.product,
    this.masonry = false,
  });

  @override
  State<SxProductCard> createState() => _SxProductCardState();
}

class _SxProductCardState extends State<SxProductCard> {
  int page = 0;
  double _dragDistance = 0;
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

    final nextPage = (page + direction).clamp(0, imageCount - 1);
    if (nextPage != page && mounted) {
      setState(() => page = nextPage);
    }
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
              duration: const Duration(milliseconds: 170),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
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

    final body = Stack(
      fit: StackFit.passthrough,
      children: [
        if (masonry)
          AspectRatio(aspectRatio: ratio, child: imageContainer)
        else
          Positioned.fill(child: imageContainer),
        const Positioned(
          top: 6,
          right: 6,
          child: SxPill(
            text: 'علامة تجارية',
            background: Colors.black87,
            foreground: Colors.white,
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
    final tab = sxText(badge['storefront_tab']);
    final fallback = tab == 'new'
        ? const Color(0xFF16A34A)
        : tab == 'offers'
            ? const Color(0xFFDC2626)
            : const Color(0xFF111827);
    final bg = sxColor(badge['bg_color'], fallback);
    final fg = sxColor(badge['text_color'], Colors.white);
    final text = sxText(
      badge['custom_text'],
      sxText(badge['name'], sxText(badge['code'])),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w900,
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
    final visibleBadges = product.badges.take(2).toList();

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
          const SizedBox(height: 5),
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
          if (visibleBadges.isNotEmpty) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: visibleBadges.map(_badgeChip).toList(),
            ),
          ],
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
          const Row(
            children: [
              Icon(Icons.star, size: 12.5, color: Color(0xFFFFB400)),
              Text(
                ' 4.8',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
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
    final rows = groups
        .where((row) => row['is_active'] != false)
        .where((row) {
          final root = row['root_category_id'];
          if (selectedRoot < 0) return true;
          return root == null || sxInt(root) == selectedRoot;
        })
        .where((row) => sxMaps(row['circles']).isNotEmpty)
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

  Map<String, dynamic>? get _selectedSide {
    for (final row in _visibleSideCategories) {
      if (sxInt(row['id']) == selectedSideCategoryId) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> get _visibleCircles {
    final selectedRow = _selectedSide;
    if (selectedRow != null) return sxMaps(selectedRow['circles']);

    final result = <Map<String, dynamic>>[];
    for (final row in _visibleSideCategories) {
      result.addAll(sxMaps(row['circles']));
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
                      if (circles.isNotEmpty)
                        _SideCircleGrid(
                          circles: circles,
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
                      if (groups.isNotEmpty) ...[
                        SizedBox(height: sectionSpacing),
                        for (final group in groups) ...[
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
  final int? categoryId, circleId, hashtagId;

  const SxResults({
    super.key,
    required this.title,
    this.query,
    this.categoryId,
    this.circleId,
    this.hashtagId,
  });

  @override State<SxResults> createState() => _SxResultsState();
}

class _SxResultsState extends State<SxResults> {
  static const int _viewGrid = 0;
  static const int _viewMasonry = 1;
  static const int _viewList = 2;

  List<ProductModel> products = [];
  List<CategoryModel> categories = [];
  List<CategoryModel> roots = [];
  List<CategoryModel> allCategories = [];
  List<Map<String, dynamic>> filters = [];
  Map<String, dynamic> home = {};

  final Set<int> values = {};
  String sort = 'recommended';
  String? minPrice, maxPrice;
  int? selectedCategoryId;
  int? categoryContextId;
  bool loading = true;
  bool changingCategory = false;
  int viewMode = _viewGrid;

  @override
  void initState() {
    super.initState();
    load();
  }

  int? _circleRootId(Map<String, dynamic> payload) {
    final id = widget.circleId;
    if (id == null) return null;
    for (final side in sxMaps(payload['side_categories'])) {
      for (final circle in sxMaps(side['circles'])) {
        if (sxInt(circle['id']) == id) return sxInt(side['root_category_id']);
      }
    }
    return null;
  }

  void _buildCategoryRail() {
    allCategories = sxMaps(home['categories'])
        .map(CategoryModel.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder == b.sortOrder
          ? a.id.compareTo(b.id)
          : a.sortOrder.compareTo(b.sortOrder));
    roots = allCategories.where((x) => x.parentId == null).toList();

    final scope = widget.categoryId ?? categoryContextId;
    if (scope != null) {
      categories = allCategories.where((x) => x.parentId == scope).toList()
        ..sort((a, b) => a.sortOrder == b.sortOrder
            ? a.id.compareTo(b.id)
            : a.sortOrder.compareTo(b.sortOrder));
    } else {
      categories = roots;
    }
  }

  Future<void> _loadFilters(int? categoryId) async {
    filters = [];
    if (categoryId == null) return;
    try {
      filters = await api.categoryFilters(categoryId);
    } catch (_) {}
  }

  Future<List<ProductModel>> _fetch() => api.feed(
    category: selectedCategoryId ?? widget.categoryId,
    circleId: widget.circleId,
    hashtagId: widget.hashtagId,
    q: widget.query ?? '',
    filterValueIds: values.toList(),
    sort: sort,
    minPrice: minPrice,
    maxPrice: maxPrice,
    currencyId: state.currencyId,
  );

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      home = await api.home();
      categoryContextId = _circleRootId(home);
      selectedCategoryId = null;

      await _loadFilters(widget.categoryId ?? categoryContextId);
      products = await _fetch();
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
    if (changingCategory) return;
    setState(() {
      selectedCategoryId = id;
      changingCategory = true;
      values.clear();
      minPrice = null;
      maxPrice = null;
    });
    await _loadFilters(id ?? widget.categoryId ?? categoryContextId);
    try {
      final next = await _fetch();
      if (mounted) setState(() => products = next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sxText(e, 'تعذر تحديث النتائج'))),
        );
      }
    }
    if (mounted) setState(() => changingCategory = false);
  }

  Future<void> _reloadResults() async {
    if (mounted) setState(() => loading = true);
    try {
      products = await _fetch();
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
    final filterCategory = selectedCategoryId ?? widget.categoryId ?? categoryContextId;
    if (filterCategory == null || filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فلاتر مخصصة لهذه الفئة حاليًا')),
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
      ),
    );
    if (result == null) return;

    values
      ..clear()
      ..addAll(result.valueIds);
    minPrice = result.minPrice;
    maxPrice = result.maxPrice;
    await _reloadResults();
  }

  Future<void> sortSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) => SxSortSheet(current: sort),
    );
    if (result == null) return;
    setState(() => sort = result);
    await _reloadResults();
  }

  String get _sortLabel {
    switch (sort) {
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
        (maxPrice != null ? 1 : 0);

    if (loading && products.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _ResultsTopBar(
              title: _scopeLabel,
              viewMode: viewMode,
              onViewMode: () => setState(() => viewMode = (viewMode + 1) % 3),
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
              height: 58,
              child: _ResultsTopBar(
                title: _scopeLabel,
                viewMode: viewMode,
                onViewMode: () => setState(() => viewMode = (viewMode + 1) % 3),
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
          if (categories.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ResultHeaderDelegate(
                height: 94,
                child: _ResultsCategoryRail(
                  categories: categories,
                  selected: selectedCategoryId,
                  onSelected: _selectCategory,
                ),
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ResultHeaderDelegate(
              height: 56,
              child: _ResultsFilterBar(
                sortLabel: _sortLabel,
                filterCount: filterCount,
                onSort: sortSheet,
                onFilter: filterSheet,
              ),
            ),
          ),
          if (changingCategory || (loading && products.isNotEmpty))
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(
                minHeight: 1.5,
                backgroundColor: Colors.transparent,
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
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: viewMode == _viewList
                ? _ResultsList(products: products)
                : SxProductGrid(
                    products: products,
                    masonry: viewMode == _viewMasonry,
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
            SxCircleIcon(icon: Icons.favorite_border, onTap: onWishlist),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'تغيير طريقة العرض',
              onPressed: onViewMode,
              icon: Icon(
                viewMode == _SxResultsState._viewList
                    ? Icons.view_list_outlined
                    : viewMode == _SxResultsState._viewMasonry
                        ? Icons.view_comfy_alt_outlined
                        : Icons.grid_view_outlined,
                size: 21,
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
                    border: Border.all(color: const Color(0xFFCFCFCF), width: .8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Container(
                        width: 39,
                        height: double.infinity,
                        color: Colors.black,
                        child: const Icon(Icons.search, color: Colors.white, size: 20),
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
                              style: const TextStyle(fontSize: 11.5, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 7),
                        child: Icon(Icons.camera_alt_outlined, size: 17),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'رجوع',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 2),
      SizedBox(
        height: 84,
        child: ListView.separated(
          reverse: true,
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
                width: selected ? 1.6 : .6,
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
  final String sortLabel;
  final int filterCount;
  final VoidCallback onSort;
  final VoidCallback onFilter;

  const _ResultsFilterBar({
    required this.sortLabel,
    required this.filterCount,
    required this.onSort,
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
        Expanded(child: _FilterButton(sortLabel, Icons.keyboard_arrow_down, onSort)),
        const SizedBox(width: 5),
        Expanded(child: _FilterButton('الأحدث', Icons.auto_awesome_outlined, onSort)),
        const SizedBox(width: 5),
        Expanded(child: _FilterButton('السعر', Icons.swap_vert, onSort)),
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

class SxFilterSelection {
  final Set<int> valueIds; final String? minPrice, maxPrice;
  const SxFilterSelection({required this.valueIds, this.minPrice, this.maxPrice});
}

class SxFilterSheet extends StatefulWidget {
  final List<Map<String, dynamic>> filters; final Set<int> selected; final String? minPrice, maxPrice;
  const SxFilterSheet({super.key, required this.filters, required this.selected, this.minPrice, this.maxPrice});
  @override State<SxFilterSheet> createState() => _SxFilterSheetState();
}

class _SxFilterSheetState extends State<SxFilterSheet> {
  late Set<int> values; late TextEditingController min, max;
  @override void initState() { super.initState(); values = {...widget.selected}; min = TextEditingController(text: widget.minPrice ?? ''); max = TextEditingController(text: widget.maxPrice ?? ''); }
  @override void dispose() { min.dispose(); max.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => SafeArea(child: DraggableScrollableSheet(
    expand: false, initialChildSize: .84, maxChildSize: .96, minChildSize: .55,
    builder: (_, scroll) => Column(children: [
      const _Handle(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 3, 16, 8), child: Row(children: [
        const Expanded(child: Text('تصفية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        TextButton(onPressed: () => setState(() { values.clear(); min.clear(); max.clear(); }), child: const Text('مسح')),
      ])),
      Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        for (final f in widget.filters) _FilterGroup(filter: f, values: values, changed: () => setState(() {})),
        const Text('نطاق السعر', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: TextField(controller: min, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'من'))),
          const SizedBox(width: 7),
          Expanded(child: TextField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'إلى'))),
        ]),
        const SizedBox(height: 15),
        SizedBox(height: 49, child: FilledButton(
          onPressed: () => Navigator.pop(context, SxFilterSelection(valueIds: values, minPrice: min.text.trim().isEmpty ? null : min.text.trim(), maxPrice: max.text.trim().isEmpty ? null : max.text.trim())),
          style: FilledButton.styleFrom(backgroundColor: Colors.black),
          child: const Text('عرض النتائج', style: TextStyle(fontWeight: FontWeight.w900)),
        )),
      ])),
    ]),
  ));
}

class _FilterGroup extends StatelessWidget {
  final Map<String, dynamic> filter; final Set<int> values; final VoidCallback changed;
  const _FilterGroup({required this.filter, required this.values, required this.changed});
  @override Widget build(BuildContext context) {
    final rows = sxMaps(filter['values']);
    return Padding(padding: const EdgeInsets.only(bottom: 17), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(sxText(filter['name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: rows.map((r) {
        final id = sxInt(r['id']); final on = values.contains(id);
        return FilterChip(selected: on, label: Text(sxText(r['label']), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)), onSelected: (v) { if (v) values.add(id); else values.remove(id); changed(); });
      }).toList()),
    ]));
  }
}

class SxSortSheet extends StatelessWidget {
  final String current;
  const SxSortSheet({super.key, required this.current});
  @override Widget build(BuildContext context) {
    const options = [('recommended', 'التوصية'), ('newest', 'الأحدث'), ('price_asc', 'السعر: الأقل'), ('price_desc', 'السعر: الأعلى')];
    return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const _Handle(),
      const Padding(padding: EdgeInsets.fromLTRB(16, 5, 16, 8), child: Align(alignment: Alignment.centerRight, child: Text('ترتيب حسب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
      for (final x in options) ListTile(title: Text(x.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), trailing: current == x.$1 ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, x.$1)),
      const SizedBox(height: 5),
    ]));
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

class SxTrendsScreen extends StatefulWidget {
  const SxTrendsScreen({super.key});
  @override State<SxTrendsScreen> createState() => _SxTrendsScreenState();
}

class _SxTrendsScreenState extends State<SxTrendsScreen> {
  List<Map<String, dynamic>> trends = []; List<ProductModel> products = []; int selected = 0; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final h = await api.home();
      trends = sxMaps(h['trends']);
      if (trends.isNotEmpty) products = sxMaps(trends.first['products']).map((x) => x['product']).whereType<Map>().map((x) => ProductModel.fromJson(Map<String, dynamic>.from(x))).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    final t = trends.isEmpty ? <String, dynamic>{} : trends[selected.clamp(0, trends.length - 1)];
    return Scaffold(
      body: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Container(
          padding: const EdgeInsets.only(top: 10, bottom: 16),
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF383838), Color(0xFF171717)])),
          child: Column(children: [
            SafeArea(bottom: false, child: Row(children: [
              const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ترندات', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)))),
              SxCircleIcon(icon: Icons.search, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxSearchScreen()))),
              const SizedBox(width: 7),
            ])),
            if (trends.isNotEmpty) SizedBox(height: 243, child: ListView.separated(
              reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(11), itemCount: trends.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (_, i) => InkWell(onTap: () {
                setState(() { selected = i; products = sxMaps(trends[i]['products']).map((x) => x['product']).whereType<Map>().map((x) => ProductModel.fromJson(Map<String, dynamic>.from(x))).toList(); });
              }, child: _BigTrend(t: trends[i], active: selected == i)),
            )),
          ]),
        )),
        SliverToBoxAdapter(child: Container(
          padding: const EdgeInsets.fromLTRB(10, 17, 10, 12), color: Colors.white,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('مختارات رائعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 10),
            SingleChildScrollView(reverse: true, scrollDirection: Axis.horizontal, child: Row(children: [
              const SxPill(text: 'لك', background: ClientTheme.accent, foreground: Colors.white), const SizedBox(width: 5),
              SxPill(text: sxText((t['hashtag'] as Map?)?['display_name'])), const SizedBox(width: 5),
              const SxPill(text: '#عودة_التراث'), const SizedBox(width: 5), const SxPill(text: '#أناقة_يومية'),
            ])),
          ]),
        )),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(7, 8, 7, 18), child: SxProductGrid(products: products))),
      ]),
    );
  }
}

class _BigTrend extends StatelessWidget {
  final Map<String, dynamic> t; final bool active;
  const _BigTrend({required this.t, required this.active});
  @override Widget build(BuildContext context) {
    final rows = sxMaps(t['products']); final sec = sxInt((t['timer'] as Map?)?['seconds']);
    return Container(
      width: 334,
      decoration: BoxDecoration(color: const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(17), border: active ? Border.all(color: Colors.white70) : null),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(child: SxImage(url: (t['background'] as Map?)?['url'])),
        Positioned.fill(child: Container(color: Colors.black.withOpacity(.42))),
        Positioned(top: 10, right: 10, child: SxPill(text: sec <= 0 ? 'مستمر' : 'خلال ' + ((sec / 86400).ceil()).toString() + ' يوم', background: ClientTheme.accent, foreground: Colors.white)),
        Positioned(top: 10, left: 10, child: SxPill(text: sxText((t['hashtag'] as Map?)?['display_name']), background: Colors.black54, foreground: Colors.white)),
        Positioned(left: 9, right: 9, bottom: 9, child: Row(children: [
          for (final row in rows.take(3)) Expanded(child: Padding(padding: const EdgeInsets.only(left: 5), child: Container(height: 111, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)), clipBehavior: Clip.antiAlias, child: SxImage(url: (row['product'] as Map?)?['image_url'])))),
        ])),
      ]),
    );
  }
}

class SxTrendDetailScreen extends StatelessWidget {
  final Map<String, dynamic> trend;
  const SxTrendDetailScreen({super.key, required this.trend});
  @override Widget build(BuildContext context) {
    final products = sxMaps(trend['products']).map((x) => x['product']).whereType<Map>().map((x) => ProductModel.fromJson(Map<String, dynamic>.from(x))).toList();
    return SxShellPage(title: sxText((trend['hashtag'] as Map?)?['display_name'], 'الترند'), back: true, child: ListView(children: [
      SizedBox(height: 285, child: SxImage(url: (trend['background'] as Map?)?['url'])),
      Padding(padding: const EdgeInsets.all(15), child: Text(sxText(trend['promo_text']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
      const SxSectionTitle(title: 'منتجات الترند'), Padding(padding: const EdgeInsets.fromLTRB(7, 0, 7, 20), child: SxProductGrid(products: products)),
    ]));
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
  const SxAddressForm({super.key});
  @override State<SxAddressForm> createState() => _SxAddressFormState();
}

class _SxAddressFormState extends State<SxAddressForm> {
  final name = TextEditingController(), phone = TextEditingController(), district = TextEditingController(), street = TextEditingController(), landmark = TextEditingController();
  List<Map<String, dynamic>> cities = [], areas = []; int? cityId, areaId;
  @override void initState() { super.initState(); api.cities().then((v) { if (mounted) setState(() => cities = v); }); }
  @override void dispose() { name.dispose(); phone.dispose(); district.dispose(); street.dispose(); landmark.dispose(); super.dispose(); }
  Future<void> areasFor(int id) async { try { final v = await api.cityAreas(cityId: id); if (mounted) setState(() { areas = v; areaId = null; }); } catch (_) {} }
  @override Widget build(BuildContext context) => SafeArea(child: DraggableScrollableSheet(
    expand: false, initialChildSize: .9, minChildSize: .65, maxChildSize: .96,
    builder: (_, scroll) => Column(children: [
      const _Handle(),
      const Padding(padding: EdgeInsets.fromLTRB(15, 1, 15, 9), child: Align(alignment: Alignment.centerRight, child: Text('إضافة عنوان', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)))),
      Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(15, 0, 15, 15), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المستلم')),
        const SizedBox(height: 7),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
        const SizedBox(height: 7),
        DropdownButtonFormField<int>(value: cityId, decoration: const InputDecoration(labelText: 'المدينة'), items: cities.map((x) => DropdownMenuItem(value: sxInt(x['id']), child: Text(sxText(x['name']), style: const TextStyle(fontSize: 11)))).toList(), onChanged: (v) { if (v == null) return; setState(() => cityId = v); areasFor(v); }),
        if (areas.isNotEmpty) ...[
          const SizedBox(height: 7),
          DropdownButtonFormField<int>(value: areaId, decoration: const InputDecoration(labelText: 'المنطقة'), items: areas.map((x) => DropdownMenuItem(value: sxInt(x['id']), child: Text(sxText(x['name']), style: const TextStyle(fontSize: 11)))).toList(), onChanged: (v) => setState(() => areaId = v)),
        ],
        const SizedBox(height: 7),
        TextField(controller: district, decoration: const InputDecoration(labelText: 'الحي')),
        const SizedBox(height: 7),
        TextField(controller: street, decoration: const InputDecoration(labelText: 'الشارع')),
        const SizedBox(height: 7),
        TextField(controller: landmark, decoration: const InputDecoration(labelText: 'معلم قريب')),
        const SizedBox(height: 13),
        SizedBox(height: 49, child: FilledButton(
          onPressed: cityId == null || name.text.trim().isEmpty || phone.text.trim().isEmpty ? null : () => Navigator.pop(context, {
            'recipient_name': name.text.trim(), 'phone': phone.text.trim(), 'city_id': cityId, 'city_area_id': areaId,
            'district': district.text.trim(), 'street': street.text.trim(), 'landmark': landmark.text.trim(), 'is_default': true,
          }),
          style: FilledButton.styleFrom(backgroundColor: Colors.black),
          child: const Text('حفظ العنوان', style: TextStyle(fontWeight: FontWeight.w900)),
        )),
      ])),
    ]),
  ));
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
    try { me = Map<String, dynamic>.from((await api.me())['item'] ?? {}); orders = await api.orders(); state.wishlist = (await api.wishlistIds()).toSet(); } catch (_) {}
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
        onTap: () async { await state.setCurrency(id: id, code: sxText(x['code'], 'SAR'), symbol: sxText(x['symbol'], sxText(x['code'], 'SAR'))); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير العملة'))); Navigator.pop(context); } },
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
        try { final id = sxInt(filtered[i]['id']); await api.updateMe({'city_id': id, 'city_area_id': null}); await state.setCity(id: id, name: sxText(filtered[i]['name'])); if (mounted) Navigator.pop(context); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
      },
    ))),
  ]));
}

class SxAddressesScreen extends StatefulWidget {
  const SxAddressesScreen({super.key});
  @override State<SxAddressesScreen> createState() => _SxAddressesScreenState();
}
class _SxAddressesScreenState extends State<SxAddressesScreen> {
  List<Map<String, dynamic>> rows = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { try { rows = await api.addresses(); } catch (_) {} if (mounted) setState(() => loading = false); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'العناوين', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView(
    padding: const EdgeInsets.all(10),
    children: [
      for (final x in rows) Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: x['is_default'] == true ? Colors.black : ClientTheme.border), borderRadius: BorderRadius.circular(7)), child: Row(children: [
        const Icon(Icons.location_on_outlined), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(sxText(x['recipient_name']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))), if (x['is_default'] == true) const SxPill(text: 'افتراضي', background: Colors.black, foreground: Colors.white)]),
          const SizedBox(height: 4), Text(sxText(x['phone']), style: const TextStyle(fontSize: 9)), const SizedBox(height: 3),
          Text(sxText(x['district']) + ' ' + sxText(x['street']) + ' ' + sxText(x['landmark']), style: const TextStyle(fontSize: 9, color: ClientTheme.muted)),
        ])),
      ])),
      SizedBox(height: 48, child: OutlinedButton.icon(
        onPressed: () async { final b = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, backgroundColor: Colors.white, builder: (_) => const SxAddressForm()); if (b != null) { await api.addAddress(b); await load(); } },
        icon: const Icon(Icons.add), label: const Text('إضافة عنوان جديد', style: TextStyle(fontWeight: FontWeight.w900)),
        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.black), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
      )),
    ],
  ));
}

class SxOrdersScreen extends StatefulWidget {
  const SxOrdersScreen({super.key});
  @override State<SxOrdersScreen> createState() => _SxOrdersScreenState();
}
class _SxOrdersScreenState extends State<SxOrdersScreen> {
  List<Map<String, dynamic>> rows = []; bool loading = true;
  @override void initState() { super.initState(); api.orders().then((v) { if (mounted) setState(() { rows = v; loading = false; }); }).catchError((_) { if (mounted) setState(() => loading = false); }); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'طلباتي', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView.separated(
    padding: const EdgeInsets.all(10), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 7),
    itemBuilder: (_, i) => InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxOrderDetailScreen(id: sxInt(rows[i]['id'])))),
      child: Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(border: Border.all(color: ClientTheme.border), borderRadius: BorderRadius.circular(6)), child: Row(children: [
        const Icon(Icons.receipt_long_outlined), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(sxText(rows[i]['order_no'], '#'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(sxText(rows[i]['status']), style: const TextStyle(fontSize: 9, color: ClientTheme.muted)),
        ])), const Icon(Icons.chevron_left),
      ])),
    ),
  ));
}
class SxOrderDetailScreen extends StatefulWidget {
  final int id; const SxOrderDetailScreen({super.key, required this.id});
  @override State<SxOrderDetailScreen> createState() => _SxOrderDetailScreenState();
}
class _SxOrderDetailScreenState extends State<SxOrderDetailScreen> {
  Map<String, dynamic> order = {}; bool loading = true;
  @override void initState() { super.initState(); api.order(widget.id).then((v) { if (mounted) setState(() { order = Map<String, dynamic>.from(v['item'] is Map ? v['item'] : v); loading = false; }); }).catchError((_) { if (mounted) setState(() => loading = false); }); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'تفاصيل الطلب', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView(
    padding: const EdgeInsets.all(10),
    children: [
      Container(color: ClientTheme.soft, padding: const EdgeInsets.all(11), child: Text('رقم الطلب: ' + sxText(order['order_no']) + '\\nالحالة: ' + sxText(order['status']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 1.7))),
      const SxSectionTitle(title: 'المنتجات'),
      for (final x in sxMaps(order['items'])) ListTile(
        contentPadding: EdgeInsets.zero, leading: SizedBox(width: 59, height: 63, child: SxImage(url: x['image_url'])),
        title: Text(sxText(x['product_name']), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
        subtitle: Text('الكمية: ' + sxText(x['qty']), style: const TextStyle(fontSize: 9)),
        trailing: Text(sxText(x['unit_price'], '0') + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
      ),
    ],
  ));
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
  List<Map<String, dynamic>> rows = []; bool loading = true;
  @override void initState() { super.initState(); api.conversations().then((v) { if (mounted) setState(() { rows = v; loading = false; }); }).catchError((_) { if (mounted) setState(() => loading = false); }); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'خدمة العملاء', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : rows.isEmpty ? Center(child: FilledButton(onPressed: () async { try { await api.newConversation(); final v = await api.conversations(); if (mounted) setState(() => rows = v); } catch (_) {} }, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: const Text('بدء محادثة'))) : ListView.separated(
    itemCount: rows.length, separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (_, i) => ListTile(leading: const CircleAvatar(backgroundColor: Colors.black, child: Icon(Icons.support_agent, color: Colors.white)), title: Text(sxText(rows[i]['subject'], 'خدمة العملاء'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)), subtitle: Text(sxText(rows[i]['status'], 'مفتوحة'), style: const TextStyle(fontSize: 9))),
  ));
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
    try { await api.verifyOtp(widget.requestId, code.text.trim(), phone: widget.phone); if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SxAppShell()), (_) => false); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e)))); }
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
