import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_store/core/network/api_config.dart';
import 'package:t_store/core/network/flask_api_client.dart';

void main() {
  group('ApiConfig', () {
    test('normalizes the API base URL and preserves its prefix', () {
      expect(
        ApiConfig.normalizeBaseUrl('  https://example.test/api/v1///  '),
        'https://example.test/api/v1/',
      );
    });

    test('rejects invalid or credential-bearing API URLs', () {
      expect(
        () => ApiConfig.normalizeBaseUrl('ftp://example.test/api/v1'),
        throwsFormatException,
      );
      expect(
        () => ApiConfig.normalizeBaseUrl('https://user:pass@example.test/api'),
        throwsFormatException,
      );
      expect(
        () => ApiConfig.normalizeBaseUrl('https://example.test/api?token=x'),
        throwsFormatException,
      );
    });

    test('resolves media paths against the host root', () {
      expect(
        ApiConfig.resolveMediaUrl(
          '/media/products/item.jpg',
          apiBaseUrl: 'https://example.test/api/v1',
        ),
        'https://example.test/media/products/item.jpg',
      );
    });

    test('leaves absolute HTTP(S) media URLs unchanged', () {
      expect(
        ApiConfig.resolveMediaUrl('https://cdn.example.test/item.jpg'),
        'https://cdn.example.test/item.jpg',
      );
      expect(ApiConfig.resolveMediaUrl('  '), '');
    });
  });

  group('FlaskApiClient', () {
    test('preserves the API prefix and sends a supplied Bearer token',
        () async {
      RequestOptions? captured;
      final dio = Dio();
      dio.httpClientAdapter = _CallbackAdapter((options) async {
        captured = options;
        return _jsonResponse(200, {'ok': true});
      });

      final client = FlaskApiClient(
        dio: dio,
        baseUrl: 'https://example.test/api/v1',
        accessTokenProvider: () async => 'test-access-token',
      );

      final result = await client.get('/catalog/products', queryParameters: {
        'page': 2,
      });

      expect(result, {'ok': true});
      expect(captured!.uri.path, '/api/v1/catalog/products');
      expect(captured!.uri.queryParameters['page'], '2');
      expect(captured!.headers['Authorization'], 'Bearer test-access-token');
      expect(captured!.headers['Accept'], 'application/json');
    });

    test('rejects absolute URLs before sending a request', () async {
      final dio = Dio();
      var reachedAdapter = false;
      dio.httpClientAdapter = _CallbackAdapter((options) async {
        reachedAdapter = true;
        return _jsonResponse(200, {'ok': true});
      });

      final client = FlaskApiClient(
        dio: dio,
        baseUrl: 'https://example.test/api/v1',
        accessTokenProvider: () async => 'test-access-token',
      );

      await expectLater(
        client.get('https://attacker.example/collect'),
        throwsA(isA<ArgumentError>()),
      );
      expect(reachedAdapter, isFalse);
    });

    test('normalizes Flask error/detail responses', () async {
      final dio = Dio();
      dio.httpClientAdapter = _CallbackAdapter((options) async {
        return _jsonResponse(401, {
          'error': 'unauthorized',
          'detail': 'The session has expired.',
        });
      });

      final client = FlaskApiClient(
        dio: dio,
        baseUrl: 'https://example.test/api/v1',
      );

      await expectLater(
        client.get('customer/me'),
        throwsA(
          isA<FlaskApiException>()
              .having((error) => error.statusCode, 'status code', 401)
              .having(
                (error) => error.message,
                'server detail',
                'The session has expired.',
              ),
        ),
      );
    });
  });
}

class _CallbackAdapter implements HttpClientAdapter {
  _CallbackAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(int statusCode, Object body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: const {
      'content-type': ['application/json; charset=utf-8'],
    },
  );
}
