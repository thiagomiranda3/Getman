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
  // Fast-out: no `{{` on the line means no variable token is possible, so the
  // (regex) scan + run flattening is pure waste. Most JSON lines hit this.
  if (!text.contains('{{')) return base;

  final matches = EnvironmentResolver.findVariables(text).toList();
  if (matches.isEmpty) return base;

  // Precompute each match's color once (ascending, non-overlapping ranges).
  final ranges = <({int start, int end, Color color})>[];
  for (final m in matches) {
    final resolved =
        variables.containsKey(m.name) || EnvironmentResolver.isDynamic(m.name);
    ranges.add((
      start: m.start,
      end: m.end,
      color: resolved ? resolvedColor : unresolvedColor,
    ));
  }

  // 1. Flatten `base` into contiguous runs: (start, end, style).
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

  // 2. Single sweep: runs and ranges are both ascending, so one monotonic
  // pointer `mi` over the ranges suffices. O(line + matches), no per-char scan.
  final children = <InlineSpan>[];
  var mi = 0;
  for (final run in runs) {
    var i = run.start;
    while (i < run.end) {
      while (mi < ranges.length && ranges[mi].end <= i) {
        mi++;
      }
      final inRange =
          mi < ranges.length && i >= ranges[mi].start && i < ranges[mi].end;
      final color = inRange ? ranges[mi].color : null;
      final int j;
      if (inRange) {
        j = ranges[mi].end < run.end ? ranges[mi].end : run.end;
      } else {
        final nextStart = mi < ranges.length ? ranges[mi].start : run.end;
        j = nextStart < run.end ? nextStart : run.end;
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
