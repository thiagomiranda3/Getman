import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/latency_weight.dart';

void main() {
  group('latencyWeight', () {
    test('null => 0', () => expect(latencyWeight(null), 0));
    test('0 => 0', () => expect(latencyWeight(0), 0));
    test('fast (<=150ms) => 0', () => expect(latencyWeight(150), 0));
    test('slow (>=3000ms) => 1', () => expect(latencyWeight(3000), 1));
    test('very slow clamps to 1', () => expect(latencyWeight(10000), 1));
    test('always within [0,1]', () {
      for (final ms in [50, 200, 500, 1000, 2000, 2999]) {
        final w = latencyWeight(ms);
        expect(w, inInclusiveRange(0.0, 1.0), reason: 'ms=$ms');
      }
    });
    test('monotonic non-decreasing', () {
      var prev = -1.0;
      for (final ms in [150, 300, 600, 1200, 2400, 3000]) {
        final w = latencyWeight(ms);
        expect(w, greaterThanOrEqualTo(prev), reason: 'ms=$ms');
        prev = w;
      }
    });
  });

  group('inFlightTension', () {
    test('0 => 0', () => expect(inFlightTension(0), 0));
    test('full at 3000ms', () => expect(inFlightTension(3000), 1));
    test('beyond full clamps to 1', () => expect(inFlightTension(9000), 1));
    test('mid is between 0 and 1', () {
      final t = inFlightTension(1500);
      expect(t, greaterThan(0.0));
      expect(t, lessThan(1.0));
    });
  });
}
