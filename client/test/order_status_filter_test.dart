import 'package:flutter_test/flutter_test.dart';
import 'package:altakhfid_client/order_status.dart';

void main() {
  group('orderMatchesFilter', () {
    test('a created unpaid order only matches approval, not payment', () {
      final order = <String, dynamic>{
        'status': 'created',
        'payment_status': 'unpaid',
        'shipping_status': 'pending',
      };

      expect(orderMatchesFilter(order, 'approval'), isTrue);
      expect(orderMatchesFilter(order, 'payment'), isFalse);
      expect(orderMatchesFilter(order, 'shipping'), isFalse);
    });

    test('empty status result remains empty instead of showing all orders', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{'status': 'created', 'shipping_status': 'pending'},
        <String, dynamic>{'status': 'cancelled', 'shipping_status': 'pending'},
      ];

      final visible = rows.where((row) => orderMatchesFilter(row, 'processing'));
      expect(visible, isEmpty);
    });

    test('awaiting payment appears in its own filter', () {
      final order = <String, dynamic>{
        'status': 'awaiting_payment',
        'payment_status': 'unpaid',
        'shipping_status': 'pending',
      };

      expect(orderMatchesFilter(order, 'payment'), isTrue);
      expect(orderMatchesFilter(order, 'approval'), isFalse);
      expect(orderStatusLabelForCustomer(order['status']), 'بانتظار الدفع');
    });

    test('in-transit shipment is not counted as merely shipped', () {
      final order = <String, dynamic>{
        'status': 'shipped',
        'shipping_status': 'in_transit',
      };

      expect(orderMatchesFilter(order, 'shipping'), isFalse);
      expect(orderMatchesFilter(order, 'in_transit'), isTrue);
      expect(
        orderStatusLabelForCustomer(
          order['status'],
          shippingStatus: order['shipping_status'],
        ),
        'في الطريق',
      );
    });

    test('a returned order is not shown in delivered results', () {
      final order = <String, dynamic>{
        'status': 'returned',
        'shipping_status': 'delivered',
      };
      expect(orderMatchesFilter(order, 'returned'), isTrue);
      expect(orderMatchesFilter(order, 'delivered'), isFalse);
    });

    test('supports legacy shortcut keys without broadening the filter', () {
      final shipped = <String, dynamic>{
        'status': 'shipped',
        'shipping_status': 'pending',
      };
      final delivered = <String, dynamic>{
        'status': 'delivered',
        'shipping_status': 'delivered',
      };

      expect(normalizeOrderFilter('shipped'), 'shipping');
      expect(normalizeOrderFilter('shiped'), 'shipping');
      expect(normalizeOrderFilter('proccessing'), 'processing');
      expect(normalizeOrderStatus('shiped'), 'shipped');
      expect(normalizeOrderStatus('proccessing'), 'processing');
      expect(normalizeOrderFilter('completed'), 'delivered');
      expect(orderMatchesFilter(<String, dynamic>{
        'status': 'shiped',
        'shipping_status': 'pending',
      }, 'shipping'), isTrue);
      expect(orderMatchesFilter(shipped, 'shipped'), isTrue);
      expect(orderMatchesFilter(delivered, 'completed'), isTrue);
      expect(orderMatchesFilter(shipped, 'not-a-state'), isFalse);
    });

    test('all canonical states are displayed in Arabic', () {
      const statuses = <String>[
        'created',
        'awaiting_payment',
        'paid',
        'processing',
        'shipped',
        'in_transit',
        'delivered',
        'returned',
        'cancelled',
      ];

      for (final status in statuses) {
        final label = orderStatusLabelForCustomer(status);
        expect(label, isNotEmpty);
        expect(label, isNot('created'));
        expect(RegExp(r'[a-zA-Z]').hasMatch(label), isFalse, reason: status);
      }
    });
  });
}
