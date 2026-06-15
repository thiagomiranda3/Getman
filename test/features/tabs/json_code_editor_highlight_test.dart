import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

/// Regression: JSON token colouring must reach the paint path.
///
/// re_editor's built-in (isolate-based) highlighter delivered no coloured
/// spans in this app, so the body rendered in a single colour. The fix colours
/// each line synchronously via the controller's `spanBuilder`. Because that is
/// synchronous, the colours are present on the first paint — no isolate, no
/// real-async pump needed (which is also why this is reliably testable).
void main() {
  Set<int?> collectColors(List<TextSpan> spans) {
    final colors = <int?>{};
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        colors.add(s.style?.color?.toARGB32());
        (s.children ?? const <InlineSpan>[]).forEach(walk);
      }
    }

    spans.forEach(walk);
    return colors;
  }

  testWidgets('JsonCodeEditor paints more than one colour for JSON', (
    tester,
  ) async {
    final captured = <TextSpan>[];
    final controller = createJsonCodeController();
    // Decorate the real highlighting span builder so we can observe what the
    // editor actually hands to the paint path.
    final controllerWithCapture = CodeLineEditingController(
      spanBuilder:
          ({
            required context,
            required index,
            required codeLine,
            required textSpan,
            required style,
          }) {
            final span = jsonHighlightSpanBuilder(
              context: context,
              index: index,
              codeLine: codeLine,
              textSpan: textSpan,
              style: style,
            );
            captured.add(span);
            return span;
          },
    );
    controller.dispose();
    controllerWithCapture.text =
        '{\n  "name": "getman",\n  "count": 42,\n  "ok": true\n}';

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData('brutalist', Brightness.dark, isCompact: false),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: JsonCodeEditor(
              controller: controllerWithCapture,
              readOnly: true,
              autofocus: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final colors = collectColors(captured);
    expect(
      captured,
      isNotEmpty,
      reason: 'editor should have built spans for the visible lines',
    );
    expect(
      colors.length,
      greaterThan(1),
      reason: 'JSON keys/strings/numbers must render in distinct colours',
    );

    // Dispose the editor so its cursor-blink timer is cancelled before the
    // test ends (re_editor autofocuses and starts a periodic blink timer).
    await tester.pumpWidget(const SizedBox());
    controllerWithCapture.dispose();
  });

  testWidgets('JsonCodeEditor renders a fold (collapse/expand) gutter', (
    tester,
  ) async {
    // Wiring check: the gutter must include re_editor's chunk indicator so
    // object/array regions get clickable fold chevrons. The fold engine itself
    // runs in a re_editor isolate (not deterministic here); the structural
    // presence of the indicator is what this guards against regressing.
    const json = '{\n  "a": {\n    "b": 1\n  }\n}';
    final controller = createJsonCodeController()..text = json;

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData('brutalist', Brightness.dark, isCompact: false),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: JsonCodeEditor(
              controller: controller,
              readOnly: true,
              autofocus: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DefaultCodeChunkIndicator), findsOneWidget);
    expect(find.byType(DefaultCodeLineNumber), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('non-JSON content does not throw and still renders', (
    tester,
  ) async {
    final captured = <TextSpan>[];
    final controller = CodeLineEditingController(
      spanBuilder:
          ({
            required context,
            required index,
            required codeLine,
            required textSpan,
            required style,
          }) {
            final span = jsonHighlightSpanBuilder(
              context: context,
              index: index,
              codeLine: codeLine,
              textSpan: textSpan,
              style: style,
            );
            captured.add(span);
            return span;
          },
    )..text = '<html>\n  <body>not json</body>\n</html>';

    await tester.pumpWidget(
      MaterialApp(
        theme: resolveThemeData(
          'brutalist',
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: JsonCodeEditor(
              controller: controller,
              readOnly: true,
              autofocus: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(captured, isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
