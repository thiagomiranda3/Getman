// Pure body autocomplete context scanner and UTF-16 replacement ranges.
// Recognizes JSON property positions without requiring a complete document;
// template placeholders are opaque values. All work is linear and bounded.

import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The two namespaces offered by the request body editor.
enum BodyCompletionKind { field, variable }

/// Immutable replacement plan; offsets use the editor's UTF-16 coordinates.
class BodyCompletionTarget extends Equatable {
  /// Creates a replacement plan for the current editor snapshot.
  const BodyCompletionTarget({
    required this.kind,
    required this.query,
    required this.replaceStart,
    required this.replaceEnd,
    this.appendColon = false,
  });

  /// Whether names are JSON properties or environment variables.
  final BodyCompletionKind kind;

  /// The decoded prefix before the caret, used to rank suggestions.
  final String query;

  /// Inclusive start of the token, including existing delimiters.
  final int replaceStart;

  /// Exclusive end of the token, including its suffix and delimiters.
  final int replaceEnd;

  /// Whether the selected property still needs a colon after its name.
  final bool appendColon;

  /// Exact replacement; callers retain all text outside this plan's range.
  String insertion(String name) => switch (kind) {
    BodyCompletionKind.field => '${jsonEncode(name)}${appendColon ? ': ' : ''}',
    BodyCompletionKind.variable => '{{$name}}',
  };

  /// Copies this plan with selected fields changed.
  BodyCompletionTarget copyWith({
    BodyCompletionKind? kind,
    String? query,
    int? replaceStart,
    int? replaceEnd,
    bool? appendColon,
  }) => BodyCompletionTarget(
    kind: kind ?? this.kind,
    query: query ?? this.query,
    replaceStart: replaceStart ?? this.replaceStart,
    replaceEnd: replaceEnd ?? this.replaceEnd,
    appendColon: appendColon ?? this.appendColon,
  );

  @override
  List<Object> get props => [
    kind,
    query,
    replaceStart,
    replaceEnd,
    appendColon,
  ];
}

/// Detects suggestions at [caret] without parsing or rewriting the whole body.
///
/// Bare property slots require explicit activation; quoted prefixes and open
/// `{{variable}}` tokens activate automatically. With [fieldsEnabled] false,
/// explicit activation inserts variables in arbitrary RAW/GraphQL text. Bodies
/// larger than 1 Mi UTF-16 units are skipped to bound synchronous editor work.
BodyCompletionTarget? detectBodyCompletion(
  String text,
  int caret, {
  bool explicit = false,
  bool fieldsEnabled = true,
}) {
  if (caret < 0 || caret > text.length || text.length > 1024 * 1024) {
    return null;
  }
  final variable = _variableTarget(text, caret);
  if (variable != null) return variable;
  if (!fieldsEnabled) return explicit ? _emptyVariable(caret) : null;
  return _JsonContext(text, caret, explicit: explicit).scan();
}

BodyCompletionTarget _emptyVariable(int caret) => BodyCompletionTarget(
  kind: BodyCompletionKind.variable,
  query: '',
  replaceStart: caret,
  replaceEnd: caret,
);

bool _variableBoundary(int unit) =>
    unit == 123 || unit == 125 || unit == 34 || unit < 32;

BodyCompletionTarget? _variableTarget(String text, int caret) {
  if (caret < 2) return null;
  final start = text.lastIndexOf('{{', caret - 2);
  if (start < 0) return null;
  for (var index = start + 2; index < caret; index++) {
    if (_variableBoundary(text.codeUnitAt(index))) return null;
  }
  var end = caret;
  while (end < text.length && !_variableBoundary(text.codeUnitAt(end))) {
    end++;
  }
  if (text.startsWith('}}', end)) {
    // Paired placeholders have an unambiguous end, so names may contain
    // punctuation and spaces without being mistaken for surrounding syntax.
    end += 2;
  } else {
    // An incomplete unquoted placeholder can be followed by JSON/GraphQL
    // syntax. Only replace its name suffix, preserving separators and layout.
    var suffixEnd = caret;
    while (suffixEnd < end && !',:[]()'.contains(text[suffixEnd])) {
      suffixEnd++;
    }
    while (suffixEnd > caret && _whitespace(text.codeUnitAt(suffixEnd - 1))) {
      suffixEnd--;
    }
    end = suffixEnd;
  }
  return BodyCompletionTarget(
    kind: BodyCompletionKind.variable,
    query: text.substring(start + 2, caret),
    replaceStart: start,
    replaceEnd: end,
  );
}

enum _Slot { key, colon, value, comma }

class _Frame {
  _Frame({required this.object}) : slot = object ? _Slot.key : _Slot.value;
  final bool object;
  _Slot slot;
}

class _JsonContext {
  _JsonContext(this.text, this.caret, {required this.explicit});

  final String text;
  final int caret;
  final bool explicit;
  final List<_Frame> stack = [];
  int index = 0;
  bool rootConsumed = false;

