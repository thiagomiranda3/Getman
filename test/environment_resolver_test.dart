import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/environment_resolver.dart';

void main() {
  group('EnvironmentResolver.resolve', () {
    test('empty input returns empty', () {
      expect(EnvironmentResolver.resolve('', {'a': '1'}), '');
    });

    test('no variables returns input unchanged', () {
      expect(EnvironmentResolver.resolve('https://example.com/foo', {}), 'https://example.com/foo');
    });

    test('substitutes a single variable', () {
      expect(
        EnvironmentResolver.resolve('{{baseUrl}}/users', {'baseUrl': 'https://api.example.com'}),
        'https://api.example.com/users',
      );
    });

    test('substitutes multiple variables in one string', () {
      expect(
        EnvironmentResolver.resolve('{{scheme}}://{{host}}/users', {
          'scheme': 'https',
          'host': 'api.example.com',
        }),
        'https://api.example.com/users',
      );
    });

    test('leaves unknown variable names verbatim', () {
      expect(
        EnvironmentResolver.resolve('{{baseUrl}}/{{missing}}', {'baseUrl': 'https://x'}),
        'https://x/{{missing}}',
      );
    });

    test('tolerates whitespace inside the braces', () {
      expect(
        EnvironmentResolver.resolve('{{ baseUrl }}/x', {'baseUrl': 'A'}),
        'A/x',
      );
    });

    test('supports dots, dashes, and underscores in identifiers', () {
      expect(
        EnvironmentResolver.resolve('{{my-var_1.env}}', {'my-var_1.env': 'ok'}),
        'ok',
      );
    });

    test('leaves unbalanced braces untouched', () {
      expect(
        EnvironmentResolver.resolve('{{baseUrl', {'baseUrl': 'x'}),
        '{{baseUrl',
      );
      expect(
        EnvironmentResolver.resolve('baseUrl}}', {'baseUrl': 'x'}),
        'baseUrl}}',
      );
    });

    test('is case-sensitive', () {
      expect(
        EnvironmentResolver.resolve('{{BaseUrl}}', {'baseurl': 'x'}),
        '{{BaseUrl}}',
      );
    });

    test('does not recursively resolve — replacement values are literal', () {
      expect(
        EnvironmentResolver.resolve('{{a}}', {'a': '{{b}}', 'b': 'final'}),
        '{{b}}',
      );
    });
  });

  group('EnvironmentResolver.resolveMap', () {
    test('empty input returns empty map', () {
      expect(EnvironmentResolver.resolveMap(const {}, {'a': '1'}), const <String, String>{});
    });

    test('substitutes values but leaves keys alone', () {
      final result = EnvironmentResolver.resolveMap(
        {'Authorization': 'Bearer {{token}}', 'X-{{leave-key}}': 'ok'},
        {'token': 'abc'},
      );
      expect(result['Authorization'], 'Bearer abc');
      expect(result['X-{{leave-key}}'], 'ok');
    });
  });

  group('EnvironmentResolver.findVariables', () {
    test('empty input yields nothing', () {
      expect(EnvironmentResolver.findVariables('').toList(), isEmpty);
    });

    test('finds all variable positions and names', () {
      final matches = EnvironmentResolver.findVariables('{{a}}/static/{{b}}').toList();
      expect(matches.length, 2);
      expect(matches[0].name, 'a');
      expect(matches[0].start, 0);
      expect(matches[0].end, 5);
      expect(matches[1].name, 'b');
    });

    test('finds names even when braces contain whitespace', () {
      final matches = EnvironmentResolver.findVariables('{{ baseUrl }}').toList();
      expect(matches, hasLength(1));
      expect(matches.first.name, 'baseUrl');
    });
  });
}
