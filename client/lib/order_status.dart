/// Canonical order states and exact customer-facing filtering.
///
/// The API keeps stable machine-readable values; this file owns the Arabic
/// labels and filter matching used by the Flutter customer app.
String normalizeOrderValue(dynamic value) {
  return (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '_');
}

String normalizeOrderStatus(dynamic value) {
  final raw = normalizeOrderValue(value);
  const aliases = <String, String>{
    'canceled': 'cancelled',
    'cancel': 'cancelled',
    'intransit': 'in_transit',
    'outfordelivery': 'out_for_delivery',
    'pickedup': 'picked_up',
    'pending_payment': 'awaiting_payment',
    'waiting_payment': 'awaiting_payment',
    'waiting_for_payment': 'awaiting_payment',
    'waiting_confirmation': 'created',
    'pending_confirmation': 'created',
    'approved': 'awaiting_payment',
    'accepted': 'awaiting_payment',
  };
  return aliases[raw] ?? raw;
}

String normalizeShippingStatus(dynamic value) {
  final raw = normalizeOrderValue(value);
  const aliases = <String, String>{
    'canceled': 'cancelled',
    'intransit': 'in_transit',
    'outfordelivery': 'out_for_delivery',
    'pickedup': 'picked_up',
    'shipped': 'pending',
  };
  return aliases[raw] ?? raw;
}

/// Converts legacy shortcut keys to the current, explicit filter names.
String normalizeOrderFilter(String value) {
  final raw = normalizeOrderValue(value);
  const aliases = <String, String>{
    'confirmation': 'approval',
    'awaiting_approval': 'approval',
    'waiting_approval': 'approval',
    'pending_confirmation': 'approval',
    'pending_payment': 'payment',
    'awaiting_payment': 'payment',
    'shipped': 'shipping',
    'shipping_status': 'shipping',
    'completed': 'delivered',
    'complete': 'delivered',
    'delivery': 'delivered',
    'in_transit': 'in_transit',
    'returned_orders': 'returned',
  };
  return aliases[raw] ?? raw;
}

const Map<String, String> orderFilterLabels = <String, String>{
  'all': 'الكل',
  'approval': 'بانتظار الموافقة',
  'payment': 'بانتظار الدفع',
  'processing': 'قيد التجهيز',
  'shipping': 'الشحن',
  'in_transit': 'في الطريق',
  'delivered': 'تم التسليم',
  'returned': 'المرتجعة',
  'cancelled': 'ملغاة',
};

const Map<String, String> customerOrderStatusLabels = <String, String>{
  'created': 'بانتظار موافقة الطلب',
  'awaiting_payment': 'بانتظار الدفع',
  // "paid" is an internal transition; customers see it as the preparing stage.
  'paid': 'قيد التجهيز',
  'processing': 'قيد التجهيز',
  'shipped': 'تم الشحن',
  'in_transit': 'في الطريق',
  'delivered': 'تم التسليم',
  'returned': 'تمت الإعادة',
  'cancelled': 'ملغاة',
};

String orderStatusLabelForCustomer(
  dynamic status, {
  dynamic shippingStatus,
}) {
  final key = normalizeOrderStatus(status);
  final shipping = normalizeShippingStatus(shippingStatus);

  if (key == 'shipped') {
    if (shipping == 'delivered') return 'تم التسليم';
    if (const <String>{
      'picked_up',
      'in_transit',
      'out_for_delivery',
    }.contains(shipping)) {
      return 'في الطريق';
    }
    return 'تم الشحن';
  }

  if (key == 'in_transit') return 'في الطريق';
  return customerOrderStatusLabels[key] ?? 'حالة غير معروفة';
}

/// Filters are exact. An empty result stays empty; it never falls back to all
/// orders merely because the selected state has no matching orders.
bool orderMatchesFilter(Map<String, dynamic> row, String requestedFilter) {
  final filter = normalizeOrderFilter(requestedFilter);
  final status = normalizeOrderStatus(row['status']);
  final shipping = normalizeShippingStatus(row['shipping_status']);

  final isInTransit = status == 'in_transit' ||
      (status == 'shipped' &&
          const <String>{
            'picked_up',
            'in_transit',
            'out_for_delivery',
          }.contains(shipping));
  final isDelivered = status == 'delivered' || shipping == 'delivered';

  switch (filter) {
    case 'all':
      return true;
    case 'approval':
      return status == 'created';
    case 'payment':
      // A newly created order is not awaiting customer payment until the
      // store approves it, even though its payment_status is "unpaid".
      return status == 'awaiting_payment';
    case 'processing':
      return status == 'paid' || status == 'processing';
    case 'shipping':
      return status == 'shipped' && !isInTransit && !isDelivered;
    case 'in_transit':
      return isInTransit && !isDelivered;
    case 'delivered':
      return isDelivered;
    case 'returned':
      return status == 'returned';
    case 'cancelled':
      return status == 'cancelled';
    default:
      return false;
  }
}

/// Position within the five visible customer tracking stages.
int orderProgressIndex(Map<String, dynamic> row) {
  final status = normalizeOrderStatus(row['status']);
  final shipping = normalizeShippingStatus(row['shipping_status']);

  if (status == 'cancelled') return -1;
  if (status == 'delivered' || shipping == 'delivered') return 4;
  if (status == 'returned') return 4;
  if (status == 'in_transit' ||
      (status == 'shipped' &&
          const <String>{
            'picked_up',
            'in_transit',
            'out_for_delivery',
          }.contains(shipping))) {
    return 3;
  }
  if (status == 'shipped') return 2;
  if (status == 'paid' || status == 'processing') return 1;
  return 0;
}
