// test/core/utils/openapi/schema_sampler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/schema_sampler.dart';

void main() {
  test('uses example when present', () {
    expect(sampleSchema({'type': 'string', 'example': 'hi'}), 'hi');
  });

  test('uses default when present and no example', () {
    expect(sampleSchema({'type': 'integer', 'default': 7}), 7);
  });

  test('uses first enum value', () {
    expect(
      sampleSchema({
        'enum': ['a', 'b'],
      }),
      'a',
    );
  });

  test('object produces a map of sampled properties', () {
    final out = sampleSchema({
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
        'active': {'type': 'boolean'},
      },
    });
    expect(out, {'name': '', 'age': 0, 'active': false});
  });

  test('array produces a single-element list of the item sample', () {
    final out = sampleSchema({
      'type': 'array',
      'items': {'type': 'string', 'example': 'x'},
    });
    expect(out, ['x']);
  });

  test('allOf merges object properties', () {
    final out = sampleSchema({
      'allOf': [
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'string'},
          },
        },
        {
          'type': 'object',
          'properties': {
            'b': {'type': 'integer'},
          },
        },
      ],
    });
    expect(out, {'a': '', 'b': 0});
  });

  test('untyped node with properties is treated as an object', () {
    final out = sampleSchema({
      'properties': {
        'k': {'type': 'string'},
      },
    });
    expect(out, {'k': ''});
  });

  test('depth cap stops runaway nesting and returns {}', () {
    // A self-similar object deeper than the cap collapses to {}.
    Map<String, dynamic> nest(int n) => n == 0
        ? {'type': 'string'}
        : {
            'type': 'object',
            'properties': {'child': nest(n - 1)},
          };
    final out = sampleSchema(nest(50));
    expect((out! as Map<String, dynamic>).containsKey('child'), isTrue);
  });
}
