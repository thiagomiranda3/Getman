// Tests for TabStripDoubleClickDetector: a double primary-click on the tab
// strip's EMPTY area fires onNewTab (Postman parity), while clicks landing on
// a chip (TabChipHitTarget), slow click pairs, and non-primary buttons never
// do. Raw TestPointer events with explicit timeStamps drive the detector's
// own double-click timing (kDoubleTapTimeout).

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/home/presentation/widgets/tab_strip_double_click.dart';

void main() {
  late int newTabCount;

  Future<void> pumpStrip(WidgetTester tester) async {
    newTabCount = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 40,
            child: TabStripDoubleClickDetector(
              onNewTab: () => newTabCount++,
              // Fills the strip so the empty area is hit-testable, like the
              // real strip's opaque scrollable.
              child: const ColoredBox(
                color: Color(0xFFEEEEEE),
                child: Row(
                  children: [
                    TabChipHitTarget(
                      child: SizedBox(
                        key: ValueKey('chip'),
                        width: 100,
                        height: 40,
                        child: ColoredBox(color: Color(0xFF333333)),
                      ),
                    ),
                    Expanded(child: SizedBox(height: 40)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A click (down+up) at [position], with explicit timestamps so the test
  /// controls the double-click window.
  Future<void> click(
    WidgetTester tester,
    TestPointer pointer,
    Offset position,
    Duration at,
  ) async {
    await tester.sendEventToBinding(pointer.down(position, timeStamp: at));
    await tester.sendEventToBinding(
      pointer.up(timeStamp: at + const Duration(milliseconds: 20)),
    );
  }

  Offset emptyArea(WidgetTester tester) =>
      tester.getRect(find.byType(TabStripDoubleClickDetector)).centerRight -
      const Offset(50, 0);

  testWidgets('double-click on the empty strip area fires onNewTab once', (
    tester,
  ) async {
    await pumpStrip(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final target = emptyArea(tester);

    await click(tester, pointer, target, const Duration(milliseconds: 100));
    expect(newTabCount, 0, reason: 'a single click must not open a tab');

    await click(tester, pointer, target, const Duration(milliseconds: 250));
    expect(newTabCount, 1);
  });

  testWidgets('a triple-click opens only one tab (the pair is consumed)', (
    tester,
  ) async {
    await pumpStrip(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final target = emptyArea(tester);

    await click(tester, pointer, target, const Duration(milliseconds: 100));
    await click(tester, pointer, target, const Duration(milliseconds: 250));
    await click(tester, pointer, target, const Duration(milliseconds: 400));

    expect(newTabCount, 1);
  });

  testWidgets('double-click on a tab chip does NOT open a new tab', (
    tester,
  ) async {
    await pumpStrip(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final chip = tester.getCenter(find.byKey(const ValueKey('chip')));

    await click(tester, pointer, chip, const Duration(milliseconds: 100));
    await click(tester, pointer, chip, const Duration(milliseconds: 250));

    expect(newTabCount, 0);
  });

  testWidgets('chip click then empty-area click is not a double-click', (
    tester,
  ) async {
    await pumpStrip(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await click(
      tester,
      pointer,
      tester.getCenter(find.byKey(const ValueKey('chip'))),
      const Duration(milliseconds: 100),
    );
    await click(
      tester,
      pointer,
      emptyArea(tester),
      const Duration(milliseconds: 250),
    );

    expect(newTabCount, 0);
  });

  testWidgets('two clicks slower than the double-click window do nothing', (
    tester,
  ) async {
    await pumpStrip(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final target = emptyArea(tester);

    await click(tester, pointer, target, const Duration(milliseconds: 100));
    // Beyond kDoubleTapTimeout (300ms) after the first down.
    await click(tester, pointer, target, const Duration(milliseconds: 600));

    expect(newTabCount, 0);
  });

  testWidgets('a secondary-button double-click does nothing', (tester) async {
    await pumpStrip(tester);
    final pointer = TestPointer(
      1,
      PointerDeviceKind.mouse,
      null,
      kSecondaryMouseButton,
    );
    final target = emptyArea(tester);

    await click(tester, pointer, target, const Duration(milliseconds: 100));
    await click(tester, pointer, target, const Duration(milliseconds: 250));

    expect(newTabCount, 0);
  });

  testWidgets('two far-apart clicks within the time window do nothing', (
    tester,
  ) async {
    await pumpStrip(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final rect = tester.getRect(find.byType(TabStripDoubleClickDetector));
    // Both on empty strip, but farther apart than kDoubleTapSlop (100px).
    final first = rect.centerLeft + const Offset(120, 0);
    final second = rect.centerRight - const Offset(20, 0);
    expect((second - first).distance, greaterThan(kDoubleTapSlop));

    await click(tester, pointer, first, const Duration(milliseconds: 100));
    await click(tester, pointer, second, const Duration(milliseconds: 250));

    expect(newTabCount, 0);
  });
}
