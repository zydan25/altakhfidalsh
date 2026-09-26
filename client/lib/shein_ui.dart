import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

String sxText(dynamic v, [String fallback = '']) => (v ?? fallback).toString();
int sxInt(dynamic v, [int fallback = 0]) => int.tryParse(sxText(v)) ?? fallback;
double sxDouble(dynamic v, [double fallback = 0]) => double.tryParse(sxText(v)) ?? fallback;

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
  late final List<Widget> pages;
  @override void initState() {
    super.initState();
    pages = const [SxHomeScreen(), SxCategoriesScreen(), SxTrendsScreen(), SxCartScreen(), SxAccountScreen()];
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      navigationBarColor: Colors.white,
      navigationBarIconBrightness: Brightness.dark,
    ));
  }
  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SxBottomBar(index: index, onChanged: (v) => setState(() => index = v)),
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
  final String hint;
  final bool autofocus;
  const SxSearchBar({super.key, this.onTap, this.controller, this.onChanged, this.hint = 'ابحث عن المنتجات', this.autofocus = false});
  @override Widget build(BuildContext context) => SizedBox(
    height: 43,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      readOnly: onTap != null && controller == null,
      onTap: onTap,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 22),
        suffixIcon: const Icon(Icons.camera_alt_outlined, size: 19),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: Color(0xFFD5D5D5), width: .8)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: Color(0xFFD5D5D5), width: .8)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: Colors.black)),
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
    return Image.network(value, width: width, height: height, fit: fit, gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(width: width, height: height, color: ClientTheme.soft, child: const Icon(Icons.image_outlined, color: Color(0xFF9AA0A6))));
  }
}

class SxCircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dot;
  const SxCircleIcon({super.key, required this.icon, this.onTap, this.dot = false});
  @override Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.91), shape: BoxShape.circle),
      child: Stack(children: [
        Center(child: Icon(icon, size: 20)),
        if (dot) Positioned(right: 5, top: 6, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: ClientTheme.promo, shape: BoxShape.circle))),
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
  List<CategoryModel> roots = [];
  int selected = -1;
  bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final h = await api.home();
      home = h;
      roots = sxMaps(h['categories']).map(CategoryModel.fromJson).where((x) => x.parentId == null).toList();
      products = await api.feed(category: selected < 0 ? null : selected, currencyId: state.currencyId);
      try {
        final c = await api.cart(currencyId: state.currencyId);
        _CartBadge.value.value = sxMaps(c['item']?['items']).length;
      } catch (_) {}
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e))));
    }
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    final banners = sxMaps(home['banners']);
    final looks = sxMaps(home['looks']);
    final side = sxMaps(home['side_categories']);
    final trends = sxMaps(home['trends']);
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: load,
        color: Colors.black,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _HomeHero(
              banners: banners, roots: roots, selected: selected,
              onSelected: (id) async { setState(() => selected = id); await load(); },
              onSearch: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxSearchScreen())),
              onWishlist: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxWishlistScreen())),
              onNotifications: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxNotificationsScreen())),
            )),
            if (!loading) const SliverToBoxAdapter(child: SxDeals()),
            if (!loading && looks.isNotEmpty) SliverToBoxAdapter(child: SxFeatureTiles(rows: looks.take(4).toList())),
            if (!loading && side.isNotEmpty) SliverToBoxAdapter(child: SxCircleRail(
              title: 'مختارات من أجلك',
              rows: side.expand((e) => sxMaps(e['circles'])).take(14).toList(),
              onTap: (c) => Navigator.push(context, MaterialPageRoute(builder: (_) => SxResults(title: sxText(c['name']), circleId: sxInt(c['id'])))),
            )),
            if (!loading && trends.isNotEmpty) SliverToBoxAdapter(child: SxTrendRail(trends: trends)),
            const SliverToBoxAdapter(child: SxSectionTitle(title: 'من أجلك')),
            if (loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(7, 0, 7, 18), child: SxProductGrid(products: products))),
          ],
        ),
      ),
    );
  }
}

