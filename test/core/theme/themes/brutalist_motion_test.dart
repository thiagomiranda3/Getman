// test/core/theme/themes/brutalist_motion_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_reaction.dart';
import 'package:getman/core/theme/motion/theme_reaction_controller.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_motion.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('stamp on success shows the status code text', (tester) async {
    final motion = brutalistMotion(reduceEffects: false);
    final controller = ThemeReactionController();
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: motion.reactionOverlay(
                context,
                controller: controller,
                child: const Text('app'),
              ),
            );
          },
        ),
      ),
    );
    controller.fire(
      const ThemeReaction(kind: ThemeReactionKind.success, statusCode: 200),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('200'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
  });

  test('reduced effects => identity', () {
    final motion = brutalistMotion(reduceEffects: true);
    expect(motion.runtimeType.toString(), 'AppMotion');
  });
}
