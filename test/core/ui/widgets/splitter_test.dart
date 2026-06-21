import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/splitter.dart';

void main() {
  Future<void> pumpSplitter(
    WidgetTester tester, {
    required bool isVertical,
    required ValueChanged<double> onUpdate,
    VoidCallback? onEnd,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: Splitter(
                isVertical: isVertical,
                onUpdate: onUpdate,
                onEnd: onEnd,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('horizontal: onUpdate fires with non-zero dx on drag', (
    tester,
  ) async {
    final deltas = <double>[];
    await pumpSplitter(
      tester,
      isVertical: false,
      onUpdate: deltas.add,
    );

    await tester.drag(find.byType(Splitter), const Offset(20, 0));
    await tester.pump();

    expect(deltas, isNotEmpty);
    expect(deltas.any((d) => d != 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical: onUpdate fires with non-zero dy on drag', (
    tester,
  ) async {
    final deltas = <double>[];
    await pumpSplitter(
      tester,
      isVertical: true,
      onUpdate: deltas.add,
    );

    await tester.drag(find.byType(Splitter), const Offset(0, 20));
    await tester.pump();

    expect(deltas, isNotEmpty);
    expect(deltas.any((d) => d != 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onEnd fires when drag ends', (tester) async {
    var endCount = 0;
    await pumpSplitter(
      tester,
      isVertical: false,
      onUpdate: (_) {},
      onEnd: () => endCount++,
    );

    await tester.drag(find.byType(Splitter), const Offset(15, 0));
    await tester.pump();

    expect(endCount, 1);
  });

  testWidgets('lays out without overflow in horizontal configuration', (
    tester,
  ) async {
    await pumpSplitter(
      tester,
      isVertical: false,
      onUpdate: (_) {},
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Splitter), findsOneWidget);
  });

  testWidgets('lays out without overflow in vertical configuration', (
    tester,
  ) async {
    await pumpSplitter(
      tester,
      isVertical: true,
      onUpdate: (_) {},
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Splitter), findsOneWidget);
  });
}
