import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/large_response_text.dart';

void main() {
  test('minified 11.3 MB body is losslessly split into bounded chunks', () {
    final body = '{"data":"${'x' * 11300000}"}';
    final ends = responseTextChunkEnds(body);
    final rebuilt = StringBuffer();
    var start = 0;
    for (final end in ends) {
      expect(end - start, inInclusiveRange(1, 4096));
      rebuilt.write(body.substring(start, end));
      start = end;
    }
    expect(rebuilt.toString() == body, isTrue);
  });

  test('prefers complete lines and preserves CRLF and surrogate pairs', () {
    for (final separator in ['\n', '\r\n', '😀']) {
      final body = '${'x' * 4095}$separator${'y' * 5000}';
      final ends = responseTextChunkEnds(body);
      expect(ends.first, separator == '\n' ? 4096 : 4095);
      expect(ends.last, body.length);
      for (final end in ends.where((end) => end < body.length)) {
        expect(
          body.codeUnitAt(end - 1),
          isNot(inInclusiveRange(0xD800, 0xDBFF)),
        );
        expect(body.substring(end - 1, end + 1), isNot('\r\n'));
      }
    }
  });

  test('empty text has no chunks; short text remains exact', () {
    expect(responseTextChunkEnds(''), isEmpty);
    expect(responseTextChunkEnds('a\nb\n'), [4]);
  });
}
