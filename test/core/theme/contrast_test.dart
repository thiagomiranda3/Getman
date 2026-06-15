import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';

/// WCAG relative-luminance contrast ratio between two colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = max(la, lb);
  final lo = min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// onColor always picks the higher-contrast of black/white, which is provably
// >= ~4.58:1 for any background — comfortably past WCAG AA for normal text.
const double _minRatio = 4.5;

void main() {
  // Building a theme pulls Google Fonts, which needs an initialized binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final descriptor in appThemes.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final palette = resolveThemeData(
        descriptor.id,
        brightness,
        isCompact: false,
      ).extension<AppPalette>()!;

      group('${descriptor.id} (${brightness.name}) on-color contrast', () {
        palette.methodColors.forEach((method, color) {
          test('method "$method" text is legible', () {
            expect(
              _contrast(color, palette.onColor(color)),
              greaterThanOrEqualTo(_minRatio),
            );
          });
        });

        for (final code in [204, 301, 404]) {
          test('status $code text is legible', () {
            final bg = palette.statusColor(code);
            expect(
              _contrast(bg, palette.onColor(bg)),
              greaterThanOrEqualTo(_minRatio),
            );
          });
        }
      });
    }
  }
}
