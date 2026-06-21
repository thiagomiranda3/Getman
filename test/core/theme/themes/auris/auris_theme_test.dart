import 'package:auris/auris.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/extensions/app_palette.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Disable network font fetching in tests to prevent async errors after
    // tests complete; fonts fall back to system defaults.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test(
    'AURIS is registered with display name AURIS and is not the default',
    () {
      expect(appThemes[kAurisThemeId]?.displayName, 'AURIS');
      expect(defaultThemeId, isNot(kAurisThemeId));
    },
  );

  // testWidgets absorbs the asynchronous google_fonts font-not-found error
  // that fires after assertions pass when fonts are missing from test assets.
  testWidgets(
    'aurisTheme builds for all flag combos and attaches required extensions',
    (tester) async {
      for (final b in Brightness.values) {
        for (final compact in [false, true]) {
          for (final reduce in [false, true]) {
            final tag = '$b c=$compact r=$reduce';
            final data = appThemes[kAurisThemeId]!.builder(
              b,
              isCompact: compact,
              reduceEffects: reduce,
            );
            expect(
              data.extension<AppLayout>(),
              isNotNull,
              reason: 'AURIS ($tag) missing AppLayout',
            );
            expect(
              data.extension<AppPalette>(),
              isNotNull,
              reason: 'AURIS ($tag) missing AppPalette',
            );
            expect(
              data.extension<AppMotion>(),
              isNotNull,
              reason: 'AURIS ($tag) missing AppMotion',
            );
            expect(
              data.extension<AppComponents>(),
              isNotNull,
              reason: 'AURIS ($tag) missing AppComponents',
            );
            // Critical: AurisScheme MUST survive the copyWith so auris
            // widgets don't throw when force-unwrapping it.
            expect(
              data.extension<AurisScheme>(),
              isNotNull,
              reason:
                  'AURIS ($tag) missing AurisScheme — '
                  'spread ...base.extensions.values in copyWith',
            );
          }
        }
      }
    },
  );
}
