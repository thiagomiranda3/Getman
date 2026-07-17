import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.bytes, required this.headers});
  final List<int> bytes;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(bytes, 200, headers: headers);

  @override
  void close({bool force = false}) {}
}

NetworkService serviceReturning(
  List<int> bytes,
  Map<String, List<String>> headers, {
  int maxResponseBytes = 50 * 1024 * 1024,
}) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = _FakeAdapter(bytes: bytes, headers: headers);
  return NetworkService(dio: dio, maxResponseBytes: maxResponseBytes);
}

void main() {
  test('textual response decodes to body, no bodyBytes', () async {
    final svc = serviceReturning(
      utf8.encode('{"a":1}'),
      {
        'content-type': ['application/json'],
      },
    );
    final r = await svc.request(url: 'https://x/y', method: 'GET');
    expect(r.body, '{"a":1}');
    expect(r.bodyBytes, isNull);
  });

  test('image response keeps bytes + placeholder body', () async {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final svc = serviceReturning(png, {
      'content-type': ['image/png'],
    });
    final r = await svc.request(url: 'https://x/a.png', method: 'GET');
    expect(r.bodyBytes, png);
    expect(r.body, contains('image/png'));
  });

  test('content-length over cap → no bytes, too-large placeholder', () async {
    final svc = serviceReturning(
      List<int>.filled(100, 0),
      {
        'content-type': ['video/mp4'],
        'content-length': ['999999999'],
      },
      maxResponseBytes: 10,
    );
    final r = await svc.request(url: 'https://x/big.mp4', method: 'GET');
    expect(r.bodyBytes, isNull);
    expect(r.body.toLowerCase(), contains('too large'));
  });

  test(
    'stream exceeding cap (no content-length) → too-large placeholder',
    () async {
      final svc = serviceReturning(
        List<int>.filled(5000, 7),
        {
          'content-type': ['video/mp4'],
        },
        maxResponseBytes: 100,
      );
      final r = await svc.request(url: 'https://x/big.mp4', method: 'GET');
      expect(r.bodyBytes, isNull);
      expect(r.body.toLowerCase(), contains('too large'));
    },
  );

  test('empty body → empty string, no bytes', () async {
    final svc = serviceReturning(const [], {
      'content-type': ['image/png'],
    });
    final r = await svc.request(url: 'https://x/a.png', method: 'GET');
    expect(r.body, '');
    expect(r.bodyBytes, isNull);
  });

  test('iso-8859-1 charset decodes with latin1, not utf8', () async {
    // 0xE9 is "é" in ISO-8859-1 but an invalid lone UTF-8 byte.
    final svc = serviceReturning(
      [0xE9],
      {
        'content-type': ['text/plain; charset=iso-8859-1'],
      },
    );
    final r = await svc.request(url: 'https://x/y', method: 'GET');
    expect(r.body, 'é');
  });

  test('default (no charset) decodes as utf8', () async {
    final svc = serviceReturning(
      utf8.encode('café'),
      {
        'content-type': ['text/plain'],
      },
    );
    final r = await svc.request(url: 'https://x/y', method: 'GET');
    expect(r.body, 'café');
  });
}
