import 'package:altakhfid_client2_bridge/src/flask_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('FlaskApiClient', () {
    test('keeps requests under the configured API prefix', () async {
      final client = FlaskApiClient(
        baseUrl: 'https://example.test/api/v1/',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/catalog/products/feed');
          expect(request.url.queryParameters['q'], 'red shoes');
          return http.Response('{"items":[]}', 200);
        }),
      );

      final result = await client.get(
        '/catalog/products/feed',
        query: {'q': 'red shoes'},
      );

      expect(result, {'items': []});
      client.close();
    });

    test('adds a bearer token when provided', () async {
      final client = FlaskApiClient(
        baseUrl: 'https://example.test/api/v1',
        accessTokenReader: () async => 'example-token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer example-token');
          expect(request.headers['Accept'], 'application/json');
          return http.Response('{"item":{"id":1}}', 200);
        }),
      );

      final result = await client.get('/customer/me');
      expect(result, {'item': {'id': 1}});
      client.close();
    });

    test('surfaces Flask error/detail as a typed exception', () async {
      final client = FlaskApiClient(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async => http.Response(
              '{"error":"not allowed","detail":"Access denied"}',
              403,
            )),
      );

      await expectLater(
        client.get('/customer/me'),
        throwsA(
          isA<FlaskApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', 'Access denied'),
        ),
      );
      client.close();
    });

    test('rejects absolute API paths to protect bearer tokens', () {
      final client = FlaskApiClient(
        baseUrl: 'https://example.test/api/v1',
        accessTokenReader: () async => 'should-not-leak',
        client: MockClient((request) async => http.Response('{}', 200)),
      );

      expect(
        () => client.uriFor('https://untrusted.example.test/collect'),
        throwsArgumentError,
      );
      client.close();
    });

    test('resolves root-relative media URLs at the server origin', () {
      final client = FlaskApiClient(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async => http.Response('{}', 200)),
      );

      expect(
        client.resolveUrl('/media/products/item.jpg'),
        'https://example.test/media/products/item.jpg',
      );
      expect(
        client.resolveUrl('https://cdn.example.test/item.jpg'),
        'https://cdn.example.test/item.jpg',
      );
      client.close();
    });
  });
}
