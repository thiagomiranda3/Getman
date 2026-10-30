// Literal secret-value masking for display. Callers include captured values
// and new values proposed for existing secret keys; this is not taint tracking.
class ScriptDiagnosticRedactor {
  ScriptDiagnosticRedactor({required Iterable<String> secretValues})
    : _values = secretValues.where((value) => value.isNotEmpty).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  final List<String> _values;
  String redact(String text) {
    var result = text;
    for (final value in _values) {
      result = result.replaceAll(value, '••••');
    }
    return result;
  }
}
