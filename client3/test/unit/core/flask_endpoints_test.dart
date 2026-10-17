import 'package:flutter_test/flutter_test.dart';
import 'package:t_store/core/network/flask_endpoints.dart';

void main() {
  group('FlaskEndpoints', () {
    test('uses the customer storefront feed rather than the minimal search API',
        () {
      expect(FlaskEndpoints.storefrontHome, 'storefront/home');
      expect(FlaskEndpoints.categories, 'catalog/categories');
      expect(FlaskEndpoints.productFeed, 'catalog/products/feed');
      expect(FlaskEndpoints.productDetail(42), 'catalog/products/42');
      expect(FlaskEndpoints.searchProducts, 'search/products');
    });

    test('uses the registered customer-scoped cart and order routes', () {
      expect(FlaskEndpoints.customerCart, 'commerce/me/cart');
      expect(FlaskEndpoints.customerCartItems, 'commerce/me/cart/items');
      expect(FlaskEndpoints.customerCartItem(9), 'commerce/me/cart/items/9');
      expect(FlaskEndpoints.customerOrders, 'commerce/me/orders');
      expect(FlaskEndpoints.customerOrderDetail(17),
          'commerce/me/orders/17/detail');
    });

    test('paths are relative and preserve the /api/v1 base prefix', () {
      final paths = <String>[
        FlaskEndpoints.storefrontHome,
        FlaskEndpoints.categories,
        FlaskEndpoints.productFeed,
        FlaskEndpoints.productDetail(1),
        FlaskEndpoints.requestOtp,
        FlaskEndpoints.customerMe,
        FlaskEndpoints.customerCart,
        FlaskEndpoints.customerOrders,
      ];

      for (final path in paths) {
        expect(path.startsWith('/'), isFalse, reason: path);
        expect(Uri.parse(path).hasScheme, isFalse, reason: path);
        expect(Uri.parse(path).pathSegments, isNot(contains('..')),
            reason: path);
      }
    });
  });
}
