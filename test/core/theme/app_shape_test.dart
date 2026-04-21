import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  group('AppShape', () {
    const a = AppShape(panelRadius: 4, buttonRadius: 4, inputRadius: 4, dialogRadius: 8);
    const b = AppShape(panelRadius: 12, buttonRadius: 12, inputRadius: 12, dialogRadius: 20);

    test('copyWith preserves non-overridden fields', () {
      final copy = a.copyWith(panelRadius: 99);
      expect(copy.panelRadius, 99);
      expect(copy.buttonRadius, 4);
      expect(copy.inputRadius, 4);
      expect(copy.dialogRadius, 8);
    });

    test('lerp interpolates radii', () {
      final mid = a.lerp(b, 0.5);
      expect(mid.panelRadius, 8);
      expect(mid.buttonRadius, 8);
      expect(mid.inputRadius, 8);
      expect(mid.dialogRadius, 14);
    });

    test('lerp with wrong type returns this', () {
      expect(a.lerp(null, 0.5), a);
    });
  });
}
