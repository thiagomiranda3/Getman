import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  group('AppTypography', () {
    const a = AppTypography(
      base: TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      codeFontFamily: 'JetBrainsMono',
      displayWeight: FontWeight.w900,
      titleWeight: FontWeight.w700,
      bodyWeight: FontWeight.w500,
    );

    test('copyWith preserves non-overridden fields', () {
      final copy = a.copyWith(codeFontFamily: 'FiraCode');
      expect(copy.codeFontFamily, 'FiraCode');
      expect(copy.displayWeight, FontWeight.w900);
      expect(copy.base.bodyMedium?.fontSize, 14);
    });

    test('lerp returns a typography with other.codeFontFamily', () {
      final b = a.copyWith(codeFontFamily: 'Monaco');
      final mid = a.lerp(b, 1.0);
      expect(mid.codeFontFamily, 'Monaco');
    });

    test('lerp with wrong type returns this', () {
      expect(a.lerp(null, 0.5), a);
    });
  });
}
