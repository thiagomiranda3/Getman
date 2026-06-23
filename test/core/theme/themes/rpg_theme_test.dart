import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/rpg/rpg_decorations.dart';
import 'package:getman/core/theme/themes/rpg/rpg_theme.dart';
import 'package:getman/core/theme/themes/shared/subtle_press.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('rpgTheme reduceEffects', () {
    testWidgets('full effects: animated background + SubtlePress animated', (
      tester,
    ) async {
      final d = rpgTheme(Brightness.dark).extension<AppDecoration>()!;
      expect(identical(d.scaffoldBackground, rpgScaffoldBackground), isTrue);
      final w = d.wrapInteractive(child: const SizedBox()) as SubtlePress;
      expect(w.animate, isTrue);
    });

    testWidgets(
      'reduced effects: static background + SubtlePress not animated',
      (
        tester,
      ) async {
        final d = rpgTheme(
          Brightness.dark,
          reduceEffects: true,
        ).extension<AppDecoration>()!;
        expect(
          identical(d.scaffoldBackground, rpgStaticScaffoldBackground),
          isTrue,
        );
        final w = d.wrapInteractive(child: const SizedBox()) as SubtlePress;
        expect(w.animate, isFalse);
      },
    );
  });
}
