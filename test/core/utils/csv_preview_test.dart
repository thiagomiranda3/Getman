import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/csv_preview.dart';

void main() {
  test('retains 500 body rows while counting the complete CSV', () {
    final source =
        'name,note\n${List.generate(10000, (i) => '$i,"a\nb"').join('\n')}';
    final preview = parseCsvPreview(Uint8List.fromList(utf8.encode(source)));
    expect(preview.totalBodyRows, 10000);
    expect(preview.rows.length, 501);
    expect(preview.rows.last, ['499', 'a\nb']);
  });

  test('stream boundaries preserve UTF-8, quotes and CRLF', () {
    for (var offset = -4; offset <= 4; offset++) {
      final source = 'h,n\r\n"${'x' * (16384 + offset)}😀","a""b\r\nc"\r\n1,2';
      final preview = parseCsvPreview(Uint8List.fromList(utf8.encode(source)));
      expect(
        preview.rows,
        Csv(autoDetect: false).decode(source),
        reason: '$offset',
      );
      expect(preview.totalBodyRows, 2);
    }
  });

  test('empty and malformed UTF-8 preserve viewer semantics', () {
    expect(parseCsvPreview(Uint8List(0)).rows, isEmpty);
    final preview = parseCsvPreview(Uint8List.fromList([255, 44, 65]));
    expect(preview.rows, [
      ['�', 'A'],
    ]);
    expect(preview.totalBodyRows, 0);
  });
}
