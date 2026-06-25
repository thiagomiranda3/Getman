import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/mcp/domain/mcp_argument_resolver.dart';

void main() {
  group('resolveMcpArguments', () {
    const vars = {'base': 'api.dev', 'id': '42'};

    test('substitutes {{var}} in string leaves', () {
      final out = resolveMcpArguments(const {
        'url': 'https://{{base}}/v1',
      }, vars);
      expect(out['url'], 'https://api.dev/v1');
    });

    test('recurses into nested maps and lists', () {
      final out = resolveMcpArguments(const {
        'nested': {'who': '{{base}}'},
        'list': ['{{id}}', 'static'],
      }, vars);
      expect((out['nested'] as Map)['who'], 'api.dev');
      expect(out['list'], ['42', 'static']);
    });

    test('passes non-string values through unchanged', () {
      final out = resolveMcpArguments(const {
        'n': 7,
        'b': true,
        'nil': null,
      }, vars);
      expect(out['n'], 7);
      expect(out['b'], true);
      expect(out['nil'], isNull);
    });

    test('leaves unknown variables verbatim', () {
      final out = resolveMcpArguments(const {'x': '{{missing}}'}, vars);
      expect(out['x'], '{{missing}}');
    });

    test(r'resolves dynamic variables like {{$timestamp}}', () {
      final out = resolveMcpArguments(const {'t': r'{{$timestamp}}'}, vars);
      // A dynamic timestamp resolves to digits, not the literal token.
      expect(out['t'], isNot(r'{{$timestamp}}'));
      expect(int.tryParse(out['t'] as String), isNotNull);
    });
  });
}
