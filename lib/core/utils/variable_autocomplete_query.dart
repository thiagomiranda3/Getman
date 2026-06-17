/// The `{{variable}}` token currently being typed at the caret, used to drive
/// the variable autocomplete menu and to compute the insertion. Pure Dart.
class ActiveVariableQuery {
  const ActiveVariableQuery({
    required this.replaceStart,
    required this.replaceEnd,
    required this.query,
    required this.hasClosingBraces,
  });

  /// Index where the variable name starts (just after the opening `{{`).
  final int replaceStart;

  /// The caret offset (end of the typed query).
  final int replaceEnd;

  /// Text between `{{` and the caret. May be empty (just opened).
  final String query;

  /// Whether a `}}` immediately follows the caret (don't double the braces).
  final bool hasClosingBraces;
}

final RegExp _identifierChar = RegExp(r'[A-Za-z0-9_\-.$]');

/// Detects the open `{{` token at [caretOffset], or null if the caret is not
/// inside an in-progress `{{name` (e.g. no opening braces, a closed token, or
/// a non-identifier char between `{{` and the caret). Callers must only invoke
/// this with a collapsed selection.
ActiveVariableQuery? detectActiveVariableQuery(String text, int caretOffset) {
  if (caretOffset < 2 || caretOffset > text.length) return null;
  final open = text.lastIndexOf('{{', caretOffset - 2);
  if (open < 0) return null;
  final nameStart = open + 2;
  if (nameStart > caretOffset) return null;
  final query = text.substring(nameStart, caretOffset);
  for (var i = 0; i < query.length; i++) {
    if (!_identifierChar.hasMatch(query[i])) return null;
  }
  final hasClosingBraces =
      caretOffset + 2 <= text.length &&
      text.substring(caretOffset, caretOffset + 2) == '}}';
  return ActiveVariableQuery(
    replaceStart: nameStart,
    replaceEnd: caretOffset,
    query: query,
    hasClosingBraces: hasClosingBraces,
  );
}
