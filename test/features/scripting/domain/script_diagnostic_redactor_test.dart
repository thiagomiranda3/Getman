import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/scripting/domain/logic/script_diagnostic_redactor.dart';

void main() {
  test('redacts known and freshly written secrets longest first', () {
    final redact = ScriptDiagnosticRedactor(
      secretValues: const {'token', 'token-long', 'new-token', ''},
    );
    expect(
      redact.redact('token-long token new-token at script.js:3'),
      '•••• •••• •••• at script.js:3',
    );
    expect(redact.redact('ordinary text'), 'ordinary text');
  });
  test('redaction accepts literal metacharacters and preserves Unicode', () {
    final redact = ScriptDiagnosticRedactor(secretValues: const {r'a.$[b]'});
    expect(redact.redact(r'sessão a.$[b] 🚀'), 'sessão •••• 🚀');
  });
}
