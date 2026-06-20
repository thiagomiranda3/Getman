import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  testWidgets('reactionOverlay identity passes child through', (tester) async {
    final controller = ThemeReactionController();
    final theme = resolveThemeData(
      'classic',
      Brightness.light,
      isCompact: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            return context.appMotion.reactionOverlay(
              context,
              controller: controller,
              child: const Text('content'),
            );
          },
        ),
      ),
    );
    expect(find.text('content'), findsOneWidget);
    controller.dispose();
  });
}
