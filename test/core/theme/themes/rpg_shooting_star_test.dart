import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/rpg/rpg_decorations.dart';

void main() {
  group('rpgShootingStarSegment', () {
    const origin = Offset(100, 50);
    const angle = math.pi / 6; // 30° below horizontal
    const travel = 600.0;
    const bodyLength = 80.0;

    ({Offset head, Offset tailStart}) at(double fraction) =>
        rpgShootingStarSegment(
          origin: origin,
          angle: angle,
          travel: travel,
          bodyLength: bodyLength,
          fraction: fraction,
        );

    test('head starts at the origin and travels the full path', () {
      expect((at(0).head - origin).distance, closeTo(0, 0.001));
      // By the end of the flight the head has moved the whole travel distance.
      expect((at(1).head - origin).distance, closeTo(travel, 0.001));
    });

    test('head advances monotonically — it is not a static line', () {
      double dist(double f) => (at(f).head - origin).distance;
      expect(dist(0.25), lessThan(dist(0.5)));
      expect(dist(0.5), lessThan(dist(0.75)));
    });

    test('the visible comet body stays far shorter than the travel', () {
      final body = (at(1).head - at(1).tailStart).distance;
      expect(body, closeTo(bodyLength, 0.001));
      expect(body, lessThan(travel / 3));
    });

    test('the tail is clamped to the origin while the head is still close', () {
      final seg = at(0.02); // headDist (12) < bodyLength (80)
      expect((seg.tailStart - origin).distance, closeTo(0, 0.001));
      expect(
        (seg.tailStart - origin).distance,
        lessThanOrEqualTo((seg.head - origin).distance + 0.001),
      );
    });

    test('fraction is clamped to 0..1', () {
      expect((at(-1).head - origin).distance, closeTo(0, 0.001));
      expect((at(5).head - origin).distance, closeTo(travel, 0.001));
    });
  });
}
