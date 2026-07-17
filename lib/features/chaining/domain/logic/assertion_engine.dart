import 'dart:convert';

import 'package:getman/core/domain/entities/assertion_result.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';

/// Runs assertions against a response. Pure; returns one [AssertionResult] per
/// enabled assertion with a human label, pass/fail, and the actual value.
class AssertionEngine {
  AssertionEngine._();

  /// Decodes the body once, then delegates to [runDecoded]. Callers running
  /// both engines should decode once themselves and use [runDecoded] (see
  /// `rules_runner.dart`).
  static List<AssertionResult> run(
    List<Assertion> assertions,
    HttpResponseEntity response,
  ) => runDecoded(assertions, response, JsonPath.tryDecode(response.body));

  /// Like [run] but reuses an already-decoded JSON [decodedBody] (null when the
  /// body wasn't JSON), so N bodyJsonPath assertions don't re-decode N times.
  static List<AssertionResult> runDecoded(
    List<Assertion> assertions,
    HttpResponseEntity response,
    Object? decodedBody,
  ) {
    final results = <AssertionResult>[];
    for (final a in assertions) {
      if (!a.enabled) continue;
      final (actual, present) = _actual(a, response, decodedBody);
      final passed = _compare(a.comparator, actual, a.expected, present);
      results.add(
        AssertionResult(label: _label(a), passed: passed, actual: actual),
      );
    }
    return results;
  }

  /// Returns the actual value as a string + whether it was present at all.
  static (String, bool) _actual(
    Assertion a,
    HttpResponseEntity response,
    Object? decodedBody,
  ) {
    switch (a.target) {
      case AssertionTarget.statusCode:
        return (response.statusCode.toString(), true);
      case AssertionTarget.responseTime:
        return (response.durationMs.toString(), true);
      case AssertionTarget.bodyJsonPath:
        // lookup, not read: a present-but-null leaf is a value ('null'), not
        // a miss — `exists` must pass on the node the TREE view renders.
        final r = JsonPath.lookup(decodedBody, a.path);
        return r.found ? (_stringify(r.value), true) : ('(not found)', false);
      case AssertionTarget.header:
        final h = _header(response.headers, a.path);
        return h == null ? ('(absent)', false) : (h, true);
    }
  }

  static bool _compare(
    AssertionComparator c,
    String actual,
    String expected,
    bool present,
  ) {
    switch (c) {
      case AssertionComparator.exists:
        return present;
      case AssertionComparator.equals:
        return present && actual == expected;
      case AssertionComparator.notEquals:
        // Gate on presence like equals/contains: a missing field must not
        // "pass" notEquals just because its "(not found)" sentinel differs.
        return present && actual != expected;
      case AssertionComparator.contains:
        return present && actual.contains(expected);
      case AssertionComparator.lessThan:
        final a = num.tryParse(actual);
        final e = num.tryParse(expected);
        return a != null && e != null && a < e;
      case AssertionComparator.greaterThan:
        final a = num.tryParse(actual);
        final e = num.tryParse(expected);
        return a != null && e != null && a > e;
      case AssertionComparator.inRange:
        final a = num.tryParse(actual);
        if (a == null) return false;
        // `lo-hi` or `lo..hi` — a plain split('-') can't express negative
        // bounds ('-10-0'), so anchor each bound as a signed number.
        final m = RegExp(
          r'^\s*(-?\d+(?:\.\d+)?)\s*(?:\.\.|-)\s*(-?\d+(?:\.\d+)?)\s*$',
        ).firstMatch(expected);
        if (m == null) return false;
        final lo = num.tryParse(m.group(1)!);
        final hi = num.tryParse(m.group(2)!);
        return lo != null && hi != null && a >= lo && a <= hi;
    }
  }

  static String _label(Assertion a) {
    final subject = switch (a.target) {
      AssertionTarget.statusCode => 'status',
      AssertionTarget.responseTime => 'time (ms)',
      AssertionTarget.bodyJsonPath => a.path.isEmpty ? 'body' : a.path,
      AssertionTarget.header => a.path.isEmpty ? 'header' : 'header ${a.path}',
    };
    final verb = switch (a.comparator) {
      AssertionComparator.equals => '=',
      AssertionComparator.notEquals => '≠',
      AssertionComparator.contains => 'contains',
      AssertionComparator.lessThan => '<',
      AssertionComparator.greaterThan => '>',
      AssertionComparator.inRange => 'in',
      AssertionComparator.exists => 'exists',
    };
    return a.comparator == AssertionComparator.exists
        ? '$subject $verb'
        : '$subject $verb ${a.expected}';
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
