import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  testWidgets('every theme attaches an AppMotion; defaults are identity', (
    tester,
  ) async {
    for (final id in appThemes.keys) {
      final theme = resolveThemeData(id, Brightness.light, isCompact: false);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final motion = ctx.appMotion;
      // Identity sendAffordance returns the child unchanged.
      const marker = SizedBox(key: ValueKey('marker'));
      expect(
        identical(
          motion.sendAffordance(ctx, child: marker, isSending: false),
          marker,
        ),
        isTrue,
        reason: 'theme "$id" sendAffordance must default to identity',
      );
    }
  });
}
