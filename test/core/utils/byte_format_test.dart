import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/byte_format.dart';

void main() {
  test('responseSizeBytes prefers bodyBytes length', () {
    final r = HttpResponseEntity(
      statusCode: 200,
      body: '[binary]',
      headers: const {},
      durationMs: 1,
      bodyBytes: Uint8List(1234),
    );
    expect(responseSizeBytes(r), 1234);
  });

  test('responseSizeBytes prefers bodyBytes over Content-Length header', () {
    final r = HttpResponseEntity(
      statusCode: 200,
      body: '',
      headers: const {'content-length': '9999'},
      durationMs: 1,
      bodyBytes: Uint8List(42),
    );
    expect(responseSizeBytes(r), 42);
  });

  group('responseSizeBytes memoization', () {
    test('multibyte body: stable across repeated calls', () {
      // No bodyBytes, no content-length -> utf8 fallback path.
      final resp = HttpResponseEntity(
        statusCode: 200,
        body: 'café ☕ ${'x' * 1000}', // multibyte, so chars != bytes
        headers: const {},
        durationMs: 1,
      );
      final expected = utf8.encode(resp.body).length;
      expect(responseSizeBytes(resp), expected);
      // Second call must return the identical value (memoized, not recomputed).
      expect(responseSizeBytes(resp), expected);
    });
  });
}
