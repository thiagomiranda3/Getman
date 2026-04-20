import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  const fallback = Colors.grey;
  const palette = AppPalette(
    methodColors: {
      'GET': Color(0xFF4ADE80),
      'POST': Color(0xFF60A5FA),
    },
    methodFallback: fallback,
    statusSuccess: Colors.green,
    statusWarning: Colors.orange,
    statusError: Colors.red,
    statusAccentSuccess: Colors.greenAccent,
    statusAccentWarning: Colors.orangeAccent,
    statusAccentError: Colors.redAccent,
    codeBackground: Color(0xFF111111),
    mutedHover: Color(0x1A000000),
  );

  group('AppPalette', () {
    test('methodColor returns map entry for known methods (case-insensitive)', () {
      expect(palette.methodColor('GET'), const Color(0xFF4ADE80));
      expect(palette.methodColor('get'), const Color(0xFF4ADE80));
      expect(palette.methodColor('POST'), const Color(0xFF60A5FA));
    });

    test('methodColor returns fallback for unknown methods', () {
      expect(palette.methodColor('OPTIONS'), fallback);
    });

    test('statusColor maps 2xx/3xx/4xx+ to success/warning/error', () {
      expect(palette.statusColor(204), Colors.green);
      expect(palette.statusColor(301), Colors.orange);
      expect(palette.statusColor(404), Colors.red);
      expect(palette.statusColor(500), Colors.red);
    });

    test('statusAccent maps 2xx/3xx/4xx+ to accent variants', () {
      expect(palette.statusAccent(204), Colors.greenAccent);
      expect(palette.statusAccent(301), Colors.orangeAccent);
      expect(palette.statusAccent(404), Colors.redAccent);
    });

    test('copyWith preserves non-overridden fields', () {
      final copy = palette.copyWith(codeBackground: const Color(0xFF222222));
      expect(copy.codeBackground, const Color(0xFF222222));
      expect(copy.methodFallback, fallback);
      expect(copy.statusSuccess, Colors.green);
    });

    test('lerp interpolates colors and picks other.methodColors map', () {
      final other = palette.copyWith(
        methodColors: const {'GET': Color(0xFF000000)},
        statusSuccess: Colors.white,
      );
      final mid = palette.lerp(other, 1.0);
      expect(mid.methodColors['GET'], const Color(0xFF000000));
      expect(mid.statusSuccess, Colors.white);
    });
  });
}
