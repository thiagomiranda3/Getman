// TextEditingController subclass that colors `{{var}}` tokens resolved vs.
// unresolved (plus built-in $dynamic vars) in buildTextSpan, and reports
// hover enter/exit on each token span for a resolution popover.
//
// Gotchas: the constructor takes no colors — they're theme-dependent and
// unknown before a BuildContext exists — so the owning widget pushes them
// via updateColors, and pushes the variable map via updateVariables, both
// typically from didChangeDependencies. Both methods call notifyListeners()
// ONLY when the value actually changed (MapEquality for variables, == for
// colors); skipping that check would rebuild the URL bar on every BLoC
// emission. The variable-match scan is memoized per exact text value
// (_cachedText), independent of color/variable updates.
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// Reports a hovered `{{var}}` token: its [name] and the global pointer
/// position (so the owner can anchor a popover). Set by the owning widget.
typedef VariableEnterCallback =
    void Function(
      String name,
      Offset globalPosition,
    );

class VariableHighlightController extends TextEditingController {
  VariableHighlightController({
    super.text,
    this._variables = const {},
  });
  Map<String, String> _variables;

  // Theme-dependent, so they can't be known at construction time (no
  // BuildContext yet). The owning widget pushes them via [updateColors] in
  // `didChangeDependencies`; until then tokens render unhighlighted.
  Color? _resolvedColor;
  Color? _unresolvedColor;

  /// Optional hover sink. When set, each `{{var}}` token span reports pointer
  /// enter/exit so the owner can show/hide a resolution popover. Null = no
  /// hover behavior (unchanged rendering).
  VariableEnterCallback? onVariableEnter;
  VoidCallback? onVariableExit;

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

  Map<String, String> get variables => _variables;

  void updateVariables(Map<String, String> variables) {
    if (const MapEquality<String, String>().equals(_variables, variables)) {
      return;
    }
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
    required bool withComposing,
    TextStyle? style,
  }) {
    final current = text;
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
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        children.add(
          TextSpan(style: style, text: current.substring(cursor, match.start)),
        );
      }
      // Built-in dynamic vars ({{$timestamp}}, {{$guid}}, …) always resolve.
      final resolved =
          _variables.containsKey(match.name) ||
          EnvironmentResolver.isDynamic(match.name);
      final highlightStyle = (style ?? const TextStyle()).copyWith(
        color: resolved ? resolvedColor : unresolvedColor,
        fontWeight: FontWeight.w800,
      );
      final enter = onVariableEnter;
      final exit = onVariableExit;
      children.add(
        TextSpan(
          style: highlightStyle,
          text: current.substring(match.start, match.end),
          // Hover is tracked only when an enter sink is wired; exit is paired
          // under the same guard so callers can't get unpaired exit events.
          onEnter: enter == null
              ? null
              : (event) => enter(match.name, event.position),
          onExit: enter == null ? null : (_) => exit?.call(),
        ),
      );
      cursor = match.end;
    }
    if (cursor < current.length) {
      children.add(TextSpan(style: style, text: current.substring(cursor)));
    }

    return TextSpan(style: style, children: children);
  }
}
