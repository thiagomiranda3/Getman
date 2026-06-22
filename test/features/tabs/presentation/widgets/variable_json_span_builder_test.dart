import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_json_span_builder.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('colors a {{var}} token inside a JSON string', (tester) async {
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = variableAwareJsonSpan(
              context: context,
              index: 0,
              codeLine: const CodeLine('{"url": "{{host}}/v1"}'),
              textSpan: const TextSpan(text: '{"url": "{{host}}/v1"}'),
              style: const TextStyle(color: Colors.black),
              variables: const {'host': 'example.com'},
              resolvedColor: const Color(0xFF00FF00),
              unresolvedColor: const Color(0xFFFF0000),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    final resolvedRun = _findRun(span, '{{host}}');
    expect(resolvedRun, isNotNull);
    expect(resolvedRun?.style?.color, const Color(0xFF00FF00));
    expect(resolvedRun?.style?.fontWeight, FontWeight.w800);
  });

  testWidgets(
    'a JSON line with no variables is unchanged vs base highlighter',
    (
      tester,
    ) async {
      const line = '{"name": "getman", "version": 1}';
      late String baseText;
      late String overlaidText;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final base = jsonHighlightSpanBuilder(
                context: context,
                index: 0,
                codeLine: const CodeLine(line),
                textSpan: const TextSpan(text: line),
                style: const TextStyle(color: Colors.black),
              );
              final overlaid = variableAwareJsonSpan(
                context: context,
                index: 0,
                codeLine: const CodeLine(line),
                textSpan: const TextSpan(text: line),
                style: const TextStyle(color: Colors.black),
                variables: const {'host': 'example.com'},
                resolvedColor: const Color(0xFF00FF00),
                unresolvedColor: const Color(0xFFFF0000),
              );
              baseText = base.toPlainText();
              overlaidText = overlaid.toPlainText();
              return const SizedBox();
            },
          ),
        ),
      );

      expect(overlaidText, baseText);
      expect(overlaidText, line);
    },
  );

  testWidgets(
    'span plain-text fidelity: variable line preserves every character',
    (tester) async {
      const line = '{"url": "{{host}}/v1"}';
      late String spanText;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final span = variableAwareJsonSpan(
                context: context,
                index: 0,
                codeLine: const CodeLine(line),
                textSpan: const TextSpan(text: line),
                style: const TextStyle(color: Colors.black),
                variables: const {'host': 'example.com'},
                resolvedColor: const Color(0xFF00FF00),
                unresolvedColor: const Color(0xFFFF0000),
              );
              spanText = span.toPlainText();
              return const SizedBox();
            },
          ),
        ),
      );

      // The flat-run merge must not drop or duplicate any characters.
      expect(spanText, line);
    },
  );

  testWidgets('unknown variable uses the unresolved color', (tester) async {
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = variableAwareJsonSpan(
              context: context,
              index: 0,
              codeLine: const CodeLine('{"x": "{{nope}}"}'),
              textSpan: const TextSpan(text: '{"x": "{{nope}}"}'),
              style: const TextStyle(color: Colors.black),
              variables: const {},
              resolvedColor: const Color(0xFF00FF00),
              unresolvedColor: const Color(0xFFFF0000),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    final run = _findRun(span, '{{nope}}');
    expect(run, isNotNull);
    expect(run?.style?.color, const Color(0xFFFF0000));
  });
}

/// Depth-first search the span tree for the child whose text == [needle].
TextSpan? _findRun(InlineSpan span, String needle) {
  if (span is TextSpan) {
    if (span.text == needle) return span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _findRun(child, needle);
      if (found != null) return found;
    }
  }
  return null;
}
