import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';

void main() {
  HttpResponseEntity make({Uint8List? bytes}) => HttpResponseEntity(
    statusCode: 200,
    body: 'x',
    headers: const {},
    durationMs: 1,
    bodyBytes: bytes,
  );

  test('bodyBytes defaults to null', () {
    expect(
      const HttpResponseEntity(
        statusCode: 200,
        body: '',
        headers: {},
        durationMs: 0,
      ).bodyBytes,
      isNull,
    );
  });

  test('equality uses bodyBytes length, not identity', () {
    final a = make(bytes: Uint8List.fromList([1, 2, 3]));
    final b = make(bytes: Uint8List.fromList([9, 9, 9]));
    final c = make(bytes: Uint8List.fromList([1, 2]));
    expect(a, equals(b)); // same length → equal
    expect(a, isNot(equals(c))); // different length → not equal
  });

  test('copyWithBody preserves bodyBytes by default', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final r = make(bytes: bytes).copyWithBody('placeholder');
    expect(r.body, 'placeholder');
    expect(r.bodyBytes, bytes);
  });

  test('copyWithBody(keepBytes: false) drops bodyBytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final r = make(bytes: bytes).copyWithBody('placeholder', keepBytes: false);
    expect(r.body, 'placeholder');
    // The history downgrade path relies on this to release superseded media
    // buffers (S5) — status/headers/duration still ride along.
    expect(r.bodyBytes, isNull);
    expect(r.statusCode, 200);
    expect(r.durationMs, 1);
  });
}
