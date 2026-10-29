// Advisory JSON template syntax validation for request bodies. Complete
// unquoted {{variables}} stand in for JSON values without resolving them;
// padding preserves UTF-16 offsets for caret navigation in the source editor.
// Quoted strings retain JSON escape validation. No request data leaves here.
import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The first syntax error, with one-based line/column and UTF-16 offset.
class JsonBodyValidationError extends Equatable {
  const JsonBodyValidationError({
    required this.message,
    required this.offset,
    required this.line,
    required this.column,
  });

  final String message;
  final int offset;
  final int line;
  final int column;

  JsonBodyValidationError copyWith({
    String? message,
    int? offset,
    int? line,
    int? column,
  }) => JsonBodyValidationError(
    message: message ?? this.message,
    offset: offset ?? this.offset,
    line: line ?? this.line,
    column: column ?? this.column,
  );

  @override
  List<Object> get props => [message, offset, line, column];
}

/// Validates template syntax only; empty bodies are valid for this advisory.
JsonBodyValidationError? validateJsonBody(String source) {
  if (source.trim().isEmpty) return null;
  try {
    jsonDecode(_maskUnquotedVariables(source));
    return null;
  } on FormatException catch (error) {
    final offset = (error.offset ?? source.length).clamp(0, source.length);
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (source.codeUnitAt(i) == 10) {
        line++;
        lineStart = i + 1;
      }
    }
    return JsonBodyValidationError(
      message: error.message,
      offset: offset,
      line: line,
      column: offset - lineStart + 1,
    );
  }
}

final _variable = RegExp(r'\{\{([^{}]+?)\}\}');

String _maskUnquotedVariables(String source) {
  final result = StringBuffer();
  var inString = false;
  var escaped = false;
  for (var i = 0; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (!inString && char == 123) {
      final token = _variable.matchAsPrefix(source, i);
      if (token != null) {
        // A JSON null sentinel also rejects an unquoted variable used as
        // an object key: templates here stand for values, never JSON syntax.
        result
          ..write('null')
          ..write(' ' * (token.end - i - 4));
        i = token.end - 1;
        continue;
      }
    }
    result.writeCharCode(char);
    if (escaped) {
      escaped = false;
    } else if (inString && char == 92) {
      escaped = true;
    } else if (char == 34) {
      inString = !inString;
    }
  }
  return result.toString();
}
