// test/core/utils/apidoc/json_schema_inferrer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

void main() {
  group('JsonSchemaInferrer.infer', () {
    test('infers an object with typed properties and required keys', () {
      final schema = JsonSchemaInferrer.infer({
        'id': 1,
        'name': 'ada',
        'active': true,
        'score': 9.5,
      });
      expect(schema.type, 'object');
      expect(schema.properties['id']!.type, 'integer');
      expect(schema.properties['name']!.type, 'string');
      expect(schema.properties['active']!.type, 'boolean');
      expect(schema.properties['score']!.type, 'number');
      expect(
        schema.required,
        containsAll(<String>['id', 'name', 'active', 'score']),
      );
    });

    test('infers nested objects and arrays from the first element', () {
      final schema = JsonSchemaInferrer.infer({
        'tags': ['a', 'b'],
        'owner': {'uid': 7},
      });
      expect(schema.properties['tags']!.type, 'array');
      expect(schema.properties['tags']!.items!.type, 'string');
      expect(schema.properties['owner']!.type, 'object');
      expect(schema.properties['owner']!.properties['uid']!.type, 'integer');
    });

    test('empty array yields array schema with no items', () {
      final schema = JsonSchemaInferrer.infer(<dynamic>[]);
      expect(schema.type, 'array');
      expect(schema.items, isNull);
    });

    test('null yields a nullable schema with no type', () {
      final schema = JsonSchemaInferrer.infer(null);
      expect(schema.nullable, isTrue);
      expect(schema.type, isNull);
    });

    test(
      'toOpenApi emits object with properties, required, and nested items',
      () {
        final schema = JsonSchemaInferrer.infer({
          'tags': ['a'],
          'n': 1,
        });
        final map = schema.toOpenApi();
        expect(map['type'], 'object');
        expect((map['properties'] as Map)['n'], {'type': 'integer'});
        expect((map['properties'] as Map)['tags'], {
          'type': 'array',
          'items': {'type': 'string'},
        });
        expect(map['required'], containsAll(<String>['tags', 'n']));
      },
    );

    test(
      'empty array toOpenApi emits a permissive items:{} (OAS 3.0 requires '
      'an `items` key on every array schema)',
      () {
        final schema = JsonSchemaInferrer.infer(<dynamic>[]);
        final map = schema.toOpenApi();
        expect(map['type'], 'array');
        expect(map['items'], <String, dynamic>{});
      },
    );

    test('binary format round-trips through toOpenApi', () {
      const schema = JsonSchema(type: 'string', format: 'binary');
      expect(schema.toOpenApi(), {'type': 'string', 'format': 'binary'});
    });
  });
}