class _HomeHero extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  final List<CategoryModel> roots;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch, onWishlist, onNotifications;
  const _HomeHero({required this.banners, required this.roots, required this.selected, required this.onSelected, required this.onSearch, required this.onWishlist, required this.onNotifications});
  @override State<_HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<_HomeHero> {
  int page = 0;
  @override Widget build(BuildContext context) {
    final tabs = [const CategoryModel(id: -1, name: 'كل'), ...widget.roots];
    return SizedBox(
      height: 378,
      child: Stack(children: [
        PageView.builder(
          itemCount: widget.banners.length,
          onPageChanged: (v) => setState(() => page = v),
          itemBuilder: (_, i) => InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxBannerLandingScreen(banner: widget.banners[i]))),
            child: SxImage(url: widget.banners[i]['mobile_image_url'] ?? widget.banners[i]['image_url'], width: double.infinity, height: 378),
          ),
        ),
        if (widget.banners.isEmpty) const Positioned.fill(child: ColoredBox(color: ClientTheme.soft)),
        Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Colors.black.withOpacity(.28), Colors.transparent]))))),
        Positioned(top: 10, left: 8, right: 8, child: SafeArea(bottom: false, child: Row(children: [
          SxCircleIcon(icon: Icons.favorite_border, onTap: widget.onWishlist),
          const SizedBox(width: 5),
          Expanded(child: GestureDetector(onTap: widget.onSearch, child: const SxSearchBar())),
          const SizedBox(width: 5),
          SxCircleIcon(icon: Icons.notifications_none, onTap: widget.onNotifications, dot: true),
          SxCircleIcon(icon: Icons.mail_outline, onTap: widget.onNotifications),
        ]))),
        Positioned(left: 0, right: 0, bottom: 37, child: SizedBox(
          height: 45,
          child: ListView(
            reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8),
            children: tabs.map((t) {
              final active = widget.selected == t.id;
              return InkWell(
                onTap: () => widget.onSelected(t.id),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(t.name, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
                  const SizedBox(height: 6),
                  AnimatedContainer(duration: const Duration(milliseconds: 160), width: active ? 31 : 0, height: 2, color: Colors.white),
                ])),
              );
            }).toList(),
          ),
        )),
        Positioned(left: 0, right: 0, bottom: 10, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(
          widget.banners.length,
          (i) => AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.symmetric(horizontal: 2), width: i == page ? 18 : 4, height: 3, decoration: BoxDecoration(color: i == page ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(5))),
        ))),
      ]),
    );
  }
}

class SxBannerLandingScreen extends StatefulWidget {
  final Map<String, dynamic> banner;
  const SxBannerLandingScreen({super.key, required this.banner});
  @override State<SxBannerLandingScreen> createState() => _SxBannerLandingScreenState();
}

class _SxBannerLandingScreenState extends State<SxBannerLandingScreen> {
  List<ProductModel> products = [];
  bool loading = true;
  String title = '';

  @override void initState() {
    super.initState();
    title = sxText(widget.banner['title'], 'العرض');
    load();
  }

  Future<void> load() async {
    try {
      final targets = sxMaps(widget.banner['targets']);
      final target = targets.isEmpty ? <String, dynamic>{} : targets.first;
      final type = sxText(target['type']);
      final id = sxInt(target['id']);
      if (type == 'product' && id > 0) {
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SxProductScreen(id: id)));
        }
        return;
      }
      if (type == 'category' && id > 0) {
        products = await api.feed(category: id, currencyId: state.currencyId);
      } else if ((type == 'circle' || type == 'side_category_circle') && id > 0) {
        products = await api.feed(circleId: id, currencyId: state.currencyId);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sxText(e))));
    }
    if (mounted) setState(() => loading = false);
  }

  @override Widget build(BuildContext context) => SxShellPage(
    title: title,
    back: true,
    child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView(
      children: [
        SizedBox(height: 285, child: SxImage(url: widget.banner['mobile_image_url'] ?? widget.banner['image_url'])),
        if (sxText(widget.banner['description']).isNotEmpty)
          Padding(padding: const EdgeInsets.all(14), child: Text(sxText(widget.banner['description']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.5))),
        const SxSectionTitle(title: 'منتجات العرض'),
        Padding(padding: const EdgeInsets.fromLTRB(7, 0, 7, 20), child: SxProductGrid(products: products)),
      ],
    ),
  );
}

