import 'package:flutter/material.dart';

import 'api.dart';
import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

String oeText(dynamic value, [String fallback = '']) => (value ?? fallback).toString();
int oeInt(dynamic value, [int fallback = 0]) =>
    int.tryParse(oeText(value)) ?? fallback;
List<Map<String, dynamic>> oeMaps(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

class SxOrderEditScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const SxOrderEditScreen({super.key, required this.order});

  @override
  State<SxOrderEditScreen> createState() => _SxOrderEditScreenState();
}

class _SxOrderEditScreenState extends State<SxOrderEditScreen> {
  final ApiService api = ApiService();
  List<Map<String, dynamic>> addresses = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> shipping = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
  int? addressId;
  int? shippingId;
  late TextEditingController note;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    api.token = _sharedToken();
    note = TextEditingController(text: oeText(widget.order['customer_note']));
    items = oeMaps(widget.order['items']).map(_prepareItem).toList();

    final address = widget.order['address_snapshot'] is Map
        ? Map<String, dynamic>.from(widget.order['address_snapshot'] as Map)
        : <String, dynamic>{};
    addressId = oeInt(address['id']) > 0 ? oeInt(address['id']) : null;
    shippingId = oeInt(widget.order['shipping_method_id']) > 0
        ? oeInt(widget.order['shipping_method_id'])
        : null;
    load();
  }

  // Reuse the current global ApiService token without introducing state coupling.
  String _sharedToken() => appApiTokenFallback();

  Map<String, dynamic> _prepareItem(Map<String, dynamic> raw) {
    final item = Map<String, dynamic>.from(raw);
    final selected = <String, dynamic>{};

    for (final option in oeMaps(item['options'])) {
      final name = oeText(option['name']).trim();
      final value = oeText(option['value']).trim();
      if (name.isNotEmpty && value.isNotEmpty) selected[name] = value;
    }

    final variant = item['variant_display'] is Map
        ? Map<String, dynamic>.from(item['variant_display'] as Map)
        : <String, dynamic>{};
    final color = variant['color'] is Map
        ? Map<String, dynamic>.from(variant['color'] as Map)
        : null;
    final size = variant['size'] is Map
        ? Map<String, dynamic>.from(variant['size'] as Map)
        : null;

    if (color != null) {
      selected.putIfAbsent('اللون', () => oeText(color['name']));
    }
    if (size != null) {
      selected.putIfAbsent(
        'المقاس',
        () => oeText(size['label'], oeText(size['code'])),
      );
    }

    item['_selected_options'] = selected;
    item['_qty'] = oeInt(item['qty'], 1);
    return item;
  }

  Future<void> load() async {
    try {
      final result = await Future.wait<dynamic>([
        api.addresses(),
        api.shippingMethods(),
      ]);
      addresses = (result[0] as List)
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      shipping = (result[1] as List)
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();

      if (addressId == null && addresses.isNotEmpty) {
        addressId = oeInt(addresses.first['id']);
      }
      if (shippingId == null && shipping.isNotEmpty) {
        shippingId = oeInt(shipping.first['id']);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(oeText(error))),
        );
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> addProduct() async {
    try {
      final products = await api.feed(currencyId: state.currencyId);
      if (!mounted) return;
      final product = await showModalBottomSheet<ProductModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) => _OrderProductPicker(products: products),
      );
      if (product == null || !mounted) return;

      final detailResponse = await api.product(product.id, currencyId: state.currencyId);
      final detail = detailResponse['item'] is Map
          ? Map<String, dynamic>.from(detailResponse['item'])
          : <String, dynamic>{};
      final variants = oeMaps(detail['variants']).where(
        (v) => oeInt(v['id']) > 0 && oeInt(v['available_qty']) > 0,
      ).toList();
      if (variants.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا المنتج لا يملك مخزونًا متاحًا حاليًا.')),
        );
        return;
      }

      final colors = oeMaps(detail['reference_colors']);
      final sizes = oeMaps(detail['reference_sizes']);
      final selectedVariant = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) => _OrderVariantPicker(
          productName: product.name,
          variants: variants,
          colors: colors,
          sizes: sizes,
        ),
      );
      if (selectedVariant == null || !mounted) return;

      final options = <String, dynamic>{};
      final colorId = oeInt(selectedVariant['color_id']);
      final sizeId = oeInt(selectedVariant['size_id']);
      final color = colors.where((x) => oeInt(x['id']) == colorId).toList();
      final size = sizes.where((x) => oeInt(x['id']) == sizeId).toList();
      if (color.isNotEmpty) options['اللون'] = oeText(color.first['name']);
      if (size.isNotEmpty) options['المقاس'] = oeText(size.first['label'], oeText(size.first['code']));

      setState(() {
        items.add(<String, dynamic>{
          'variant_id': oeInt(selectedVariant['id']),
          'name': product.name,
          'image_url': product.image,
          'sale_price_display': product.price,
          '_selected_options': options,
          '_qty': 1,
        });
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(oeText(error))),
        );
      }
    }
  }

  Future<void> save() async {
    final status = oeText(widget.order['status']);
    if (status != 'created') {
      return;
    }

    final payloadItems = items
        .where((row) => oeInt(row['_qty']) > 0)
        .map((row) {
      final selected = row['_selected_options'] is Map
          ? Map<String, dynamic>.from(row['_selected_options'] as Map)
          : <String, dynamic>{};
      return <String, dynamic>{
        'variant_id': oeInt(row['variant_id']),
        'qty': oeInt(row['_qty'], 1),
        if (selected.isNotEmpty) 'selected_options': selected,
      };
    }).toList();

    if (payloadItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إبقاء منتج واحد على الأقل في الطلب.')),
      );
      return;
    }
    if (addressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر عنوان التسليم.')),
      );
      return;
    }

    setState(() => saving = true);
    try {
      await api.updateOrder(
        oeInt(widget.order['id']),
        <String, dynamic>{
          'address_id': addressId,
          if (shippingId != null) 'shipping_method_id': shippingId,
          'items': payloadItems,
          'customer_note': note.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الطلب وإعادة احتساب السعر والشحن.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(oeText(error))),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String addressLine(Map<String, dynamic> row) => <String>[
        oeText(row['city_name']),
        oeText(row['city_area_name']),
        oeText(row['district']),
        oeText(row['street']),
      ].where((x) => x.trim().isNotEmpty).join(' • ');

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final currency = widget.order['currency'] is Map
        ? oeText(
            (widget.order['currency'] as Map)['symbol'],
            state.currencySymbol,
          )
        : state.currencySymbol;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'تعديل الطلب',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 120),
          children: [
            const Text(
              'المنتجات والاختيارات',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: saving ? null : addProduct,
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 19),
                label: const Text(
                  'إضافة منتج إلى الطلب',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 9),
            for (final row in items)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: ClientTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 64,
                          height: 78,
                          child: oeText(
                            oeMaps(row['media']).isNotEmpty
                                ? oeMaps(row['media']).first['url']
                                : row['image_url'],
                          ).isEmpty
                              ? Container(color: ClientTheme.soft)
                              : Image.network(
                                  api.url(
                                    oeMaps(row['media']).isNotEmpty
                                        ? oeMaps(row['media']).first['url']
                                        : row['image_url'],
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: ClientTheme.soft),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                oeText(row['name'], 'منتج'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if ((row['_selected_options'] as Map).isNotEmpty)
                                Text(
                                  (row['_selected_options'] as Map)
                                      .entries
                                      .map((entry) =>
                                          entry.key + ': ' + entry.value.toString())
                                      .join(' • '),
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    color: ClientTheme.muted,
                                    height: 1.35,
                                  ),
                                ),
                              const SizedBox(height: 5),
                              Text(
                                oeText(row['sale_price_display'], '0') + ' ' + currency,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'زيادة الكمية',
                          onPressed: () => setState(
                            () => row['_qty'] = oeInt(row['_qty'], 1) + 1,
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 21),
                        ),
                        Container(
                          width: 34,
                          alignment: Alignment.center,
                          child: Text(
                            oeInt(row['_qty'], 1).toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'نقص الكمية',
                          onPressed: () {
                            setState(() {
                              row['_qty'] = oeInt(row['_qty'], 1) - 1;
                            });
                          },
                          icon: const Icon(Icons.remove_circle_outline, size: 21),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'حذف المنتج من الطلب',
                          onPressed: () => setState(() => row['_qty'] = 0),
                          icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFC62828)),
                        ),
                        if (oeInt(row['_qty'], 1) <= 0)
                          const Text(
                            'سيُحذف من الطلب',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: Color(0xFFC62828),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'عنوان التسليم',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            for (final address in addresses)
              RadioListTile<int>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: oeInt(address['id']),
                groupValue: addressId,
                onChanged: (value) => setState(() => addressId = value),
                title: Text(
                  oeText(address['recipient_name'], 'المستلم'),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  addressLine(address),
                  style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted),
                ),
              ),
            const SizedBox(height: 5),
            const Text(
              'طريقة التوصيل',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            for (final method in shipping)
              RadioListTile<int>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: oeInt(method['id']),
                groupValue: shippingId,
                onChanged: (value) => setState(() => shippingId = value),
                title: Text(
                  oeText(method['name'], 'التوصيل'),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  [
                    oeText(method['delivery_days_min']),
                    oeText(method['delivery_days_max']),
                  ].where((x) => x.isNotEmpty).join(' - ') +
                      ' يوم',
                  style: const TextStyle(fontSize: 8.5, color: ClientTheme.muted),
                ),
              ),
            const SizedBox(height: 5),
            const Text(
              'ملاحظة الطلب',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'ملاحظة أو تعليمات إضافية…',
              ),
            ),
            const SizedBox(height: 11),
            SizedBox(
              height: 49,
              child: FilledButton(
                onPressed: saving ? null : save,
                style: FilledButton.styleFrom(backgroundColor: Colors.black),
                child: saving
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Text(
                        'حفظ التعديلات وإعادة احتساب السعر',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderProductPicker extends StatefulWidget {
  final List<ProductModel> products;
  const _OrderProductPicker({required this.products});
  @override
  State<_OrderProductPicker> createState() => _OrderProductPickerState();
}
class _OrderProductPickerState extends State<_OrderProductPicker> {
  final search = TextEditingController();
  List<ProductModel> visible = const [];
  @override
  void initState() {
    super.initState();
    visible = widget.products;
    search.addListener(_filter);
  }
  void _filter() {
    final q = search.text.trim().toLowerCase();
    setState(() {
      visible = q.isEmpty
          ? widget.products
          : widget.products.where((p) => p.name.toLowerCase().contains(q)).toList();
    });
  }
  @override
  void dispose() {
    search.removeListener(_filter);
    search.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .86,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 13, 16, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('إضافة منتج', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                    Icon(Icons.shopping_bag_outlined),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: search,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'ابحث عن المنتج',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('لا توجد منتجات مطابقة.', style: TextStyle(fontSize: 10, color: ClientTheme.muted)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 7),
                        itemBuilder: (_, index) {
                          final product = visible[index];
                          return ListTile(
                            tileColor: const Color(0xFFF8F8F8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            leading: SizedBox(
                              width: 48,
                              height: 60,
                              child: product.image == null || product.image!.isEmpty
                                  ? Container(color: ClientTheme.soft)
                                  : Image.network(
                                      api.url(product.image),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(color: ClientTheme.soft),
                                    ),
                            ),
                            title: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                            subtitle: Text('${product.price} ${state.currencySymbol}', style: const TextStyle(fontSize: 9, color: ClientTheme.muted)),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => Navigator.pop(context, product),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
}
class _OrderVariantPicker extends StatelessWidget {
  final String productName;
  final List<Map<String, dynamic>> variants;
  final List<Map<String, dynamic>> colors;
  final List<Map<String, dynamic>> sizes;
  const _OrderVariantPicker({
    required this.productName,
    required this.variants,
    required this.colors,
    required this.sizes,
  });
  String label(Map<String, dynamic> variant) {
    final color = colors.where((x) => oeInt(x['id']) == oeInt(variant['color_id'])).toList();
    final size = sizes.where((x) => oeInt(x['id']) == oeInt(variant['size_id'])).toList();
    final parts = <String>[
      if (color.isNotEmpty) oeText(color.first['name']),
      if (size.isNotEmpty) oeText(size.first['label'], oeText(size.first['code'])),
    ].where((x) => x.trim().isNotEmpty).toList();
    return parts.isEmpty ? oeText(variant['sku'], 'اختيار المنتج') : parts.join(' · ');
  }
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(productName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('اختر اللون/المقاس المتاح قبل إضافة المنتج.', style: TextStyle(fontSize: 9, color: ClientTheme.muted)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: variants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, index) {
                    final variant = variants[index];
                    final available = oeInt(variant['available_qty']);
                    return ListTile(
                      tileColor: const Color(0xFFF8F8F8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      title: Text(label(variant), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                      subtitle: Text('المتاح: $available', style: const TextStyle(fontSize: 8.5, color: ClientTheme.success)),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => Navigator.pop(context, variant),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

// Returns the current shared ApiService token through the app singleton.
// Kept in a small function to avoid duplicate authentication storage.
String appApiTokenFallback() {
  return api.token;
}
