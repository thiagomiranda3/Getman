// Pure engine that runs ExtractionRules against a response; see the class
// doc for the run/runDecoded shared-decode contract with AssertionEngine.

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

  /// Decodes the body once, then delegates to [runDecoded]. Callers running
  /// both engines should decode once themselves and use [runDecoded] (see
  /// `rules_runner.dart`).
  static List<ExtractionResult> run(
    List<ExtractionRule> rules,
    HttpResponseEntity response,
  ) => runDecoded(rules, response, JsonPath.tryDecode(response.body));

  /// Like [run] but reuses an already-decoded JSON [decodedBody] (null when the
  /// body wasn't JSON), so N jsonPath rules don't re-decode the body N times.
  static List<ExtractionResult> runDecoded(
    List<ExtractionRule> rules,
    HttpResponseEntity response,
    Object? decodedBody,
  ) {
    final results = <ExtractionResult>[];
    for (final rule in rules) {
      if (!rule.enabled || rule.targetVariable.isEmpty) continue;
      final value = _extract(rule, response, decodedBody);
      results.add(
        ExtractionResult(
          variable: rule.targetVariable,
          value: value,
          matched: value != null,
        ),
      );
    }
    return results;
  }

  static String? _extract(
    ExtractionRule rule,
    HttpResponseEntity response,
    Object? decodedBody,
  ) {
    switch (rule.kind) {
      case ExtractionKind.jsonPath:
        // lookup, not read: a present-but-null leaf (which the TREE view
        // renders and offers Extract on) must capture 'null', not report a
        // miss.
        final r = JsonPath.lookup(decodedBody, rule.expression);
        return r.found ? _stringify(r.value) : null;
      case ExtractionKind.header:
        return _header(response.headers, rule.expression);
      case ExtractionKind.regex:
        try {
          final match = RegExp(rule.expression).firstMatch(response.body);
          if (match == null) return null;
          // First PARTICIPATING group: in an alternation like `a=(\w+)|b=(\w+)`
          // group 1 can be null even though the pattern matched.
          for (var i = 1; i <= match.groupCount; i++) {
            final group = match.group(i);
            if (group != null) return group;
          }
          return match.group(0);
        } on Object catch (_) {
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

  static String _stringify(Object? value) =>
      value is String ? value : jsonEncode(value);
}
