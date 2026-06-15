import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';

void main() {
  TextSpan buildSpan(VariableHighlightController c) => c.buildTextSpan(
    context: _FakeBuildContext(),
    style: const TextStyle(),
    withComposing: false,
  );

  int leafCount(InlineSpan span) {
    var n = 0;
    span.visitChildren((child) {
      if (child is TextSpan &&
          (child.children == null || child.children!.isEmpty)) {
        n++;
      }
      return true;
    });
    return n;
  }

  group('VariableHighlightController', () {
    test('highlights {{var}} tokens once colors are pushed', () {
      final c =
          VariableHighlightController(
            text: 'https://{{host}}/api',
            variables: {'host': 'example.com'},
          )..updateColors(
            resolved: const Color(0xFF00FF00),
            unresolved: const Color(0xFFFF0000),
          );

      final span = buildSpan(c);
      // base + token + tail = 3 leaf spans
      expect(leafCount(span), 3);
    });

    test(
      'reuses the cached match list across repaints with unchanged text',
      () {
        final c = VariableHighlightController(text: 'a {{x}} b')
          ..updateColors(
            resolved: const Color(0xFF00FF00),
            unresolved: const Color(0xFFFF0000),
          );

        final first = buildSpan(c);
        final second = buildSpan(c);
        // Structurally identical across repaints (no recompute side effects).
        expect(leafCount(first), leafCount(second));
        expect(leafCount(second), 3);
      },
    );

    test('recomputes when the text changes', () {
      final c = VariableHighlightController(text: 'no tokens here')
        ..updateColors(
          resolved: const Color(0xFF00FF00),
          unresolved: const Color(0xFFFF0000),
        );
      expect(leafCount(buildSpan(c)), 1); // whole string, no tokens

      c.text = 'now {{a}} and {{b}}';
      // "now " + {{a}} + " and " + {{b}} = 4 leaf spans
      // (ends on a token, no tail)
      expect(leafCount(buildSpan(c)), 4);
    });

    test(
      'toggling a variable to resolved keeps token boundaries, flips color',
      () {
        const resolved = Color(0xFF00FF00);
        const unresolved = Color(0xFFFF0000);
        final c = VariableHighlightController(text: '{{token}}')
          ..updateColors(resolved: resolved, unresolved: unresolved);

        Color? tokenColor(InlineSpan span) {
          Color? found;
          span.visitChildren((child) {
            if (child is TextSpan && child.text == '{{token}}') {
              found = child.style?.color;
            }
            return true;
          });
          return found;
        }

        expect(tokenColor(buildSpan(c)), unresolved);
        c.updateVariables({'token': 'v'});
        expect(tokenColor(buildSpan(c)), resolved);
      },
    );

    test('updateVariables with an equal map does not notify', () {
      final c = VariableHighlightController(variables: {'a': '1'});
      var notifies = 0;
      c
        ..addListener(() => notifies++)
        ..updateVariables({'a': '1'});
      expect(notifies, 0);
      c.updateVariables({'a': '2'});
      expect(notifies, 1);
    });
  });
}

/// Minimal BuildContext stand-in — buildTextSpan only forwards it, never reads
/// from it for the highlighted path under test.
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
