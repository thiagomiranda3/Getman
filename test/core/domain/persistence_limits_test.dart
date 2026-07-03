import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/persistence_limits.dart';

void main() {
  group('canHighlightBody', () {
    test('allows up to and including the cap', () {
      expect(canHighlightBody(0), isTrue);
      expect(canHighlightBody(kMaxHighlightChars), isTrue);
    });

    test('rejects beyond the cap', () {
      expect(canHighlightBody(kMaxHighlightChars + 1), isFalse);
    });
  });
}
