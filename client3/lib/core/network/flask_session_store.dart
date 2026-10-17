import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistence for Flask-issued customer sessions.
/// Tokens are never logged and are only attached to the configured Flask API.
abstract final class FlaskSessionStore {
  static const _accessTokenKey = 'flask_customer_access_token';
  static const _refreshTokenKey = 'flask_customer_refresh_token';
  static const _customerIdKey = 'flask_customer_id';

  static Future<String?> accessToken() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_accessTokenKey);
    return value == null || value.trim().isEmpty ? null : value;
  }

  static Future<void> saveSession(Map<String, dynamic> payload) async {
    final accessToken = payload['access_token']?.toString().trim() ?? '';
    final refreshToken = payload['refresh_token']?.toString().trim() ?? '';
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const FormatException('لم يُرجع الخادم بيانات جلسة مكتملة.');
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accessTokenKey, accessToken);
    await preferences.setString(_refreshTokenKey, refreshToken);
    final customerId = payload['customer_id'];
    if (customerId != null) {
      await preferences.setString(_customerIdKey, customerId.toString());
    }
  }

  static Future<String?> refreshToken() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_refreshTokenKey);
    return value == null || value.trim().isEmpty ? null : value;
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_refreshTokenKey);
    await preferences.remove(_customerIdKey);
  }
}
