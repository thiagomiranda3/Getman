import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/hover_highlight.dart';

void main() {
  const hoveredColor = Color(0xFFFF0000);
  const idleColor = Color(0xFF0000FF);

  // HoverHighlight.decoration is positional-bool by design (see source ignore).
  // ignore: avoid_positional_boolean_parameters
  BoxDecoration testDecoration(bool hovered) =>
      BoxDecoration(color: hovered ? hoveredColor : idleColor);

  Future<void> pumpHighlight(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: HoverHighlight(
              decoration: testDecoration,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows idle decoration before hover', (tester) async {
    await pumpHighlight(tester);

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final containerDecoration = container.decoration! as BoxDecoration;
    expect(containerDecoration.color, idleColor);
  });

  testWidgets('shows hovered decoration on mouse enter, clears on exit', (
    tester,
  ) async {
    await pumpHighlight(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    // Move pointer over the widget.
    await gesture.moveTo(tester.getCenter(find.byType(HoverHighlight)));
    await tester.pump();

    final hoveredContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(
      (hoveredContainer.decoration! as BoxDecoration).color,
      hoveredColor,
    );

    // Move pointer away.
    await gesture.moveTo(const Offset(500, 500));
    await tester.pump();

    final idleContainer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(
      (idleContainer.decoration! as BoxDecoration).color,
      idleColor,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses provided duration on the AnimatedContainer', (
    tester,
  ) async {
    const customDuration = Duration(milliseconds: 350);
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: HoverHighlight(
              decoration: testDecoration,
              duration: customDuration,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(container.duration, customDuration);
    expect(tester.takeException(), isNull);
  });
}
