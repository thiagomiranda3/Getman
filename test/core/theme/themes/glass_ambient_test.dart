// test/core/theme/themes/glass_ambient_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Glass wallpaper renders child + pumps without throwing', (
    tester,
  ) async {
    final theme = resolveThemeData(
      kGlassThemeId,
      Brightness.dark,
      isCompact: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            return context.appDecoration.scaffoldBackground(
              context,
              child: const Text('bg'),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('bg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
