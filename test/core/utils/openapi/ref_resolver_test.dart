// test/core/utils/openapi/ref_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/ref_resolver.dart';

void main() {
  final root = <String, dynamic>{
    'components': {
      'schemas': {
        'User': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer'},
            'manager': {r'$ref': '#/components/schemas/User'}, // cycle
          },
        },
      },
    },
    'definitions': {
      'Pet': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      },
    },
  };

  test('resolves a #/components/schemas ref one level', () {
    final r = RefResolver(root);
    final user = r.resolve(<String, dynamic>{
      r'$ref': '#/components/schemas/User',
    });
    expect(user['type'], 'object');
    expect(
      (user['properties'] as Map<String, dynamic>).containsKey('id'),
      isTrue,
    );
  });

  test('resolves a Swagger #/definitions ref', () {
    final r = RefResolver(root);
    final pet = r.resolve(<String, dynamic>{r'$ref': '#/definitions/Pet'});
    final petProps = pet['properties'] as Map<String, dynamic>;
    expect(petProps['name'], isA<Map<String, dynamic>>());
  });

  test('deepResolve replaces nested refs and breaks cycles', () {
    final r = RefResolver(root);
    final resolved = r.deepResolve(<String, dynamic>{
      r'$ref': '#/components/schemas/User',
    });
    final user = resolved! as Map<String, dynamic>;
    final props = user['properties']! as Map<String, dynamic>;
    final manager = props['manager'];
    // Cycle short-circuited to an empty object, not infinite recursion.
    expect(manager, isEmpty);
  });

  test('returns the node unchanged when there is no ref', () {
    final r = RefResolver(root);
    final node = <String, dynamic>{'type': 'string'};
    expect(r.resolve(node), node);
  });

  test('external refs (other files/urls) are left as-is by resolve', () {
    final r = RefResolver(root);
    final node = <String, dynamic>{r'$ref': 'other.yaml#/Thing'};
    expect(r.resolve(node), node); // unresolved; caller may warn
  });
}
