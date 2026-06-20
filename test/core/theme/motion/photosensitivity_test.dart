import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/photosensitivity.dart';

void main() {
  test('caps at 3 flashes per second', () {
    expect(kMaxSafeFlashesPerSecond, 3);
  });

  group('safeFlashCount', () {
    test('clamps an over-rate count down to the budget', () {
      // 700ms window allows floor(700*3/1000) = 2 flashes.
      expect(safeFlashCount(const Duration(milliseconds: 700), 3), 2);
    });
    test('passes an in-budget count through', () {
      // 1000ms allows 3.
      expect(safeFlashCount(const Duration(seconds: 1), 3), 3);
    });
    test('never returns less than 1', () {
      expect(safeFlashCount(const Duration(milliseconds: 100), 5), 1);
    });
  });
}
