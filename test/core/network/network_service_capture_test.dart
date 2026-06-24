import 'dart:async';
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

  // Regression: on a real Dio socket adapter, cancelToken.cancel() during
  // cap-overflow can cause the body stream to emit a DioException(cancel)
  // that propagates out of the `await for`. The inner try/catch must absorb
  // it when overflow is already set — it must NOT fall through to the outer
  // DioException handler (which would throw a NetworkFailure).
  //
  // The fake returns a stream that yields an over-cap chunk then throws a
  // cancel DioException. The inner try/catch in network_service.dart absorbs
  // the cancel (capOverflow is true) and the result is still too-large.
  test(
    'cap-overflow cancel race → absorbed, returns too-large entity',
    () async {
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = _CancelRacingAdapter();
      final svc = NetworkService(dio: dio, maxResponseBytes: 10);

      // Must NOT throw; must return a normal entity with "too large" body.
      final r = await svc.request(url: 'https://x/big.mp4', method: 'GET');
      expect(r.body.toLowerCase(), contains('too large'));
      expect(r.bodyBytes, isNull);
    },
  );
}

/// Adapter that produces the cancel-race scenario: the response stream yields
/// an over-cap chunk and then throws a DioException(cancel) — simulating a
/// real socket adapter that emits a cancel error while data is in flight.
class _CancelRacingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      _chunksThenCancel(
        [List<int>.filled(100, 0)], // 100 bytes > 10-byte cap
        options,
      ),
      200,
      headers: {
        'content-type': ['video/mp4'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Yields [chunks] and then throws a DioException(cancel), simulating a
/// real socket adapter that delivers a cancel error after the response body
/// has started arriving.
Stream<Uint8List> _chunksThenCancel(
  List<List<int>> chunks,
  RequestOptions options,
) async* {
  for (final c in chunks) {
    yield Uint8List.fromList(c);
  }
  throw DioException(
    requestOptions: options,
    type: DioExceptionType.cancel,
  );
}
