import 'package:dio/dio.dart';

import 'api_config.dart';

typedef AccessTokenProvider = Future<String?> Function();

/// Shared HTTP transport for the Flask API.
/// Session storage and feature repositories are wired in a later phase.
class FlaskApiClient {
  FlaskApiClient({
    Dio? dio,
    String? baseUrl,
    AccessTokenProvider? accessTokenProvider,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration receiveTimeout = const Duration(seconds: 25),
  })  : baseUrl = ApiConfig.normalizeBaseUrl(baseUrl ?? ApiConfig.baseUrl),
        _dio = dio ?? Dio(),
        _accessTokenProvider = accessTokenProvider {
    _dio.options.baseUrl = this.baseUrl;
    _dio.options.connectTimeout = connectTimeout;
    _dio.options.receiveTimeout = receiveTimeout;
    _dio.options.headers = <String, dynamic>{
      ..._dio.options.headers,
      'Accept': 'application/json',
    };
  }

  final String baseUrl;
  final Dio _dio;
  final AccessTokenProvider? _accessTokenProvider;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) =>
      _request('GET', path, queryParameters: queryParameters);

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) =>
      _request('POST', path, data: data, queryParameters: queryParameters);

  Future<dynamic> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) =>
      _request('PATCH', path, data: data, queryParameters: queryParameters);

  Future<dynamic> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) =>
      _request('DELETE', path, data: data, queryParameters: queryParameters);

  Future<dynamic> _request(
    String method,
    String rawPath, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final path = _normalizeRelativePath(rawPath);
    final headers = <String, dynamic>{};
    final token = await _accessTokenProvider?.call();

    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }

    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: headers),
      );
      return response.data;
    } on DioException catch (error) {
      throw FlaskApiException.fromDioException(error);
    }
  }

  String _normalizeRelativePath(String rawPath) {
    final value = rawPath.trim();
    final uri = Uri.tryParse(value);

    if (value.isEmpty ||
        uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.pathSegments.contains('..')) {
      throw ArgumentError.value(
        rawPath,
        'path',
        'Use a relative Flask API path; absolute URLs and parent paths are not allowed.',
      );
    }

    final normalized = value.replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty) {
      throw ArgumentError.value(rawPath, 'path', 'API path cannot be empty.');
    }
    return normalized;
  }
}

/// Normalized error returned by the Flask API client.
class FlaskApiException implements Exception {
  const FlaskApiException({
    required this.message,
    this.statusCode,
    this.responseData,
  });

  final String message;
  final int? statusCode;
  final dynamic responseData;

  factory FlaskApiException.fromDioException(DioException error) {
    final data = error.response?.data;
    String? serverMessage;
    if (data is Map) {
      serverMessage = _nonEmptyString(data['detail']) ??
          _nonEmptyString(data['error']) ??
          _nonEmptyString(data['message']);
    }

    final isNetworkError =
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError;
    final fallback = isNetworkError
        ? 'تعذر الاتصال بالخادم. تحقق من الاتصال بالإنترنت ثم أعد المحاولة.'
        : 'حدث خطأ أثناء تنفيذ الطلب.';

    return FlaskApiException(
      message: serverMessage ?? error.message ?? fallback,
      statusCode: error.response?.statusCode,
      responseData: data,
    );
  }

  static String? _nonEmptyString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  String toString() => 'FlaskApiException($statusCode): $message';
}
