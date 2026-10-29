// Iterative JSON property-name extraction for incomplete request bodies.
// Tracks object/array context and quoted strings, so colons and escaped quotes
// inside values cannot become learned keys. Counts a key as soon as its colon
// is typed; stops at the first malformed/incomplete token and retains earlier
// keys. Complete unquoted {{variables}} are opaque values, never objects.
// One forward scan, no recursive descent or backtracking regex.
import 'dart:convert';

import 'package:getman/features/tabs/domain/logic/body_field_dictionary_limits.dart';

Map<String, int> extractJsonFieldCounts(String text) {
  final counts = <String, int>{};
  final stack = <_Container>[];
  var offset = _skipWhitespace(text, 0);
  if (offset == text.length) return counts;
  final first = text.codeUnitAt(offset);
  if (first != 123 && first != 91) return counts;
  stack.add(_Container(isObject: first == 123));
  offset++;

  while (offset < text.length && stack.isNotEmpty) {
    offset = _skipWhitespace(text, offset);
    if (offset == text.length) break;
    final frame = stack.last;
    final code = text.codeUnitAt(offset);
    if (code == (frame.isObject ? 125 : 93)) {
      if (frame.stage == _Stage.colon ||
          (frame.isObject && frame.stage == _Stage.value)) {
        break;
      }
      stack.removeLast();
      offset++;
      continue;
    }
    if (frame.stage == _Stage.end) {
      if (code != 44) break;
      frame.stage = frame.isObject ? _Stage.key : _Stage.value;
      offset++;
      continue;
    }
    if (frame.stage == _Stage.colon) {
      if (code != 58) break;
      final key = frame.key!;
      if (isLearnableBodyFieldName(key)) {
        counts.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
      frame
        ..key = null
        ..stage = _Stage.value;
      offset++;
      continue;
    }
    if (code == 34) {
      final end = _stringEnd(text, offset);
      if (end == null) break;
      if (frame.stage == _Stage.key) {
        try {
          frame
            ..key = jsonDecode(text.substring(offset, end)) as String
            ..stage = _Stage.colon;
        } on FormatException {
          break;
        }
      } else {
        frame.stage = _Stage.end;
      }
      offset = end;
      continue;
    }
    if (frame.stage == _Stage.key) break;
    if (code == 123 &&
        offset + 1 < text.length &&
        text.codeUnitAt(offset + 1) == 123) {
      final end = _variableEnd(text, offset);
      if (end == null) break;
      frame.stage = _Stage.end;
      offset = end;
      continue;
    }
    if (code == 123 || code == 91) {
      frame.stage = _Stage.end;
      stack.add(_Container(isObject: code == 123));
      offset++;
      continue;
    }
    // Scalars cannot contain a property name; consume each only once. JSON
    // decoding rejects malformed tokens before accepting any following keys.
    final start = offset;
    while (offset < text.length && !_scalarBoundary(text.codeUnitAt(offset))) {
      offset++;
    }
    if (offset == start) break;
    try {
      jsonDecode(text.substring(start, offset));
    } on FormatException {
      break;
    }
    frame.stage = _Stage.end;
  }
  return counts;
}

enum _Stage { key, colon, value, end }

class _Container {
  _Container({required this.isObject})
    : stage = isObject ? _Stage.key : _Stage.value;

  final bool isObject;
  _Stage stage;
  String? key;
}

int _skipWhitespace(String text, int offset) {
  var current = offset;
  while (current < text.length && _isWhitespace(text.codeUnitAt(current))) {
    current++;
  }
  return current;
}

bool _isWhitespace(int code) =>
    code == 32 || code == 9 || code == 10 || code == 13;

bool _scalarBoundary(int code) =>
    _isWhitespace(code) || code == 44 || code == 125 || code == 93;

int? _stringEnd(String text, int start) {
  for (var offset = start + 1; offset < text.length; offset++) {
    final code = text.codeUnitAt(offset);
    if (code == 34) return offset + 1;
    if (code < 32) return null;
    if (code != 92) continue;
    offset++;
    if (offset >= text.length) return null;
    final escaped = text.codeUnitAt(offset);
    if (escaped == 117) {
      for (var digit = 0; digit < 4; digit++) {
        offset++;
        if (offset >= text.length || !_isHex(text.codeUnitAt(offset))) {
          return null;
        }
      }
    } else if (escaped != 34 &&
        escaped != 47 &&
        escaped != 92 &&
        escaped != 98 &&
        escaped != 102 &&
        escaped != 110 &&
        escaped != 114 &&
        escaped != 116) {
      return null;
    }
  }
  return null;
}

bool _isHex(int code) =>
    (code >= 48 && code <= 57) ||
    (code >= 65 && code <= 70) ||
    (code >= 97 && code <= 102);

int? _variableEnd(String text, int start) {
  for (var offset = start + 2; offset < text.length; offset++) {
    final code = text.codeUnitAt(offset);
    if (code == 123) return null;
    if (code != 125) continue;
    if (offset > start + 2 &&
        offset + 1 < text.length &&
        text.codeUnitAt(offset + 1) == 125) {
      return offset + 2;
    }
    return null;
  }
  return null;
}
