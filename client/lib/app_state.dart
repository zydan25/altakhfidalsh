import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'notifications_service.dart';

final api = ApiService();
final cartBadge = ValueNotifier<int>(0);
final notificationBadge = ValueNotifier<int>(0);

Future<void> refreshNotificationBadge() async {
  if (api.token.isEmpty) {
    notificationBadge.value = 0;
    return;
  }
  try {
    final data = await api.notificationSummary();
    notificationBadge.value = int.tryParse(
          (data['unread_count'] ?? 0).toString(),
        ) ??
        0;
  } catch (_) {}
}

class ClientState {
  Set<int> wishlist = <int>{};
  int? currencyId;
  String currencyCode = 'SAR';
  String currencySymbol = 'ر.س';
  int? cityId;
  String? cityName;

  bool get loggedIn => api.token.isNotEmpty;

  Future<void> restorePreferences({bool fetchServer = true}) async {
    final p = await SharedPreferences.getInstance();
    currencyId = p.getInt('currency_id');
    currencyCode = p.getString('currency_code') ?? 'SAR';
    currencySymbol = p.getString('currency_symbol') ?? 'ر.س';
    cityId = p.getInt('city_id');
    cityName = p.getString('city_name');

    // Server preferences are authoritative after login. Local values keep the
    // storefront responsive when the server is temporarily unavailable.
    if (fetchServer && api.token.isNotEmpty) {
      try {
        final raw = await api.me();
        final item = raw['item'];
        if (item is Map) {
          final me = Map<String, dynamic>.from(item);
          final serverCurrencyId = int.tryParse(
            (me['preferred_currency_id'] ?? '').toString(),
          );
          if (serverCurrencyId != null && serverCurrencyId > 0) {
            currencyId = serverCurrencyId;
            final currencies = await api.currencies();
            final match = currencies.firstWhere(
              (x) => int.tryParse((x['id'] ?? '').toString()) == currencyId,
              orElse: () => <String, dynamic>{},
            );
            if (match.isNotEmpty) {
              currencyCode = (match['code'] ?? currencyCode).toString();
              currencySymbol = (match['symbol'] ?? currencyCode).toString();
            }
          }
          final serverCityId = int.tryParse((me['city_id'] ?? '').toString());
          if (serverCityId != null && serverCityId > 0) {
            cityId = serverCityId;
            cityName = (me['city_name'] ?? cityName)?.toString();
          }
        }
        if (currencyId != null) {
          await p.setInt('currency_id', currencyId!);
          await p.setString('currency_code', currencyCode);
          await p.setString('currency_symbol', currencySymbol);
        }
        if (cityId != null) {
          await p.setInt('city_id', cityId!);
          if (cityName != null) await p.setString('city_name', cityName!);
        }
      } catch (_) {}
    }
  }

  Future<void> setCurrency({
    required int id,
    required String code,
    required String symbol,
  }) async {
    currencyId = id;
    currencyCode = code;
    currencySymbol = symbol;
    final p = await SharedPreferences.getInstance();
    await p.setInt('currency_id', id);
    await p.setString('currency_code', code);
    await p.setString('currency_symbol', symbol);
    if (api.token.isNotEmpty) {
      await api.updateMe({'preferred_currency_id': id});
    }
  }

  Future<void> setCity({required int id, required String name}) async {
    cityId = id;
    cityName = name;
    final p = await SharedPreferences.getInstance();
    await p.setInt('city_id', id);
    await p.setString('city_name', name);
    if (api.token.isNotEmpty) {
      await api.updateMe({'city_id': id, 'city_area_id': null});
    }
  }

  Future<void> clearSession() async {
    wishlist = <int>{};
    cityId = null;
    cityName = null;
    cartBadge.value = 0;
    notificationBadge.value = 0;
    await AltakhfidNotificationService.stop();
    await api.logout();
    final p = await SharedPreferences.getInstance();
    await p.remove('city_id');
    await p.remove('city_name');
  }
}

final state = ClientState();
