import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/utils/environment_resolver.dart';

class VariableHighlightController extends TextEditingController {
  Map<String, String> _variables;

  // Theme-dependent, so they can't be known at construction time (no
  // BuildContext yet). The owning widget pushes them via [updateColors] in
  // `didChangeDependencies`; until then tokens render unhighlighted.
  Color? _resolvedColor;
  Color? _unresolvedColor;

  // Per-paint memo: the variable scan depends only on `text`, so we recompute
  // it only when the text actually changes — not on every repaint (cursor
  // blink, focus, theme-driven paints). Resolved-vs-unresolved coloring is
  // decided per token at span-build time from `_variables`, so variable/color
  // updates do not invalidate this cache.
  String? _cachedText;
  List<VariableMatch>? _cachedMatches;

  List<VariableMatch> _matchesFor(String current) {
    if (_cachedText == current && _cachedMatches != null) {
      return _cachedMatches!;
    }
    final matches = EnvironmentResolver.findVariables(current).toList();
    _cachedText = current;
    _cachedMatches = matches;
    return matches;
  }

  VariableHighlightController({
    super.text,
    Map<String, String> variables = const {},
  }) : _variables = variables;

  Map<String, String> get variables => _variables;

  void updateVariables(Map<String, String> variables) {
    if (const MapEquality<String, String>().equals(_variables, variables)) return;
    _variables = variables;
    notifyListeners();
  }

  void updateColors({required Color resolved, required Color unresolved}) {
    if (_resolvedColor == resolved && _unresolvedColor == unresolved) return;
    _resolvedColor = resolved;
    _unresolvedColor = unresolved;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String current = text;
    if (current.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final resolvedColor = _resolvedColor;
    final unresolvedColor = _unresolvedColor;
    if (resolvedColor == null || unresolvedColor == null) {
      return TextSpan(style: style, text: current);
    }

    final matches = _matchesFor(current);
    if (matches.isEmpty) {
      return TextSpan(style: style, text: current);
    }

    final children = <InlineSpan>[];
    int cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        children.add(TextSpan(style: style, text: current.substring(cursor, match.start)));
      }
      // Built-in dynamic vars ({{$timestamp}}, {{$guid}}, …) always resolve.
      final resolved = _variables.containsKey(match.name) ||
          EnvironmentResolver.isDynamic(match.name);
      final highlightStyle = (style ?? const TextStyle()).copyWith(
        color: resolved ? resolvedColor : unresolvedColor,
        fontWeight: FontWeight.w800,
      );
      children.add(TextSpan(
        style: highlightStyle,
        text: current.substring(match.start, match.end),
      ));
      cursor = match.end;
    }
    if (cursor < current.length) {
      children.add(TextSpan(style: style, text: current.substring(cursor)));
    }

    return TextSpan(style: style, children: children);
  }
}
