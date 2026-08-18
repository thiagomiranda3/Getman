import 'dart:convert';

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
      // The matched container IS in the auto-expand set (overlapping
      // matchedPaths): excluding it left it collapsed, hiding the deeper
      // match while the counter still announced it.
      expect(r.ancestorPaths, {r'$.x'});
      expect(r.matchCount, 2);
      expect(r.truncated, isFalse);
    });

    test('a match nested under a MATCHED container is auto-expanded into '
        'view (every match visible, not just counted)', () {
      final r = filterJsonTree(
        data: {
          'data': {
            'user': {
              'profile': {'user_id': 42, 'email': 'a@b.c'},
            },
            'count': 7,
          },
        },
        query: 'user',
      );
      expect(r.matchedPaths, {r'$.data.user', r'$.data.user.profile.user_id'});
      expect(r.matchCount, 2);
      expect(r.truncated, isFalse);
      // The full chain to the deep match auto-expands — INCLUDING the
      // matched container '$.data.user' itself.
      expect(r.ancestorPaths, {
        r'$.data',
        r'$.data.user',
        r'$.data.user.profile',
      });
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

  group('kTreeMaxDepth depth guard (I10)', () {
    // A ~400KB `[[[[…]]]]` body: under the 512 KiB TREE gate, jsonDecode
    // survives it, but an unguarded recursive walk overflowed the stack.
    final deep = jsonDecode('${'[' * 200000}1${']' * 200000}');

    test('filterJsonTree walks a 200k-deep body without overflowing and '
        'flags the skipped subtree as truncated', () {
      final r = filterJsonTree(data: deep, query: '1');
      // The only matchable value (the scalar 1) sits ~200k levels down —
      // past the cap, so it is not matched; the skip is surfaced instead.
      expect(r.matchCount, 0);
      expect(r.matchedPaths, isEmpty);
      expect(r.truncated, isTrue);
    });

    test('planExpandAll walks a 200k-deep body without overflowing and '
        'plans only renderable containers', () {
      final plan = planExpandAll(data: deep);
      // One container per renderable depth 0..kTreeMaxDepth-1; nodes past
      // the cap are neither counted toward maxNodes nor expandable.
      expect(plan.containerPaths.length, kTreeMaxDepth);
      expect(plan.limitedToDepth, isFalse);
    });

    test('filterJsonTree maxDepth override: a match under the cap is found, '
        'past the cap it is skipped and flagged', () {
      final data = jsonDecode('${'[' * 10}"needle"${']' * 10}');
      final unbounded = filterJsonTree(data: data, query: 'needle');
      expect(unbounded.matchCount, 1);
      expect(unbounded.truncated, isFalse);

      final capped = filterJsonTree(
        data: data,
        query: 'needle',
        maxDepth: 4,
      );
      expect(capped.matchCount, 0);
      expect(capped.matchedPaths, isEmpty);
      expect(capped.truncated, isTrue);
    });

    test('planExpandAll maxDepth override caps collected containers', () {
      final data = jsonDecode('${'[' * 10}"needle"${']' * 10}');
      final plan = planExpandAll(data: data, maxDepth: 4);
      expect(plan.containerPaths, {
        r'$[0]',
        r'$[0][0]',
        r'$[0][0][0]',
        r'$[0][0][0][0]',
      });
      expect(plan.limitedToDepth, isFalse);
    });

    test('an empty container sitting exactly at the cap boundary does not '
        'flag truncation (nothing was skipped)', () {
      final r = filterJsonTree(
        data: {
          'a': {
            'b': <String, Object?>{},
          },
        },
        query: 'zzz',
        maxDepth: 2,
      );
      expect(r.truncated, isFalse);
    });
  });
}