class SxDeals extends StatelessWidget {
  const SxDeals({super.key});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: const Color(0xFFFFF8F4), border: Border.all(color: const Color(0xFFF0D8CC)), borderRadius: BorderRadius.circular(21)),
    child: const Row(children: [
      Expanded(child: _Deal(title: 'خصم 30%', sub: 'أكثر من 149 ر.س')),
      SizedBox(width: 6),
      Expanded(child: _Deal(title: 'خصم 25%', sub: 'أكثر من 379 ر.س')),
      SizedBox(width: 6),
      Expanded(child: _Deal(title: 'للمستخدم الجديد فقط', sub: 'عروض جيدة', active: true)),
    ]),
  );
}

class _Deal extends StatelessWidget {
  final String title, sub; final bool active;
  const _Deal({required this.title, required this.sub, this.active = false});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
    decoration: BoxDecoration(color: active ? const Color(0xFFFFEEF4) : Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: active ? ClientTheme.promo : const Color(0xFF8A2740))),
      const SizedBox(height: 2),
      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w600)),
    ]),
  );
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

class SxProductGrid extends StatelessWidget {
  final List<ProductModel> products;
  const SxProductGrid({super.key, required this.products});
  @override Widget build(BuildContext context) => products.isEmpty
    ? const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد منتجات مطابقة', style: TextStyle(fontWeight: FontWeight.w700))))
    : GridView.builder(
      primary: false, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 5, mainAxisSpacing: 8, childAspectRatio: .60),
      itemBuilder: (_, i) => SxProductCard(product: products[i]),
    );
}

class SxProductCard extends StatelessWidget {
  final ProductModel product;
  const SxProductCard({super.key, required this.product});
  @override Widget build(BuildContext context) {
    final old = sxDouble(product.oldPrice), now = sxDouble(product.price);
    final discount = old > now && old > 0 ? ((1 - now / old) * 100).round() : 0;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxProductScreen(id: product.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Stack(children: [
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SxImage(url: product.image))),
          const Positioned(top: 6, right: 6, child: SxPill(text: 'علامة تجارية', background: Colors.black87, foreground: Colors.white)),
          if (discount > 0) Positioned(left: 0, right: 0, bottom: 0, child: Container(
            color: Colors.black.withOpacity(.74), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Row(children: [
              const Text('🔥 توفير', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800)),
              const Spacer(), Text(discount.toString() + '%', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
            ]),
          )),
          Positioned(left: 7, bottom: discount > 0 ? 27 : 7, child: Container(
            width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(.93), shape: BoxShape.circle),
            child: const Icon(Icons.shopping_bag_outlined, size: 17),
          )),
        ])),
        const SizedBox(height: 6),
        Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2)),
        const SizedBox(height: 4),
        Row(children: [
          if (discount > 0) ...[Text('-' + discount.toString() + '%', style: const TextStyle(color: ClientTheme.promo, fontSize: 9.5, fontWeight: FontWeight.w900)), const SizedBox(width: 4)],
          Text(product.price + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
        ]),
        if (product.oldPrice != null && product.oldPrice!.isNotEmpty) Text(product.oldPrice! + ' ' + state.currencySymbol, style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted, decoration: TextDecoration.lineThrough)),
        const Row(children: [Icon(Icons.star, size: 12.5, color: Color(0xFFFFB400)), Text(' 4.8', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 4),
      ]),
    );
  }
}

class SxCategoriesScreen extends StatefulWidget {
  const SxCategoriesScreen({super.key});
  @override State<SxCategoriesScreen> createState() => _SxCategoriesScreenState();
}

