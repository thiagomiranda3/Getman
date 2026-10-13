import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/classic/classic_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/response/large_response_text_view.dart';

Future<void> _index(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find
        .byType(CircularProgressIndicator, skipOffstage: false)
        .evaluate()
        .isEmpty) {
      return;
    }
  }
  fail('The chunk index did not complete');
}

void main() {
  testWidgets(
    'select all copies the complete document beyond mounted chunks',
    (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final text = 'first\n${'x' * 11300000}\nlast marker';
      await tester.pumpWidget(
        MaterialApp(
          theme: classicTheme(Brightness.light),
          home: Scaffold(body: LargeResponseTextView(text: text)),
        ),
      );
      await _index(tester);
      final chunk = find.byKey(const ValueKey('large_response_chunk_0'));
      await tester.tap(chunk);
      await tester.pump();
      Actions.invoke(
        tester.element(chunk),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      Actions.invoke(tester.element(chunk), CopySelectionTextIntent.copy);
      await tester.pump();
      expect(copied?.length, text.length);
      expect(copied?.endsWith('last marker'), isTrue);
      expect(copied == text, isTrue);
      final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      final menu =
          area.contextMenuBuilder!(
                tester.element(find.byType(SelectionArea)),
                region,
              )
              as AdaptiveTextSelectionToolbar;
      copied = null;
      menu.buttonItems!
          .firstWhere((item) => item.type == ContextMenuButtonType.copy)
          .onPressed!();
      await tester.pump();
      expect(copied == text, isTrue);

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(2000);
      await tester.pump();
      final mountedChunk = find
          .descendant(
            of: find.byType(LargeResponseTextView),
            matching: find.byType(Text),
          )
          .first;
      copied = null;
      Actions.invoke(
        tester.element(mountedChunk),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();
      expect(copied == text, isTrue);

      // A real scrollbar gesture must keep select-all, unlike text selection.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(796, 20));
      await mouse.moveTo(const Offset(796, 25));
      await tester.pumpAndSettle();
      final beforeDrag = scrollable.position.pixels;
      await mouse.down(const Offset(796, 25));
      await mouse.moveBy(const Offset(0, 100));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(beforeDrag));
      copied = null;
      Actions.invoke(
        tester.element(mountedChunk),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();
      expect(copied == text, isTrue);
      await mouse.removePointer();

      // Starting a new ordinary selection must not retain the whole-body flag.
      await tester.tapAt(const Offset(60, 60));
      await tester.pump();
      copied = null;
      Actions.invoke(
        tester.element(mountedChunk),
        CopySelectionTextIntent.copy,
      );
      await tester.pump();
      expect(copied, isNot(text));

      scrollable.position.jumpTo(0);
      await tester.pump();
      await tester.tap(chunk);
      await tester.pump();
      Actions.invoke(
        tester.element(chunk),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      // Right-click inside select-all preserves the complete selection.
      await tester.tapAt(
        tester.getTopLeft(chunk) + const Offset(5, 5),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      copied = null;
      final copy = find.text('Copy');
      expect(copy.hitTestable(), findsOneWidget);
      await tester.tap(copy);
      await tester.pump();
      expect(copied == text, isTrue);

      // A new pointer selection restores native partial-copy semantics.
      await tester.tapAt(tester.getTopLeft(chunk) + const Offset(5, 5));
      await tester.pump();
      await tester.tapAt(
        tester.getTopLeft(chunk) + const Offset(5, 5),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      copied = null;
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, 'first');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'offstage response replacement shows the latest body on first frame',
    (
      tester,
    ) async {
      Widget page(String text, {bool offstage = false, double width = 400}) =>
          MaterialApp(
            theme: classicTheme(Brightness.light),
            home: Scaffold(
              body: Offstage(
                offstage: offstage,
                child: TickerMode(
                  enabled: !offstage,
                  child: SizedBox(
                    width: width,
                    child: LargeResponseTextView(text: text),
                  ),
                ),
              ),
            ),
          );

      final old = 'old${'x' * 11300000}';
      final next = 'latest${'y' * 11300000}';
      await tester.pumpWidget(page(old));
      await _index(tester);
      await tester.pumpWidget(page(old, offstage: true));
      await tester.pumpWidget(page(next, offstage: true));
      await _index(tester);
      await tester.pumpWidget(page(next, width: 240));
      final first = find.byKey(const ValueKey('large_response_chunk_0'));
      expect(first.hitTestable(at: Alignment.topLeft), findsOneWidget);
      expect(tester.widget<Text>(first).data, startsWith('latest'));
      final visibleChunks = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(LargeResponseTextView),
              matching: find.byType(Text),
            ),
          )
          .toList();
      expect(visibleChunks.length, lessThan(10));
      expect(
        visibleChunks.every((chunk) => chunk.data!.length <= 4096),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('replacement during indexing and disposal discard stale work', (
    tester,
  ) async {
    Widget page(String text) => MaterialApp(
      theme: classicTheme(Brightness.light),
      home: Scaffold(body: LargeResponseTextView(text: text)),
    );
    await tester.pumpWidget(page('old${'x' * 11300000}'));
    await tester.pumpWidget(page('replacement'));
    await _index(tester);
    expect(find.text('replacement').hitTestable(), findsOneWidget);
    await tester.pumpWidget(page('discard${'x' * 11300000}'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
