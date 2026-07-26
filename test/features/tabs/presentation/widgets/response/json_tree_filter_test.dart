import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_filter.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_view.dart';

void main() {
  group('filterJsonTree', () {
    final data = {
      'user': {
        'name': 'Ada Lovelace',
        'address': {'zip': '90210'},
      },
      'items': [
        {'sku': 'A-1'},
        {'sku': 'B-2'},
      ],
      'active': true,
    };

    test('empty query returns the empty result', () {
      expect(filterJsonTree(data: data, query: ''), JsonTreeFilterResult.empty);
      expect(
        filterJsonTree(data: data, query: '   '),
        JsonTreeFilterResult.empty,
      );
    });

    test('matches key names case-insensitively with ancestors', () {
      final r = filterJsonTree(data: data, query: 'ZIP');
      expect(r.matchedPaths, {r'$.user.address.zip'});
      expect(r.ancestorPaths, {r'$.user', r'$.user.address'});
      expect(r.matchCount, 1);
      expect(r.truncated, isFalse);
    });

    test('matches primitive value strings', () {
      final r = filterJsonTree(data: data, query: 'lovelace');
      expect(r.matchedPaths, {r'$.user.name'});
      expect(r.ancestorPaths, {r'$.user'});
    });

    test('matches non-string primitives via their string form', () {
      final r = filterJsonTree(data: data, query: 'true');
      expect(r.matchedPaths, contains(r'$.active'));
    });

    test(
      'container nodes match on key name but not on their contents blob',
      () {
        final r = filterJsonTree(data: data, query: 'address');
        expect(r.matchedPaths, {r'$.user.address'});
        expect(r.ancestorPaths, {r'$.user'});
      },
    );

    test('multiple matches under arrays use index paths', () {
      final r = filterJsonTree(data: data, query: 'sku');
      expect(r.matchedPaths, {r'$.items[0].sku', r'$.items[1].sku'});
      expect(r.ancestorPaths, {r'$.items', r'$.items[0]', r'$.items[1]'});
      expect(r.matchCount, 2);
    });

    test('reveal cap truncates but still counts every match', () {
      final big = {
        for (var i = 0; i < 600; i++) 'match_key_$i': i,
      };
      final r = filterJsonTree(data: big, query: 'match_key');
      expect(r.matchCount, 600);
      expect(r.truncated, isTrue);
      expect(
        r.matchedPaths.length + r.ancestorPaths.length,
        lessThanOrEqualTo(kTreeFilterMaxRevealedNodes),
      );
      expect(r.matchedPaths.length, kTreeFilterMaxRevealedNodes);
    });

    test('scalar root matches on its value', () {
      final r = filterJsonTree(data: 'hello world', query: 'world');
      expect(r.matchedPaths, {r'$'});
      expect(r.matchCount, 1);
    });

    test('a matched container that is also an ancestor of a deeper match is '
        'not double-budgeted against the cap', () {
      // '$.x' matches the query itself AND is the ancestor of '$.x.x_y',
      // which also matches. True distinct revealed nodes = 2, which must fit
      // exactly at maxRevealed: 2 without a spurious truncation.
      final r = filterJsonTree(
        data: {
          'x': {'x_y': 1},
        },
        query: 'x',
        maxRevealed: 2,
      );
      expect(r.matchedPaths, {r'$.x', r'$.x.x_y'});
      expect(r.ancestorPaths, isEmpty);
      expect(r.matchCount, 2);
      expect(r.truncated, isFalse);
    });
  });

  group('planExpandAll', () {
    test('small tree: every container path, no depth limit', () {
      final data = {
        'a': {
          'b': {'c': 1},
        },
        'list': [1, 2],
      };
      final plan = planExpandAll(data: data);
      expect(plan.limitedToDepth, isFalse);
      expect(plan.containerPaths, {r'$.a', r'$.a.b', r'$.list'});
    });

    test('over-maxNodes tree: containers only above the depth cap', () {
      final data = {
        'deep': {
          'l1': {
            'l2': {
              'l3': {'l4': 'leaf'},
            },
          },
        },
        'bulk': {for (var i = 0; i < 2100; i++) 'k$i': i},
      };
      final plan = planExpandAll(data: data);
      expect(plan.limitedToDepth, isTrue);
      // depth 0..2 containers are expanded; depth 3+ is not.
      expect(plan.containerPaths, contains(r'$.deep'));
      expect(plan.containerPaths, contains(r'$.deep.l1'));
      expect(plan.containerPaths, contains(r'$.deep.l1.l2'));
      expect(plan.containerPaths, isNot(contains(r'$.deep.l1.l2.l3')));
    });
  });

  group('flattenVisibleJsonTree with a filter', () {
    final data = {
      'user': {
        'name': 'Ada',
        'address': {'zip': '90210'},
      },
      'other': {'flag': true},
    };

    test('keeps matches, their ancestors, and nothing else', () {
      final filter = filterJsonTree(data: data, query: 'zip');
      final nodes = flattenVisibleJsonTree(
        data: data,
        expanded: {r'$.user', r'$.user.address', r'$.other'},
        filter: filter,
      );
      expect(
        nodes.map((n) => n.path).toList(),
        [r'$.user', r'$.user.address', r'$.user.address.zip'],
      );
    });

    test('descendants of a matched container stay visible when expanded', () {
      final filter = filterJsonTree(data: data, query: 'address');
      final nodes = flattenVisibleJsonTree(
        data: data,
        expanded: {r'$.user', r'$.user.address'},
        filter: filter,
      );
      expect(
        nodes.map((n) => n.path).toList(),
        [r'$.user', r'$.user.address', r'$.user.address.zip'],
      );
    });

    test('null filter behaves exactly as before', () {
      final nodes = flattenVisibleJsonTree(
        data: data,
        expanded: <String>{},
      );
      expect(nodes.map((n) => n.path).toList(), [r'$.user', r'$.other']);
    });
  });

  group('filterJsonTree edge shapes', () {
    test('top-level list roots match by index path', () {
      final r = filterJsonTree(data: ['apple', 'banana'], query: 'ban');
      expect(r.matchedPaths, {r'$[1]'});
      expect(r.ancestorPaths, isEmpty);
      expect(r.matchCount, 1);
    });

    test('nested match under a top-level list reveals the list ancestors', () {
      final r = filterJsonTree(
        data: [
          {'sku': 'A-1'},
        ],
        query: 'sku',
      );
      expect(r.matchedPaths, {r'$[0].sku'});
      expect(r.ancestorPaths, {r'$[0]'});
    });

    test('scalar root without a match yields the empty sets', () {
      final r = filterJsonTree(data: 'hello', query: 'nope');
      expect(r.matchedPaths, isEmpty);
      expect(r.ancestorPaths, isEmpty);
      expect(r.matchCount, 0);
      expect(r.truncated, isFalse);
    });
  });

  group('planExpandAll edge shapes', () {
    test('scalar data plans no containers', () {
      final plan = planExpandAll(data: 'hello');
      expect(plan.containerPaths, isEmpty);
      expect(plan.limitedToDepth, isFalse);
    });

    test('top-level list containers are planned by index path', () {
      final plan = planExpandAll(
        data: [
          [1, 2],
          {'a': 3},
          'scalar',
        ],
      );
      expect(plan.containerPaths, {r'$[0]', r'$[1]'});
      expect(plan.limitedToDepth, isFalse);
    });
  });
}
