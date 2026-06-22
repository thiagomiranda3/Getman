import 'package:flutter/material.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart'
    show jsonHighlightSpanBuilder;
import 'package:re_editor/re_editor.dart';

/// JSON-highlights [codeLine], then recolors every `{{var}}` token: resolved
/// (in [variables] or a dynamic built-in) -> [resolvedColor], else
/// [unresolvedColor]. Variable color wins inside `{{…}}`. Implemented as a flat
/// run merge so it never mutates a nested span tree.
TextSpan variableAwareJsonSpan({
  required BuildContext context,
  required int index,
  required CodeLine codeLine,
  required TextSpan textSpan,
  required TextStyle style,
  required Map<String, String> variables,
  required Color resolvedColor,
  required Color unresolvedColor,
}) {
  final base = jsonHighlightSpanBuilder(
    context: context,
    index: index,
    codeLine: codeLine,
    textSpan: textSpan,
    style: style,
  );
  final text = codeLine.text;
  final matches = EnvironmentResolver.findVariables(text).toList();
  if (matches.isEmpty) return base;

  // 1. Flatten `base` into runs: List of (start, end, style).
  final runs = <({int start, int end, TextStyle style})>[];
  var cursor = 0;
  void visit(InlineSpan span, TextStyle inherited) {
    if (span is TextSpan) {
      final s = span.style == null ? inherited : inherited.merge(span.style);
      final t = span.text;
      if (t != null && t.isNotEmpty) {
        runs.add((start: cursor, end: cursor + t.length, style: s));
        cursor += t.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, s);
      }
    }
  }

  visit(base, style);
  if (cursor == 0) {
    // base had no leaf text (shouldn't happen) — fall back to whole-line style.
    runs.add((start: 0, end: text.length, style: style));
  }

  // 2. Build a per-character color override for variable ranges.
  Color? overrideAt(int i) {
    for (final m in matches) {
      if (i >= m.start && i < m.end) {
        final resolved =
            variables.containsKey(m.name) ||
            EnvironmentResolver.isDynamic(m.name);
        return resolved ? resolvedColor : unresolvedColor;
      }
    }
    return null;
  }

  // 3. Re-emit runs, splitting where the variable override changes the color.
  final children = <InlineSpan>[];
  for (final run in runs) {
    var i = run.start;
    while (i < run.end) {
      final color = overrideAt(i);
      var j = i + 1;
      while (j < run.end && overrideAt(j) == color) {
        j++;
      }
      final segStyle = color == null
          ? run.style
          : run.style.copyWith(color: color, fontWeight: FontWeight.w800);
      children.add(TextSpan(text: text.substring(i, j), style: segStyle));
      i = j;
    }
  }
  return TextSpan(style: style, children: children);
}
