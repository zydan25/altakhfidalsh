import 'package:t_store/core/network/flask_api_client.dart';
import 'package:t_store/core/network/flask_session_store.dart';
import 'package:t_store/features/auth/domain/entities/user_entity.dart';

class FlaskLookupOption {
  const FlaskLookupOption({
    required this.id,
    required this.name,
    this.code,
    this.symbol,
    this.isDefault = false,
  });

  final int id;
  final String name;
  final String? code;
  final String? symbol;
  final bool isDefault;

  String get label {
    final currencyCode = code?.trim() ?? '';
    if (currencyCode.isEmpty) return name;
    final currencySymbol = symbol?.trim() ?? '';
    return currencySymbol.isEmpty
        ? '$name ($currencyCode)'
        : '$name ($currencyCode · $currencySymbol)';
  }
}

class FlaskOtpRequest {
  const FlaskOtpRequest({
    required this.id,
    required this.phone,
    required this.expiresAt,
  });

  final int id;
  final String phone;
  final String? expiresAt;
}

/// Customer-facing data access for the existing Flask API.
/// All paths are relative to /api/v1 and no Flask routes or tables are created here.
class FlaskCustomerApi {
  FlaskCustomerApi({required FlaskApiClient client}) : _client = client;

  final FlaskApiClient _client;

  Future<List<FlaskLookupOption>> getCities() async {
    final response = await _client.get('geo/cities');
    return _items(response).map((row) {
      return FlaskLookupOption(
        id: _toInt(row['id']),
        name: _string(row['name']).isEmpty ? 'مدينة' : _string(row['name']),
        code: _nullableString(row['code']),
      );
    }).where((option) => option.id > 0).toList(growable: false);
  }

  Future<List<FlaskLookupOption>> getCurrencies() async {
    final response = await _client.get('pricing/currencies');
    return _items(response).map((row) {
      final code = _string(row['code']);
      final name = _string(row['name_ar']);
      return FlaskLookupOption(
        id: _toInt(row['id']),
        name: name.isEmpty ? code : name,
        code: code.isEmpty ? null : code,
        symbol: _nullableString(row['symbol']),
        isDefault: row['is_base'] == true,
      );
    }).where((option) => option.id > 0).toList(growable: false);
  }

  Future<FlaskOtpRequest> requestOtp({
    required String phone,
    String purpose = 'login',
  }) async {
    final response = await _client.post(
      'customer/auth/request-otp',
      data: <String, dynamic>{
        'phone': phone.trim(),
        'purpose': purpose,
      },
    );
    final payload = _unwrap(response);
    final requestId = _toInt(
      payload['otp_request_id'] ??
          (response is Map ? response['otp_request_id'] : null),
    );
    if (requestId <= 0) {
      throw const FormatException('لم يُرجع الخادم معرّف طلب رمز التحقق.');
    }
    return FlaskOtpRequest(
      id: requestId,
      phone: _string(payload['phone']).isEmpty
          ? phone.trim()
          : _string(payload['phone']),
      expiresAt: _nullableString(payload['expires_at']),
    );
  }

  Future<UserEntity> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    final response = await _client.post(
      'customer/auth/password/login',
      data: <String, dynamic>{
        'phone': phone.trim(),
        'password': password,
        'device_id': 'client3',
      },
    );
    final session = _unwrap(response);
    await FlaskSessionStore.saveSession(session);
    return getCurrentCustomer();
  }

  Future<UserEntity> verifyRegistrationOtp({
    required int otpRequestId,
    required String code,
    required String phone,
    required Map<String, dynamic> registration,
  }) async {
    final response = await _client.post(
      'customer/auth/verify-otp',
      data: <String, dynamic>{
        'otp_request_id': otpRequestId,
        'code': code.trim(),
        'phone': phone.trim(),
        'device_id': 'client3',
        'registration': registration,
      },
    );
    final session = _unwrap(response);
    await FlaskSessionStore.saveSession(session);
    return getCurrentCustomer();
  }

  Future<UserEntity> getCurrentCustomer() async {
    final response = await _client.get('customer/me');
    final payload = _unwrap(response);
    return UserEntity(
      id: _string(payload['id'] ?? payload['customer_id']),
      email: _string(payload['email']),
      fullName: _nullableString(payload['name']),
      phone: _nullableString(
        payload['phone_normalized'] ?? payload['phone'],
      ),
    );
  }

  Future<void> logout() async {
    try {
      await _client.post('customer/auth/logout');
    } finally {
      await FlaskSessionStore.clear();
    }
  }

  static List<Map<String, dynamic>> _items(dynamic response) {
    if (response is! Map) {
      throw const FormatException('صيغة البيانات التي أعادها الخادم غير صحيحة.');
    }
    final rows = response['items'];
    if (rows is! List) {
      throw const FormatException('لم تُرجع الواجهة قائمة بيانات.');
    }
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Map<String, dynamic> _unwrap(dynamic response) {
    if (response is! Map) {
      throw const FormatException('صيغة الاستجابة التي أعادها الخادم غير صحيحة.');
    }
    final item = response['item'];
    if (item is Map) return Map<String, dynamic>.from(item);
    return Map<String, dynamic>.from(response);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static String? _nullableString(dynamic value) {
    final result = _string(value);
    return result.isEmpty ? null : result;
  }
}
