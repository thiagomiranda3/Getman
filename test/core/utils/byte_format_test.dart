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
}
