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

  group('node budget (fan-out guard)', () {
    /// 10 refs per level x [levels] levels: full expansion is 10^levels
    /// nodes — the cycle guard alone cannot stop this (sibling refs are
    /// re-expanded on every path).
    Map<String, dynamic> fanOutRoot(int levels) {
      final schemas = <String, dynamic>{};
      for (var level = 0; level < levels; level++) {
        schemas['L$level'] = {
          'type': 'object',
          'properties': {
            for (var i = 0; i < 10; i++)
              'p$i': level == levels - 1
                  ? {'type': 'string'}
                  : {r'$ref': '#/components/schemas/L${level + 1}'},
          },
        };
      }
      return {
        'components': {'schemas': schemas},
      };
    }

    test('a tiny budget stops expansion, flags exhaustion, and returns '
        'unexpanded refs instead of hanging', () {
      final r = RefResolver(fanOutRoot(10), nodeBudget: 200);
      final resolved = r.deepResolve(<String, dynamic>{
        r'$ref': '#/components/schemas/L0',
      });
      expect(resolved, isA<Map<String, dynamic>>());
      expect(r.nodeBudgetExhausted, isTrue);
      // Somewhere in the truncated tree an internal ref survives as-is.
      var foundRawRef = false;
      void scan(Object? node) {
        if (node is Map) {
          if (node[r'$ref'] is String) foundRawRef = true;
          node.values.forEach(scan);
        } else if (node is List) {
          node.forEach(scan);
        }
      }

      scan(resolved);
      expect(foundRawRef, isTrue);
    });

    test('a billion-laughs spec (10^10 full expansion) completes under the '
        'default budget', () {
      // Regression: without the budget this test hangs the isolate.
      final r = RefResolver(fanOutRoot(10));
      final resolved = r.deepResolve(<String, dynamic>{
        r'$ref': '#/components/schemas/L0',
      });
      expect(resolved, isA<Map<String, dynamic>>());
      expect(r.nodeBudgetExhausted, isTrue);
    });

    test('normal specs resolve identically and never exhaust the budget', () {
      final r = RefResolver(root);
      final resolved = r.deepResolve(<String, dynamic>{
        r'$ref': '#/definitions/Pet',
      });
      expect(resolved, {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      });
      expect(r.nodeBudgetExhausted, isFalse);
    });
  });
}
