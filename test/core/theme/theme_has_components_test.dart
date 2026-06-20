import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
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
    'every registered theme attaches AppComponents (both brightnesses)',
    (tester) async {
      for (final entry in appThemes.entries) {
        for (final b in Brightness.values) {
          final data = entry.value.builder(b);
          expect(
            data.extension<AppComponents>(),
            isNotNull,
            reason: '${entry.key} ($b) is missing AppComponents',
          );
        }
      }
    },
  );
}
