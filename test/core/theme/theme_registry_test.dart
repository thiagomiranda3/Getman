import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Disable network font fetching in tests to prevent async errors after
    // tests complete; fonts fall back to system defaults.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('theme_registry', () {
    test('appThemes contains the default entry', () {
      expect(appThemes[defaultThemeId], isNotNull);
    });

    test('resolveTheme returns default for null', () {
      final builder = resolveTheme(null);
      expect(builder, appThemes[defaultThemeId]);
    });

    test('resolveTheme returns default for unknown id', () {
      final builder = resolveTheme('does-not-exist');
      expect(builder, appThemes[defaultThemeId]);
    });

    test('resolveTheme returns registered builder for known id', () {
      final builder = resolveTheme(kBrutalistThemeId);
      expect(builder, appThemes[kBrutalistThemeId]);
    });

    // testWidgets absorbs the asynchronous google_fonts font-not-found error
    // that fires after assertions pass when fonts are missing from test assets.
    testWidgets('registered builder returns a usable ThemeData', (tester) async {
      final theme = resolveTheme(kBrutalistThemeId)(Brightness.light, isCompact: false);
      expect(theme, isA<ThemeData>());
    });
  });
}
