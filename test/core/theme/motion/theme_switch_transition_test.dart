// test/core/theme/motion/theme_switch_transition_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/motion/theme_switch_transition.dart';

void main() {
  testWidgets('plays an overlay on themeId change, then settles', (
    tester,
  ) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ThemeSwitchTransition(
              themeId: id,
              reduceEffects: false,
              child: const Text('content', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );
    expect(find.text('content'), findsOneWidget);

    setOuter(() => id = 'b');
    await tester.pump(); // start transition
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // finish
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('reduced effects: no overlay on change', (tester) async {
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return ThemeSwitchTransition(
              themeId: id,
              reduceEffects: true,
              child: const Text('content', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),
    );
    setOuter(() => id = 'b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('theme_switch_overlay')), findsNothing);
  });
}
