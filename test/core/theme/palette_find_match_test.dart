import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Disable network font fetching in tests to prevent async errors after
    // tests complete; fonts fall back to system defaults.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // testWidgets absorbs the asynchronous google_fonts font-not-found error
  // that fires after assertions pass when fonts are missing from test assets.
  testWidgets(
    'every registered theme ships find-match highlight colors, with the '
    'active match more opaque than a normal match (both brightnesses)',
    (tester) async {
      for (final entry in appThemes.entries) {
        for (final b in Brightness.values) {
          final data = entry.value.builder(b);
          final palette = data.extension<AppPalette>();
          expect(
            palette,
            isNotNull,
            reason: '${entry.key} ($b) is missing AppPalette',
          );
          expect(
            palette!.findMatchHighlight.a,
            greaterThan(0),
            reason: '${entry.key} ($b): findMatchHighlight is invisible',
          );
          expect(
            palette.findMatchActiveHighlight.a,
            greaterThan(palette.findMatchHighlight.a),
            reason:
                '${entry.key} ($b): the current match must be more opaque '
                'than a normal match',
          );
        }
      }
    },
  );
}
