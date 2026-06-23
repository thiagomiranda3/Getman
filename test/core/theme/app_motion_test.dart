import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Some theme builders (e.g. glass) pull fonts via GoogleFonts; disable
    // runtime fetching so resolveThemeData works offline in tests.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Reads the AppMotion straight off each theme's ThemeData (not via a
  // BuildContext). pumpWidget reuses the element tree across iterations, so a
  // per-iteration ctx would stay pinned to the first theme and any hook
  // assertion through it would be vacuous — assert on theme.extension instead.
  testWidgets('every registered theme attaches an AppMotion extension', (
    tester,
  ) async {
    for (final id in appThemes.keys) {
      final theme = resolveThemeData(id, Brightness.light, isCompact: false);
      expect(
        theme.extension<AppMotion>(),
        isNotNull,
        reason: 'theme "$id" must attach an AppMotion extension',
      );
    }
  });
}
