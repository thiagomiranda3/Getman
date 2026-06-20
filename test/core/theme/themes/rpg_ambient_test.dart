import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'RPG animated background renders child + pumps without throwing',
    (tester) async {
      final theme = resolveThemeData(
        kRpgThemeId,
        Brightness.dark,
        isCompact: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => context.appDecoration.scaffoldBackground(
              context,
              child: const Text('bg'),
            ),
          ),
        ),
      );
      // Pump a few animation frames; the ambient painter must not throw.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('bg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