class _SxCategoriesScreenState extends State<SxCategoriesScreen> {
  List<CategoryModel> roots = [], all = [];
  List<Map<String, dynamic>> side = [];
  List<ProductModel> products = [];
  int? selected;
  bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() => loading = true);
    try {
      final h = await api.home();
      roots = sxMaps(h['categories']).map(CategoryModel.fromJson).where((x) => x.parentId == null).toList();
      all = await api.allCategories(); side = sxMaps(h['side_categories']);
      selected ??= roots.isNotEmpty ? roots.first.id : null;
      products = await api.feed(category: selected, currencyId: state.currencyId);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override Widget build(BuildContext context) {
    final children = selected == null ? <CategoryModel>[] : all.where((x) => x.parentId == selected).toList();
    final circles = side.where((x) => sxInt(x['root_category_id']) == selected).expand((x) => sxMaps(x['circles'])).toList();
    return Scaffold(
      appBar: SxAppBar(title: 'الفئات', onSearch: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxSearchScreen()))),
      body: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : RefreshIndicator(
        onRefresh: load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: SxRootTabs(categories: roots, selected: selected, onChanged: (v) async { setState(() => selected = v); await load(); })),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(height: 350, child: Row(children: [
              Expanded(child: circles.isEmpty ? _FallbackCats(rows: children) : GridView.builder(
                padding: const EdgeInsets.all(4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 8, childAspectRatio: .88),
                itemCount: circles.length, itemBuilder: (_, i) => _CircleCategory(row: circles[i]),
              )),
              const SizedBox(width: 120, child: _NewRail()),
            ])),
          )),
          if (children.isNotEmpty) SliverToBoxAdapter(child: SizedBox(height: 43, child: ListView.separated(
            reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: children.length, separatorBuilder: (_, __) => const SizedBox(width: 5),
            itemBuilder: (_, i) => ActionChip(
              label: Text(children[i].name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxResults(title: children[i].name, categoryId: children[i].id))),
            ),
          ))),
          const SliverToBoxAdapter(child: SxSectionTitle(title: 'مختارات من أجلك')),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(7, 0, 7, 20), child: SxProductGrid(products: products))),
        ]),
      ),
    );
  }
}

class SxRootTabs extends StatelessWidget {
  final List<CategoryModel> categories; final int? selected; final ValueChanged<int?> onChanged;
  const SxRootTabs({super.key, required this.categories, required this.selected, required this.onChanged});
  @override Widget build(BuildContext context) => SizedBox(height: 54, child: ListView(
    reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 7),
    children: [
      _tab('كل', selected == null, () => onChanged(null)),
      ...categories.map((c) => _tab(c.name, selected == c.id, () => onChanged(c.id))),
    ],
  ));
  Widget _tab(String t, bool active, VoidCallback tap) => InkWell(
    onTap: tap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text(t, style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
      const SizedBox(height: 8),
      AnimatedContainer(duration: const Duration(milliseconds: 160), width: active ? 33 : 0, height: 2, color: Colors.black),
    ])),
  );
}

class _NewRail extends StatelessWidget {
  const _NewRail();
  @override Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(border: Border(right: BorderSide(color: ClientTheme.border, width: .7))),
    child: ListView(padding: const EdgeInsets.symmetric(vertical: 7), children: const [
      _NewLabel('جديد في', true), _NewLabel('ملابس نسائية'), _NewLabel('المنزل والمعيشة'), _NewLabel('الأطفال'),
      _NewLabel('الملابس الرجالية'), _NewLabel('الصحة والجمال'), _NewLabel('ملابس داخلية وملابس نوم'),
      _NewLabel('مجوهرات وإكسسوارات'), _NewLabel('أحدث'), _NewLabel('مقاسات كبيرة'), _NewLabel('الأطفال والأمومة'),
    ]),
  );
}

class _NewLabel extends StatelessWidget {
  final String text; final bool bold;
  const _NewLabel(this.text, [this.bold = false]);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: Text(text, style: TextStyle(fontSize: bold ? 14 : 11.5, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, height: 1.25)),
  );
}

