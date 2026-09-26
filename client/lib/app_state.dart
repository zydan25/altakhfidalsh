import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

final api = ApiService();

class ClientState {
  Set<int> wishlist = <int>{};
  int? currencyId;
  String currencyCode = 'SAR';
  String currencySymbol = 'ر.س';
  int? cityId;
  String? cityName;

  bool get loggedIn => api.token.isNotEmpty;

  Future<void> restorePreferences() async {
    final p = await SharedPreferences.getInstance();
    currencyId = p.getInt('currency_id');
    currencyCode = p.getString('currency_code') ?? 'SAR';
    currencySymbol = p.getString('currency_symbol') ?? 'ر.س';
    cityId = p.getInt('city_id');
    cityName = p.getString('city_name');
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
  }

  Future<void> setCity({required int id, required String name}) async {
    cityId = id;
    cityName = name;
    final p = await SharedPreferences.getInstance();
    await p.setInt('city_id', id);
    await p.setString('city_name', name);
  }

  Future<void> clearSession() async {
    wishlist = <int>{};
    cityId = null;
    cityName = null;
    await api.logout();
    final p = await SharedPreferences.getInstance();
    await p.remove('city_id');
    await p.remove('city_name');
  }
}

final state = ClientState();
