// Tests for HoverCopyRow: the copy icon must stay hidden until mouse hover,
// tapping it must copy `value` to the clipboard and show the 'Value copied'
// snackbar, and the icon must hide again once the pointer leaves.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/hover_copy_row.dart';

void main() {
  late List<String> clips;

  Future<void> pump(WidgetTester tester) async {
    clips = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clips.add((call.arguments as Map)['text'] as String);
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
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme(kClassicThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: const Scaffold(
          body: HoverCopyRow(
            value: 'copy-me',
            child: ListTile(title: Text('KEY'), subtitle: Text('copy-me')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('copy icon hidden until hover', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('row_copy_value_button')), findsNothing);
  });

  testWidgets('hover reveals icon; tap copies value + snackbar', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(HoverCopyRow)));
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('row_copy_value_button'));
    expect(button, findsOneWidget);
    expect(tester.widget<IconButton>(button).tooltip, 'Copy value');

    await tester.tap(button);
    await tester.pump();
    expect(clips, ['copy-me']);
    expect(find.text('Value copied'), findsOneWidget);
    // Flush the snackbar timer so the test ends with no pending timers.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('icon hides again when the pointer leaves', (tester) async {
    await pump(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(HoverCopyRow)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('row_copy_value_button')),
      findsOneWidget,
    );

    // Move well outside the row's bounds — the Scaffold has no AppBar, so
    // the row's rect starts at Offset.zero itself; moving back to
    // Offset.zero would still be inside it (rect containment is inclusive
    // on the top-left edge) and onExit would never fire. Same convention as
    // hover_highlight_test.dart.
    await gesture.moveTo(const Offset(500, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row_copy_value_button')), findsNothing);
  });
}
