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

    test('resolveTheme returns default builder for null', () {
      expect(resolveTheme(null), appThemes[defaultThemeId]!.builder);
    });

    test('resolveTheme returns default builder for unknown id', () {
      expect(resolveTheme('does-not-exist'), appThemes[defaultThemeId]!.builder);
    });

    test('resolveTheme returns registered builder for known id', () {
      expect(resolveTheme(kBrutalistThemeId), appThemes[kBrutalistThemeId]!.builder);
    });

    test('every descriptor has a non-empty display name matching its id', () {
      for (final entry in appThemes.entries) {
        expect(entry.value.id, entry.key);
        expect(entry.value.displayName, isNotEmpty);
      }
    });

    // testWidgets absorbs the asynchronous google_fonts font-not-found error
    // that fires after assertions pass when fonts are missing from test assets.
    testWidgets('registered builder returns a usable ThemeData', (tester) async {
      final theme = resolveTheme(kBrutalistThemeId)(Brightness.light, isCompact: false);
      expect(theme, isA<ThemeData>());
    });
  });
}
