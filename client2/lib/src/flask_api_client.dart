import 'dart:convert';

import 'package:http/http.dart' as http;

/// Loads the saved access token. Keep token storage owned by the app layer.
typedef AccessTokenReader = Future<String> Function();

/// A decoded API failure returned by Flask.
class FlaskApiException implements Exception {
  const FlaskApiException({
    this.statusCode: 0,
    this.message: '',
    this.payload,
  });

  final int statusCode;
  final String message;
  final dynamic payload;

  @override
  String toString() => 'FlaskApiException($statusCode): $message';
}

/// HTTP transport for the existing Flask API.
///
/// Keep this file compatible with the Dart language version declared by the
/// original app (>=2.7.0 <3.0.0). It deliberately contains no UI code.
class FlaskApiClient {
  FlaskApiClient({
    String baseUrl,
    http.Client client,
    AccessTokenReader accessTokenReader,
    this.timeout = const Duration(seconds: 25),
  })  : baseUrl = _normalizeBaseUrl(
          baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'https://takhfidsh.alattab.site/api/v1',
              ),
        ),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _accessTokenReader = accessTokenReader;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final AccessTokenReader _accessTokenReader;
  final Duration timeout;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'Must not be empty.');
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  /// Builds an API URL under [baseUrl] while preserving optional query values.
  Uri uriFor(String path, {Map<String, dynamic> query}) {
    final raw = path.trim();
    if (raw.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty.');
    }

    if (raw.startsWith('https://') || raw.startsWith('http://')) {
      throw ArgumentError.value(
        path,
        'path',
        'API requests must use a relative path so bearer tokens stay on the API origin.',
      );
    }
    final relativePath = raw.replaceFirst(RegExp(r'^/+'), '');
    final initial = Uri.parse('$baseUrl/$relativePath');

    final params = <String, String>{};
    params.addAll(initial.queryParameters);
    if (query != null) {
      query.forEach((key, value) {
        if (value == null) return;
        params[key] = value is Iterable ? value.join(',') : value.toString();
      });
    }

    return initial.replace(queryParameters: params.isEmpty ? null : params);
  }

  /// Resolves absolute media links and root-relative Flask paths such as
  /// /media/products/example.jpg. Relative values resolve under the API prefix.
  String resolveUrl(String value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('https://') || raw.startsWith('http://')) return raw;

    final base = Uri.parse(baseUrl);
    if (raw.startsWith('/')) {
      return base.replace(path: raw, query: null, fragment: null).toString();
    }
    return uriFor(raw).toString();
  }

  Future<dynamic> get(String path, {Map<String, dynamic> query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic> body,
    Map<String, dynamic> query,
  }) =>
      _send('POST', path, body: body, query: query);

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic> body,
    Map<String, dynamic> query,
  }) =>
      _send('PATCH', path, body: body, query: query);

  Future<dynamic> put(
    String path, {
    Map<String, dynamic> body,
    Map<String, dynamic> query,
  }) =>
      _send('PUT', path, body: body, query: query);

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic> query,
    Map<String, dynamic> body,
  }) =>
      _send('DELETE', path, body: body, query: query);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic> query,
    Map<String, dynamic> body,
  }) async {
    final request = http.Request(method, uriFor(path, query: query));
    request.headers['Accept'] = 'application/json';

    final token = (await _accessTokenReader?.call())?.trim() ?? '';
    if (token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    return _decodeResponse(response);
  }

  /// Sends a multipart request with files prepared by the calling platform
  /// layer. This keeps the transport independent from dart:io and usable on web.
  Future<dynamic> upload(
    String path, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
    Map<String, dynamic> query,
  }) async {
    final request = http.MultipartRequest('POST', uriFor(path, query: query));
    request.headers['Accept'] = 'application/json';

    final token = (await _accessTokenReader?.call())?.trim() ?? '';
    if (token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields.addAll(fields);
    request.files.addAll(files);

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    return _decodeResponse(response);
  }

  dynamic _decodeResponse(http.Response response) {
    final responseText =
        utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (responseText.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) return null;
      throw FlaskApiException(
        statusCode: response.statusCode,
        message: 'تعذر تنفيذ الطلب (${response.statusCode}).',
      );
    }

    dynamic payload;
    try {
      payload = jsonDecode(responseText);
    } on FormatException {
      payload = responseText;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    var message = 'تعذر تنفيذ الطلب (${response.statusCode}).';
    if (payload is Map) {
      final candidate =
          payload['detail'] ?? payload['error'] ?? payload['message'];
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        message = candidate.toString();
      }
    } else if (payload is String && payload.isNotEmpty) {
      message = payload;
    }

    throw FlaskApiException(
      statusCode: response.statusCode,
      message: message,
      payload: payload,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Known customer-facing routes in the existing Flask API. Feature-specific
/// adapters must still validate and map each response's exact JSON shape.
abstract class FlaskEndpoints {
  static const home = '/storefront/home';
  static const banners = '/storefront/banners';
  static const categories = '/catalog/categories';
  static const products = '/catalog/products';
  static const productFeed = '/catalog/products/feed';
  static const searchProducts = '/search/products';
  static const requestOtp = '/customer/auth/request-otp';
  static const verifyOtp = '/customer/auth/verify-otp';
  static const me = '/customer/me';
  static const addresses = '/customer/me/addresses';
  static const wishlist = '/customer/me/wishlist';
  static const cart = '/commerce/me/cart';
  static const cartItems = '/commerce/me/cart/items';
  static const orders = '/commerce/me/orders';
  static const shippingMethods = '/commerce/shipping-methods';
  static const paymentMethods = '/commerce/payment-methods';
  static const conversations = '/support/conversations';
  static const policies = '/system/policies';
}
