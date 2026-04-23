class VariableMatch {
  final int start;
  final int end;
  final String name;

  const VariableMatch({required this.start, required this.end, required this.name});
}

class EnvironmentResolver {
  static final RegExp _pattern = RegExp(r'\{\{\s*([A-Za-z0-9_\-\.]+)\s*\}\}');

  static String resolve(String input, Map<String, String> variables) {
    if (input.isEmpty || variables.isEmpty) return input;
    return input.replaceAllMapped(_pattern, (match) {
      final name = match.group(1)!;
      final value = variables[name];
      return value ?? match.group(0)!;
    });
  }

  static Map<String, String> resolveMap(Map<String, String> input, Map<String, String> variables) {
    if (input.isEmpty) return input;
    if (variables.isEmpty) return input;
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
