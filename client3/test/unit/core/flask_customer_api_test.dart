import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_store/core/network/flask_api_client.dart';
import 'package:t_store/core/network/flask_customer_api.dart';

void main() {
  test('loads cities and currencies from the Flask API response shape',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _LookupAdapter((options) async {
      if (options.uri.path.endsWith('/geo/cities')) {
        return _jsonResponse(200, {
          'items': [
            {'id': 7, 'name': 'إب', 'region_id': 2},
            {'id': 8, 'name': 'صنعاء', 'region_id': 1},
          ],
        });
      }
      if (options.uri.path.endsWith('/pricing/currencies')) {
        return _jsonResponse(200, {
          'items': [
            {
              'id': 1,
              'code': 'SAR',
              'symbol': 'ر.س',
              'name_ar': 'الريال السعودي',
              'is_base': true,
            },
            {
              'id': 2,
              'code': 'YER',
              'symbol': 'ر.ي',
              'name_ar': 'الريال اليمني',
              'is_base': false,
            },
          ],
        });
      }
      return _jsonResponse(404, {'error': 'not_found'});
    });

    final api = FlaskCustomerApi(
      client: FlaskApiClient(
        dio: dio,
        baseUrl: 'https://example.test/api/v1',
      ),
    );

    final cities = await api.getCities();
    final currencies = await api.getCurrencies();

    expect(cities.map((item) => item.name).toList(), ['إب', 'صنعاء']);
    expect(cities.map((item) => item.id).toList(), [7, 8]);
    expect(currencies.first.code, 'SAR');
    expect(currencies.first.symbol, 'ر.س');
    expect(currencies.first.isDefault, isTrue);
    expect(currencies.last.code, 'YER');
  });
}

class _LookupAdapter implements HttpClientAdapter {
  _LookupAdapter(this.handler);

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
