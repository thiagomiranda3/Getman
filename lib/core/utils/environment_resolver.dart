// Resolves `{{name}}` tokens in strings/maps against a set of environment
// variables, falling back to dynamic built-ins ($guid/$randomUUID/
// $timestamp/$isoTimestamp/$randomInt). Used on the send path
// (TabsRepositoryImpl) and by the URL/variable highlighter.
//
// Gotchas: the name grammar accepts any non-empty, non-brace text (trimmed)
// — spaces/`@`/`:`/unicode are all valid, matching whatever the env editor,
// Postman import, and `{{` autocomplete can produce. Unknown names are left
// VERBATIM, never blanked. A leading `$` marks a dynamic built-in; each
// occurrence resolves independently (freshly generated, never cached), and
// an environment variable of the same name always wins over the dynamic.
// isDynamic() is the single source of truth for classifying a name as
// dynamic (e.g. what the URL highlighter uses for resolved/unresolved
// coloring).

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
  // The name itself accepts any non-empty, non-brace text (trimmed) — the env
  // editor, Postman import, and the `{{` autocomplete all let a variable name
  // contain spaces/`@`/`:`/unicode, so the resolution grammar must accept
  // whatever they can produce or those variables can never resolve.
  //
  // Whitespace trimming happens on the captured group in Dart (_name), NOT
  // via `\s*` in the pattern: `\s*` bordering `[^{}]+?` overlaps on
  // whitespace, and that ambiguity backtracks quadratically on a large body
  // containing an unclosed `{{` — resolve() runs on the send path.
  static final RegExp _pattern = RegExp(r'\{\{([^{}]+?)\}\}');

  static String _name(Match match) => match.group(1)!.trim();

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

  /// Public accessor for a dynamic variable's freshly-generated value, or null
  /// if [name] is not a recognized dynamic variable. Each call regenerates —
  /// matching send-time behavior — so the hover tooltip shows a representative
  /// sample, not a pinned value.
  static String? resolveDynamic(String name) => _resolveDynamic(name);

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
      final name = _name(match);
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
        name: _name(match),
      );
    }
  }
}
