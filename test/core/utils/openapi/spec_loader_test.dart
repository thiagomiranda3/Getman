// test/core/utils/openapi/spec_loader_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';

void main() {
  group('loadSpec', () {
    test('decodes JSON to a Map', () {
      final map = loadSpec('{"openapi":"3.0.0","info":{"title":"X"}}');
      expect(map['openapi'], '3.0.0');
      expect((map['info'] as Map)['title'], 'X');
    });

    test('decodes YAML to a Map with nested maps/lists normalized', () {
      const yaml = '''
openapi: 3.0.0
info:
  title: X
servers:
  - url: https://api.example.com
''';
      final map = loadSpec(yaml);
      expect(map['openapi'], '3.0.0');
      expect((map['info'] as Map)['title'], 'X');
      final servers = map['servers'] as List;
      expect((servers.first as Map)['url'], 'https://api.example.com');
    });

    test('JSON and equivalent YAML produce equal structures', () {
      final fromJson = loadSpec('{"a":{"b":[1,2]}}');
      final fromYaml = loadSpec('a:\n  b:\n    - 1\n    - 2\n');
      expect(fromJson.toString(), fromYaml.toString());
    });

    test('throws FormatException on garbage', () {
      expect(() => loadSpec(':::not valid:::\n\t['), throwsFormatException);
    });

    test('throws FormatException when the root is not a map', () {
      expect(() => loadSpec('[1,2,3]'), throwsFormatException);
    });
  });
}