  _Slot get slot => stack.isEmpty
      ? (rootConsumed ? _Slot.comma : _Slot.value)
      : stack.last.slot;

  BodyCompletionTarget? scan() {
    while (index <= text.length) {
      if (index == caret) return _atBoundary();
      if (index == text.length) return null;
      final unit = text.codeUnitAt(index);
      if (_whitespace(unit)) {
        index++;
        continue;
      }
      if (unit == 34) {
        final result = _string();
        if (result.target != null || !result.valid) return result.target;
        continue;
      }
      if (slot == _Slot.value && text.startsWith('{{', index)) {
        final end = text.indexOf('}}', index + 2);
        if (end < 0 || end >= caret) return null;
        index = end + 2;
        _consumeValue();
        continue;
      }
      if (unit == 123 || unit == 91) {
        if (slot != _Slot.value) return null;
        _consumeValue();
        stack.add(_Frame(object: unit == 123));
        index++;
        continue;
      }
      if (unit == 125 || unit == 93) {
        if (stack.isEmpty || stack.last.object != (unit == 125)) return null;
        if (slot != _Slot.comma &&
            slot != (stack.last.object ? _Slot.key : _Slot.value)) {
          return null;
        }
        stack.removeLast();
        index++;
        continue;
      }
      if (unit == 58 && slot == _Slot.colon) {
        stack.last.slot = _Slot.value;
        index++;
        continue;
      }
      if (unit == 44 && slot == _Slot.comma && stack.isNotEmpty) {
        stack.last.slot = stack.last.object ? _Slot.key : _Slot.value;
        index++;
        continue;
      }
      if (slot != _Slot.value || !_primitive()) return null;
      if (index >= caret) return explicit ? _emptyVariable(caret) : null;
    }
    return null;
  }

  BodyCompletionTarget? _atBoundary() {
    if (!explicit) return null;
    if (slot == _Slot.key) {
      // A caret immediately before an existing token is ambiguous: don't
      // introduce a second property without a separator.
      var next = index;
      while (next < text.length && _whitespace(text.codeUnitAt(next))) {
        next++;
      }
      if (next < text.length && text.codeUnitAt(next) != 125) return null;
      return BodyCompletionTarget(
        kind: BodyCompletionKind.field,
        query: '',
        replaceStart: caret,
        replaceEnd: caret,
        appendColon: true,
      );
    }
    return slot == _Slot.value ? _emptyVariable(caret) : null;
  }

  ({BodyCompletionTarget? target, bool valid}) _string() {
    if (slot != _Slot.key && slot != _Slot.value) {
      return (target: null, valid: false);
    }
    final start = index++;
    var escaped = false;
    while (index < text.length) {
      final unit = text.codeUnitAt(index);
      if (!escaped && unit == 34) break;
      if (unit < 32) return (target: null, valid: false);
      if (!escaped && unit == 92) {
        escaped = true;
      } else {
        escaped = false;
      }
      index++;
    }
    final contentEnd = index;
    final closed = index < text.length;
    if (closed) index++;
    if (caret > start && caret <= contentEnd) {
      if (slot == _Slot.value) {
        return (
          target: explicit ? _emptyVariable(caret) : null,
          valid: false,
        );
      }
      final prefix = _decodeString('${text.substring(start, caret)}"');
      if (prefix == null) return (target: null, valid: false);
      var next = index;
      while (next < text.length && _whitespace(text.codeUnitAt(next))) {
        next++;
      }
      return (
        target: BodyCompletionTarget(
          kind: BodyCompletionKind.field,
          query: prefix,
          replaceStart: start,
          replaceEnd: index,
          appendColon: next == text.length || text.codeUnitAt(next) != 58,
        ),
        valid: true,
      );
    }
    if (!closed || _decodeString(text.substring(start, index)) == null) {
      return (target: null, valid: false);
    }
    if (slot == _Slot.key) {
      stack.last.slot = _Slot.colon;
    } else {
      _consumeValue();
    }
    return (target: null, valid: true);
  }

  bool _primitive() {
    final start = index;
    while (index < text.length) {
      final unit = text.codeUnitAt(index);
      if (_whitespace(unit) || unit == 44 || unit == 93 || unit == 125) break;
      index++;
    }
    final token = text.substring(start, index);
    if (token != 'true' && token != 'false' && token != 'null') {
      try {
        if (jsonDecode(token) is! num) return false;
      } on FormatException {
        return false;
      }
    }
    _consumeValue();
    return true;
  }

  void _consumeValue() {
    if (stack.isEmpty) {
      rootConsumed = true;
    } else {
      stack.last.slot = _Slot.comma;
    }
  }
}

bool _whitespace(int unit) =>
    unit == 32 || unit == 9 || unit == 10 || unit == 13;

String? _decodeString(String token) {
  try {
    return jsonDecode(token) as String;
  } on FormatException {
    return null;
  }
}
