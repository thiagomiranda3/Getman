import 'dart:convert';
import 'package:flutter/foundation.dart';

class JsonUtils {
  static Future<String> prettify(String? body) async {
    if (body == null || body.isEmpty) return '';
    // Short-circuit: HTML, plain-text, and binary responses never contain
    // top-level JSON objects/arrays, so skip isolate spawn entirely.
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return body;
    return compute(_prettifyJson, body);
  }

  /// Four-space indentation — what `JsonEncoder.withIndent('    ')` produced
  /// here before the lexeme-preserving rewrite; kept so Beautify output stays
  /// byte-identical for JSON that the old path handled correctly.
  static const String _indent = '    ';

  /// Re-indents [body] *without* parsing its scalar lexemes. A decode→re-encode
  /// round trip coerces integers beyond 2^63-1 to lossy doubles
  /// (`9223372036854775808` → `9223372036854776000`), rewrites `\uXXXX`
  /// escapes to raw characters, and throws on out-of-range magnitudes
  /// (`1e999` → `Infinity`). Beautify (Cmd+B) and cURL-paste write this result
  /// back into the body that gets *sent*, so those coercions corrupt the
  /// request. Walking the text token by token and re-emitting every string /
  /// number / literal lexeme verbatim keeps the payload byte-accurate.
  static String _prettifyJson(String body) {
    // Validity gate: only reindent text that IS parseable JSON. An arbitrary
    // HTTP response (an XML/HTML error page, a JS array literal, the over-1-MB
    // placeholder, etc.) is returned verbatim — the intended contract the
    // callers rely on. A parse miss on an arbitrary response is normal, not a
    // bug, so it is deliberately not logged. The decoded value is discarded;
    // json.decode is used only as a validity check.
    try {
      json.decode(body);
    } on Object catch (_) {
      return body;
    }
    try {
      return _reindent(body);
    } on Object catch (_) {
      // The text parsed as JSON above, so this is defensive only: never throw
      // out of the compute() isolate — fall back to the verbatim body.
      return body;
    }
  }

  static String _reindent(String source) {
    final tokens = _tokenize(source);
    final out = StringBuffer();
    var depth = 0;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      switch (token.type) {
        case _TokenType.openObject:
        case _TokenType.openArray:
          out.write(token.text);
          final closing = token.type == _TokenType.openObject
              ? _TokenType.closeObject
              : _TokenType.closeArray;
          final next = i + 1 < tokens.length ? tokens[i + 1] : null;
          if (next != null && next.type == closing) {
            // Empty container: `{}` / `[]` stay on one line.
            break;
          }
          depth++;
          out
            ..write('\n')
            ..write(_indent * depth);
        case _TokenType.closeObject:
        case _TokenType.closeArray:
          final opening = token.type == _TokenType.closeObject
              ? _TokenType.openObject
              : _TokenType.openArray;
          final prev = i > 0 ? tokens[i - 1] : null;
          if (prev != null && prev.type == opening) {
            // Matching empty open immediately precedes → emit adjacent.
            out.write(token.text);
            break;
          }
          depth--;
          out
            ..write('\n')
            ..write(_indent * depth)
            ..write(token.text);
        case _TokenType.comma:
          out
            ..write(',')
            ..write('\n')
            ..write(_indent * depth);
        case _TokenType.colon:
          out.write(': ');
        case _TokenType.value:
          out.write(token.text);
      }
    }
    return out.toString();
  }

  /// Splits validated JSON text into structural tokens plus opaque `value`
  /// tokens (strings / numbers / literals) whose text is preserved verbatim.
  static List<_Token> _tokenize(String s) {
    final tokens = <_Token>[];
    final len = s.length;
    var i = 0;
    while (i < len) {
      final c = s[i];
      if (_isWhitespace(c)) {
        i++;
        continue;
      }
      switch (c) {
        case '{':
          tokens.add(const _Token(_TokenType.openObject, '{'));
          i++;
        case '}':
          tokens.add(const _Token(_TokenType.closeObject, '}'));
          i++;
        case '[':
          tokens.add(const _Token(_TokenType.openArray, '['));
          i++;
        case ']':
          tokens.add(const _Token(_TokenType.closeArray, ']'));
          i++;
        case ':':
          tokens.add(const _Token(_TokenType.colon, ':'));
          i++;
        case ',':
          tokens.add(const _Token(_TokenType.comma, ','));
          i++;
        case '"':
          final start = i;
          i++; // consume opening quote
          while (i < len) {
            final ch = s[i];
            if (ch == r'\') {
              // Copy the escape and its escaped char verbatim; a `\uXXXX`
              // sequence flows through since the four hex digits are ordinary
              // chars on the next iterations.
              i += 2;
              continue;
            }
            if (ch == '"') {
              i++; // consume closing quote
              break;
            }
            i++;
          }
          final end = i <= len ? i : len;
          tokens.add(_Token(_TokenType.value, s.substring(start, end)));
        default:
          // A number or a `true` / `false` / `null` literal: munch the whole
          // lexeme up to the next structural char / whitespace / quote and
          // emit it verbatim (numbers are never parsed).
          final start = i;
          while (i < len && !_isTokenBoundary(s[i])) {
            i++;
          }
          tokens.add(_Token(_TokenType.value, s.substring(start, i)));
      }
    }
    return tokens;
  }

  static bool _isWhitespace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static bool _isTokenBoundary(String c) =>
      _isWhitespace(c) ||
      c == '{' ||
      c == '}' ||
      c == '[' ||
      c == ']' ||
      c == ':' ||
      c == ',' ||
      c == '"';
}

enum _TokenType {
  openObject,
  closeObject,
  openArray,
  closeArray,
  colon,
  comma,
  value,
}

@immutable
class _Token {
  const _Token(this.type, this.text);
  final _TokenType type;
  final String text;
}
