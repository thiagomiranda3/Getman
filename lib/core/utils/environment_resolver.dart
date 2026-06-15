import 'dart:math';

import 'package:uuid/uuid.dart';

class VariableMatch {
  const VariableMatch({
    required this.start,
    required this.end,
    required this.name,
  });
  final int start;
  final int end;
  final String name;
}

class EnvironmentResolver {
  // Names may carry a leading `$` for built-in dynamic variables
  // ({{$timestamp}}, {{$guid}}, …); plain names map to environment variables.
  static final RegExp _pattern = RegExp(
    r'\{\{\s*(\$?[A-Za-z0-9_\-\.]+)\s*\}\}',
  );

  static const _uuid = Uuid();
  static final Random _random = Random();

  /// Dynamic variable names recognized regardless of the active environment.
  /// Postman-compatible: $guid/$randomUUID, $timestamp (unix seconds),
  /// $isoTimestamp (UTC ISO-8601), $randomInt (0–1000).
  static const Set<String> dynamicNames = {
    r'$guid',
    r'$randomUUID',
    r'$randomUuid',
    r'$timestamp',
    r'$isoTimestamp',
    r'$randomInt',
  };

  static bool isDynamic(String name) => dynamicNames.contains(name);

  static String? _resolveDynamic(String name) {
    switch (name) {
      case r'$guid':
      case r'$randomUUID':
      case r'$randomUuid':
        return _uuid.v4();
      case r'$timestamp':
        return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      case r'$isoTimestamp':
        return DateTime.now().toUtc().toIso8601String();
      case r'$randomInt':
        return _random.nextInt(1001).toString();
      default:
        return null;
    }
  }

  static String resolve(String input, Map<String, String> variables) {
    // No early-out on empty variables: dynamic vars resolve without an env.
    if (input.isEmpty) return input;
    return input.replaceAllMapped(_pattern, (match) {
      final name = match.group(1)!;
      final value = variables[name];
      if (value != null) return value;
      return _resolveDynamic(name) ?? match.group(0)!;
    });
  }

  static Map<String, String> resolveMap(
    Map<String, String> input,
    Map<String, String> variables,
  ) {
    if (input.isEmpty) return input;
    return input.map((key, value) => MapEntry(key, resolve(value, variables)));
  }

  static Iterable<VariableMatch> findVariables(String input) sync* {
    if (input.isEmpty) return;
    for (final match in _pattern.allMatches(input)) {
      yield VariableMatch(
        start: match.start,
        end: match.end,
        name: match.group(1)!,
      );
    }
  }
}
