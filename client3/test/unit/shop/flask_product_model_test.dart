import 'package:flutter_test/flutter_test.dart';
import 'package:t_store/features/shop/data/models/product_model.dart';

void main() {
  group('ProductModel.fromFlaskJson', () {
    test('maps final customer price, compare-at price, images, currency and stock',
        () {
      final product = ProductModel.fromFlaskJson({
        'id': 42,
        'sku': 'AB-42',
        'name': 'عباءة عملية',
        'description': 'وصف المنتج',
        'price': '18.50',
        'compare_at_price': '25.00',
        'base_price_sar': '11.00',
        'currency_code': 'YER',
        'images': ['/media/products/abaya.webp'],
        'brand': {'id': 3, 'name': 'متجر التخفيض'},
        'category_ids': [7],
        'available_qty': 4,
        'in_stock': true,
        'rating': 4.8,
        'review_count': 12,
        'status': 'published',
        'badges': [
          {'id': 1, 'name': 'جديد'}
        ],
      });

      expect(product.id, '42');
      expect(product.name, 'عباءة عملية');
      expect(product.categoryId, '7');
      expect(product.brandId, '3');
      expect(product.brandName, 'متجر التخفيض');
      expect(product.price, 25.0);
      expect(product.salePrice, 18.5);
      expect(product.effectivePrice, 18.5);
      expect(product.hasDiscount, isTrue);
      expect(product.discountPercentage, closeTo(26.0, 0.001));
      expect(product.stock, 4);
      expect(product.currencyCode, 'YER');
      expect(product.images, [
        'https://takhfidsh.alattab.site/media/products/abaya.webp',
      ]);
      expect(product.thumbnail, product.images.first);
      expect(product.rating, 4.8);
      expect(product.reviewsCount, 12);
      expect(product.attributes?['badges'], isA<List>());
    });

    test('does not invent a discount when compare-at price is missing or lower',
        () {
      final product = ProductModel.fromFlaskJson({
        'id': 9,
        'name': 'حزام',
        'price': '7.25',
        'compare_at_price': '6.00',
        'currency_code': 'SAR',
        'images': [],
        'available_qty': 0,
        'status': 'published',
      });

      expect(product.price, 7.25);
      expect(product.salePrice, isNull);
      expect(product.effectivePrice, 7.25);
      expect(product.hasDiscount, isFalse);
      expect(product.images, isEmpty);
      expect(product.isInStock, isFalse);
    });
  });
}
