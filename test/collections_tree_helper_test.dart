import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';

CollectionNodeEntity folder(
  String id,
  String name, {
  List<CollectionNodeEntity> children = const [],
  bool favorite = false,
}) => CollectionNodeEntity(
  id: id,
  name: name,
  children: children,
  isFavorite: favorite,
);

CollectionNodeEntity leaf(String id, String name, {bool favorite = false}) =>
    CollectionNodeEntity(
      id: id,
      name: name,
      isFolder: false,
      config: HttpRequestConfigEntity(id: id, url: 'https://example.com/$id'),
      isFavorite: favorite,
    );

void main() {
  group('findNode', () {
    test('finds a root node', () {
      final nodes = [folder('a', 'A'), folder('b', 'B')];
      expect(CollectionsTreeHelper.findNode(nodes, 'b')?.id, 'b');
    });

    test('finds a deeply nested node', () {
      final nodes = [
        folder(
          'root',
          'Root',
          children: [
            folder('mid', 'Mid', children: [leaf('deep', 'Deep')]),
          ],
        ),
      ];
      expect(CollectionsTreeHelper.findNode(nodes, 'deep')?.name, 'Deep');
    });

    test('returns null for missing id', () {
      final nodes = [folder('a', 'A')];
      expect(CollectionsTreeHelper.findNode(nodes, 'zz'), isNull);
    });
  });

  group('sort', () {
    test(
      'orders favorites first, then folders-before-leaves, alphabetical '
      'within each tier',
      () {
        final nodes = [
          leaf('z-leaf', 'Zebra'),
          folder('b-folder', 'Beta'),
          leaf('fav-leaf', 'Alpha', favorite: true),
          folder('fav-folder', 'Gamma', favorite: true),
          folder('a-folder', 'Alpha'),
        ];
        final sorted = CollectionsTreeHelper.sort(nodes);
        // Favorites first (folders before leaves within favorites),
        // then non-favorites (folders before leaves, alphabetical).
        expect(sorted.map((n) => n.id).toList(), [
          'fav-folder',
          'fav-leaf',
          'a-folder',
          'b-folder',
          'z-leaf',
        ]);
      },
    );

    test('recurses into children', () {
      final nodes = [
        folder(
          'root',
          'Root',
          children: [
            leaf('c', 'C'),
            leaf('a', 'A'),
            leaf('b', 'B'),
          ],
        ),
      ];
      final sorted = CollectionsTreeHelper.sort(nodes);
      expect(sorted.first.children.map((n) => n.id).toList(), ['a', 'b', 'c']);
    });

    test('does not mutate input', () {
      final original = [leaf('b', 'B'), leaf('a', 'A')];
      final beforeIds = original.map((n) => n.id).toList();
      CollectionsTreeHelper.sort(original);
      expect(original.map((n) => n.id).toList(), beforeIds);
    });
  });

  group('addToParent', () {
    test('appends to named parent', () {
      final nodes = [
        folder('p', 'P', children: [leaf('x', 'X')]),
      ];
      final result = CollectionsTreeHelper.addToParent(
        nodes,
        'p',
        leaf('y', 'Y'),
      );
      expect(result.first.children.map((n) => n.id), ['x', 'y']);
    });

    test('appends to deeply nested parent', () {
      final nodes = [
        folder(
          'a',
          'A',
          children: [
            folder('b', 'B', children: []),
          ],
        ),
      ];
      final result = CollectionsTreeHelper.addToParent(
        nodes,
        'b',
        leaf('c', 'C'),
      );
      final b = result.first.children.first;
      expect(b.children.map((n) => n.id), ['c']);
    });

    test('no-op when parent id does not exist', () {
      final nodes = [folder('a', 'A')];
      final result = CollectionsTreeHelper.addToParent(
        nodes,
        'missing',
        leaf('x', 'X'),
      );
      expect(result.first.children, isEmpty);
    });
  });

  group('removeFromTree', () {
    test('removes root node', () {
      final nodes = [folder('a', 'A'), folder('b', 'B')];
      final result = CollectionsTreeHelper.removeFromTree(nodes, 'a');
      expect(result.map((n) => n.id), ['b']);
    });

    test('removes nested node', () {
      final nodes = [
        folder('a', 'A', children: [leaf('x', 'X'), leaf('y', 'Y')]),
      ];
      final result = CollectionsTreeHelper.removeFromTree(nodes, 'x');
      expect(result.first.children.map((n) => n.id), ['y']);
    });

    test('removes entire subtree when removing a folder', () {
      final nodes = [
        folder('p', 'P', children: [leaf('x', 'X')]),
      ];
      final result = CollectionsTreeHelper.removeFromTree(nodes, 'p');
      expect(result, isEmpty);
    });
  });

  group('renameInTree', () {
    test('renames matching node, deep', () {
      final nodes = [
        folder('p', 'P', children: [leaf('x', 'X')]),
      ];
      final result = CollectionsTreeHelper.renameInTree(nodes, 'x', 'NEW');
      expect(result.first.children.first.name, 'NEW');
    });

    test('no-op when id missing', () {
      final nodes = [folder('p', 'P')];
      final result = CollectionsTreeHelper.renameInTree(nodes, 'zz', 'X');
      expect(result, equals(nodes));
    });
  });

  group('toggleFavoriteInTree', () {
    test('toggles twice is a no-op', () {
      final nodes = [leaf('x', 'X')];
      final toggledOnce = CollectionsTreeHelper.toggleFavoriteInTree(
        nodes,
        'x',
      );
      final toggledTwice = CollectionsTreeHelper.toggleFavoriteInTree(
        toggledOnce,
        'x',
      );
      expect(toggledOnce.first.isFavorite, true);
      expect(toggledTwice.first.isFavorite, false);
    });
  });

  group('updateConfigInTree', () {
    test('replaces config on the target leaf', () {
      final nodes = [leaf('x', 'X')];
      const newConfig = HttpRequestConfigEntity(
        id: 'x',
        method: 'POST',
        url: 'https://new',
      );
      final result = CollectionsTreeHelper.updateConfigInTree(
        nodes,
        'x',
        newConfig,
      );
      expect(result.first.config?.url, 'https://new');
      expect(result.first.config?.method, 'POST');
    });
  });

  group('saved examples', () {
    SavedExampleEntity example(String id, String name) => SavedExampleEntity(
      id: id,
      name: name,
      capturedAt: DateTime.utc(2026, 6, 14),
      config: const HttpRequestConfigEntity(
        id: 'x',
        responseBody: '{"ok":true}',
        statusCode: 200,
      ),
    );

    test('addExampleToNode appends to the target leaf (newest last)', () {
      final nodes = [leaf('x', 'X')];
      final result = CollectionsTreeHelper.addExampleToNode(
        nodes,
        'x',
        example('e1', 'First'),
      );
      expect(result.first.examples.map((e) => e.id), ['e1']);
      // The carried response snapshot survives.
      expect(result.first.examples.first.config.statusCode, 200);
      expect(result.first.examples.first.config.responseBody, '{"ok":true}');
    });

    test('addExampleToNode does not mutate the input list', () {
      final nodes = [leaf('x', 'X')];
      CollectionsTreeHelper.addExampleToNode(
        nodes,
        'x',
        example('e1', 'First'),
      );
      expect(nodes.first.examples, isEmpty);
    });

    test('addExampleToNode is a no-op for a missing id', () {
      final nodes = [leaf('x', 'X')];
      final result = CollectionsTreeHelper.addExampleToNode(
        nodes,
        'nope',
        example('e1', 'First'),
      );
      expect(result.first.examples, isEmpty);
    });

    test('removeExampleFromNode drops only the matching example', () {
      final nodes = [
        leaf(
          'x',
          'X',
        ).copyWith(examples: [example('e1', 'First'), example('e2', 'Second')]),
      ];
      final result = CollectionsTreeHelper.removeExampleFromNode(
        nodes,
        'x',
        'e1',
      );
      expect(result.first.examples.map((e) => e.id), ['e2']);
    });

    test('renameExampleInNode renames only the matching example', () {
      final nodes = [
        leaf(
          'x',
          'X',
        ).copyWith(examples: [example('e1', 'First'), example('e2', 'Second')]),
      ];
      final result = CollectionsTreeHelper.renameExampleInNode(
        nodes,
        'x',
        'e2',
        'Renamed',
      );
      expect(
        result.first.examples.firstWhere((e) => e.id == 'e2').name,
        'Renamed',
      );
      expect(
        result.first.examples.firstWhere((e) => e.id == 'e1').name,
        'First',
      );
    });

    test('examples on a nested leaf are reachable', () {
      final nodes = [
        folder('root', 'Root', children: [leaf('deep', 'Deep')]),
      ];
      final result = CollectionsTreeHelper.addExampleToNode(
        nodes,
        'deep',
        example('e1', 'First'),
      );
      final deep = CollectionsTreeHelper.findNode(result, 'deep');
      expect(deep?.examples.map((e) => e.id), ['e1']);
    });

    test('sort leaves examples untouched', () {
      final nodes = [
        leaf('b', 'B').copyWith(examples: [example('e1', 'First')]),
        leaf('a', 'A'),
      ];
      final sorted = CollectionsTreeHelper.sort(nodes);
      expect(sorted.firstWhere((n) => n.id == 'b').examples.map((e) => e.id), [
        'e1',
      ]);
    });
  });
}
