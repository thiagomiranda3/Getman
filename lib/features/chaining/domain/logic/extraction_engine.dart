import 'dart:convert';

import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';

/// Runs extraction rules against a response, producing the value each rule
/// captured (or a miss). Pure — no I/O, no environment mutation; the caller
/// decides what to do with the captured values.
class ExtractionEngine {
  ExtractionEngine._();

  static List<ExtractionResult> run(
    List<ExtractionRule> rules,
    HttpResponseEntity response,
  ) {
    final results = <ExtractionResult>[];
    for (final rule in rules) {
      if (!rule.enabled || rule.targetVariable.isEmpty) continue;
      final value = _extract(rule, response);
      results.add(ExtractionResult(
        variable: rule.targetVariable,
        value: value,
        matched: value != null,
      ));
    }
    return results;
  }

  static String? _extract(ExtractionRule rule, HttpResponseEntity response) {
    switch (rule.kind) {
      case ExtractionKind.jsonPath:
        final v = JsonPath.readFromString(response.body, rule.expression);
        return v == null ? null : _stringify(v);
      case ExtractionKind.header:
        return _header(response.headers, rule.expression);
      case ExtractionKind.regex:
        try {
          final match = RegExp(rule.expression).firstMatch(response.body);
          if (match == null) return null;
          return match.groupCount >= 1 ? match.group(1) : match.group(0);
        } catch (_) {
          return null; // invalid regex
        }
    }
  }

  static String? _header(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  static String _stringify(Object value) =>
      value is String ? value : jsonEncode(value);
}