class _CircleCategory extends StatelessWidget {
  final Map<String, dynamic> row;
  const _CircleCategory({required this.row});
  @override Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxResults(title: sxText(row['name']), circleId: sxInt(row['id'])))),
    child: Column(children: [
      Expanded(child: Container(decoration: const BoxDecoration(color: ClientTheme.soft, shape: BoxShape.circle), clipBehavior: Clip.antiAlias, child: SxImage(url: row['image_url']))),
      const SizedBox(height: 6),
      Text(sxText(row['name']), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _FallbackCats extends StatelessWidget {
  final List<CategoryModel> rows;
  const _FallbackCats({required this.rows});
  @override Widget build(BuildContext context) => GridView.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 8, childAspectRatio: .88),
    itemCount: rows.length,
    itemBuilder: (_, i) => InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SxResults(title: rows[i].name, categoryId: rows[i].id))),
      child: Column(children: [
        Expanded(child: Container(decoration: const BoxDecoration(color: ClientTheme.soft, shape: BoxShape.circle), child: const Icon(Icons.category_outlined))),
        const SizedBox(height: 6), Text(rows[i].name, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class SxResults extends StatefulWidget {
  final String title; final int? categoryId, circleId;
  const SxResults({super.key, required this.title, this.categoryId, this.circleId});
  @override State<SxResults> createState() => _SxResultsState();
}

class _SxResultsState extends State<SxResults> {
  List<ProductModel> products = []; List<Map<String, dynamic>> filters = [];
  final values = <int>{}; String sort = 'recommended'; String? minPrice, maxPrice; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() => loading = true);
    try {
      products = await api.feed(category: widget.categoryId, circleId: widget.circleId, filterValueIds: values.toList(), sort: sort, minPrice: minPrice, maxPrice: maxPrice, currencyId: state.currencyId);
      if (widget.categoryId != null) filters = await api.categoryFilters(widget.categoryId!);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  Future<void> filterSheet() async {
    if (widget.categoryId == null) return;
    final r = await showModalBottomSheet<SxFilterSelection>(context: context, isScrollControlled: true, backgroundColor: Colors.white, builder: (_) => SxFilterSheet(filters: filters, selected: values, minPrice: minPrice, maxPrice: maxPrice));
    if (r == null) return;
    values..clear()..addAll(r.valueIds); minPrice = r.minPrice; maxPrice = r.maxPrice; await load();
  }
  Future<void> sortSheet() async {
    final r = await showModalBottomSheet<String>(context: context, backgroundColor: Colors.white, builder: (_) => SxSortSheet(current: sort));
    if (r == null) return;
    setState(() => sort = r); await load();
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: SxAppBar(title: widget.title, back: true, onSearch: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SxSearchScreen()))),
    body: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : CustomScrollView(slivers: [
      if (values.isNotEmpty || minPrice != null || maxPrice != null) SliverToBoxAdapter(child: SizedBox(height: 40, child: ListView(reverse: true, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 9), children: [
        const SxPill(text: 'فلاتر مفعلة', background: Colors.black, foreground: Colors.white),
        ...values.map((e) => Padding(padding: const EdgeInsets.only(right: 5), child: SxPill(text: _label(e)))),
      ]))),
      SliverPersistentHeader(pinned: true, delegate: _FilterHeader(child: Row(children: [
        Expanded(child: _FilterButton('التوصية', Icons.keyboard_arrow_down, sortSheet)),
        const SizedBox(width: 5), Expanded(child: _FilterButton('أوسع من...', Icons.local_fire_department_outlined, sortSheet)),
        const SizedBox(width: 5), Expanded(child: _FilterButton('السعر', Icons.swap_vert, sortSheet)),
        const SizedBox(width: 5), Expanded(child: _FilterButton('تصنيف', Icons.tune, filterSheet)),
      ]))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(7, 9, 7, 20), child: SxProductGrid(products: products))),
    ]),
  );
  String _label(int id) {
    for (final f in filters) for (final v in sxMaps(f['values'])) if (sxInt(v['id']) == id) return sxText(v['label']);
    return 'فلتر';
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
  final search = TextEditingController(); List<ProductModel> products = []; bool loading = false;
  Future<void> doSearch(String q) async {
    if (q.trim().isEmpty) { setState(() => products = []); return; }
    setState(() => loading = true);
    try { products = await api.feed(q: q, currencyId: state.currencyId); } catch (_) {}
    if (mounted) setState(() => loading = false);
  }
  @override void dispose() { search.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => SxShellPage(title: 'البحث', back: true, child: loading ? const Center(child: CircularProgressIndicator(strokeWidth: 2)) : ListView(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
    children: [
      SxSearchBar(controller: search, hint: 'ابحث عن منتج أو علامة', autofocus: true, onChanged: doSearch),
      const SizedBox(height: 12),
      if (products.isEmpty) const Wrap(spacing: 6, runSpacing: 6, children: [SxPill(text: 'بنطلون جينز'), SxPill(text: 'فساتين'), SxPill(text: 'أحذية'), SxPill(text: 'مقاسات كبيرة')]) else SxProductGrid(products: products),
    ],
  ));
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
  ]));
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
  ]))));
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
