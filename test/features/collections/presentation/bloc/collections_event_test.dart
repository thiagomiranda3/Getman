// Equality/props tests for every CollectionsEvent class: identical instances
// are equal, and each declared field participates in equality (a difference
// in any single field makes the events unequal) — guarding against a field
// silently dropping out of props.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

void main() {
  const config = HttpRequestConfigEntity(id: 'cfg-1');
  const otherConfig = HttpRequestConfigEntity(id: 'cfg-2', method: 'POST');
  const node = CollectionNodeEntity(id: 'n1', name: 'Node');
  const otherNode = CollectionNodeEntity(id: 'n2', name: 'Other');
  final example = SavedExampleEntity(
    id: 'e1',
    name: 'Example',
    capturedAt: DateTime.utc(2026, 7, 26),
    config: config,
  );
  final otherExample = SavedExampleEntity(
    id: 'e2',
    name: 'Other example',
    capturedAt: DateTime.utc(2026, 7, 26),
    config: config,
  );

  group('LoadCollections', () {
    test('instances are equal', () {
      expect(const LoadCollections(), const LoadCollections());
      expect(const LoadCollections().props, isEmpty);
    });
  });

  group('AddFolder', () {
    test('equal for identical fields', () {
      expect(
        const AddFolder('Auth', parentId: 'p1'),
        const AddFolder('Auth', parentId: 'p1'),
      );
    });

    test('every field participates in equality', () {
      const base = AddFolder('Auth', parentId: 'p1');
      expect(base, isNot(const AddFolder('Other', parentId: 'p1')));
      expect(base, isNot(const AddFolder('Auth', parentId: 'p2')));
      expect(base, isNot(const AddFolder('Auth')));
    });
  });

  group('SaveRequestToCollection', () {
    test('equal for identical fields', () {
      expect(
        const SaveRequestToCollection('Login', config, parentId: 'p', id: 'i'),
        const SaveRequestToCollection('Login', config, parentId: 'p', id: 'i'),
      );
    });

    test('every field participates in equality', () {
      const base = SaveRequestToCollection(
        'Login',
        config,
        parentId: 'p',
        id: 'i',
      );
      expect(
        base,
        isNot(
          const SaveRequestToCollection('X', config, parentId: 'p', id: 'i'),
        ),
      );
      expect(
        base,
        isNot(
          const SaveRequestToCollection(
            'Login',
            otherConfig,
            parentId: 'p',
            id: 'i',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const SaveRequestToCollection(
            'Login',
            config,
            parentId: 'q',
            id: 'i',
          ),
        ),
      );
      expect(
        base,
        isNot(
          const SaveRequestToCollection(
            'Login',
            config,
            parentId: 'p',
            id: 'j',
          ),
        ),
      );
    });
  });

  group('UpdateNodeRequest', () {
    test('equal for identical fields', () {
      expect(
        const UpdateNodeRequest('n1', config),
        const UpdateNodeRequest('n1', config),
      );
    });

    test('every field participates in equality', () {
      const base = UpdateNodeRequest('n1', config);
      expect(base, isNot(const UpdateNodeRequest('n2', config)));
      expect(base, isNot(const UpdateNodeRequest('n1', otherConfig)));
    });
  });

  group('DeleteNode', () {
    test('id participates in equality', () {
      expect(const DeleteNode('a'), const DeleteNode('a'));
      expect(const DeleteNode('a'), isNot(const DeleteNode('b')));
    });
  });

  group('RenameNode', () {
    test('every field participates in equality', () {
      expect(const RenameNode('a', 'New'), const RenameNode('a', 'New'));
      expect(const RenameNode('a', 'New'), isNot(const RenameNode('b', 'New')));
      expect(
        const RenameNode('a', 'New'),
        isNot(const RenameNode('a', 'Other')),
      );
    });
  });

  group('UpdateNodeDescription', () {
    test('every field participates in equality', () {
      expect(
        const UpdateNodeDescription('a', 'notes'),
        const UpdateNodeDescription('a', 'notes'),
      );
      expect(
        const UpdateNodeDescription('a', 'notes'),
        isNot(const UpdateNodeDescription('b', 'notes')),
      );
      expect(
        const UpdateNodeDescription('a', 'notes'),
        isNot(const UpdateNodeDescription('a', '')),
      );
    });
  });

  group('UpdateNodeVariables', () {
    test('equal for identical fields', () {
      expect(
        const UpdateNodeVariables('a', {'k': 'v'}, {'k'}),
        const UpdateNodeVariables('a', {'k': 'v'}, {'k'}),
      );
    });

    test('every field participates in equality', () {
      const base = UpdateNodeVariables('a', {'k': 'v'}, {'k'});
      expect(base, isNot(const UpdateNodeVariables('b', {'k': 'v'}, {'k'})));
      expect(base, isNot(const UpdateNodeVariables('a', {'k': 'w'}, {'k'})));
      expect(base, isNot(const UpdateNodeVariables('a', {'k': 'v'}, {})));
    });
  });

  group('ToggleFavorite', () {
    test('id participates in equality', () {
      expect(const ToggleFavorite('a'), const ToggleFavorite('a'));
      expect(const ToggleFavorite('a'), isNot(const ToggleFavorite('b')));
    });
  });

  group('SaveExampleToNode', () {
    test('every field participates in equality', () {
      expect(
        SaveExampleToNode('n1', example),
        SaveExampleToNode('n1', example),
      );
      expect(
        SaveExampleToNode('n1', example),
        isNot(SaveExampleToNode('n2', example)),
      );
      expect(
        SaveExampleToNode('n1', example),
        isNot(SaveExampleToNode('n1', otherExample)),
      );
    });
  });

  group('DeleteExample', () {
    test('every field participates in equality', () {
      expect(const DeleteExample('n', 'e'), const DeleteExample('n', 'e'));
      expect(
        const DeleteExample('n', 'e'),
        isNot(const DeleteExample('m', 'e')),
      );
      expect(
        const DeleteExample('n', 'e'),
        isNot(const DeleteExample('n', 'f')),
      );
    });
  });

  group('RenameExample', () {
    test('every field participates in equality', () {
      const base = RenameExample('n', 'e', 'New');
      expect(base, const RenameExample('n', 'e', 'New'));
      expect(base, isNot(const RenameExample('m', 'e', 'New')));
      expect(base, isNot(const RenameExample('n', 'f', 'New')));
      expect(base, isNot(const RenameExample('n', 'e', 'Other')));
    });
  });

  group('MoveNode', () {
    test('every field participates in equality', () {
      expect(const MoveNode('n', 'p'), const MoveNode('n', 'p'));
      expect(const MoveNode('n', 'p'), isNot(const MoveNode('m', 'p')));
      expect(const MoveNode('n', 'p'), isNot(const MoveNode('n', null)));
    });
  });

  group('ImportCollections', () {
    test('rootNodes participate in equality', () {
      expect(
        const ImportCollections([node]),
        const ImportCollections([node]),
      );
      expect(
        const ImportCollections([node]),
        isNot(const ImportCollections([otherNode])),
      );
    });
  });

  group('ReplaceCollections', () {
    test('rootNodes participate in equality', () {
      expect(
        const ReplaceCollections([node]),
        const ReplaceCollections([node]),
      );
      expect(
        const ReplaceCollections([node]),
        isNot(const ReplaceCollections([])),
      );
    });

    test('is a distinct event type from ImportCollections', () {
      expect(
        const ReplaceCollections([node]),
        isNot(const ImportCollections([node])),
      );
    });
  });

  group('RestoreNodeSubtree', () {
    test('equal for identical fields', () {
      expect(
        const RestoreNodeSubtree(
          node: node,
          ancestorIds: ['a'],
          siblingIndex: 1,
        ),
        const RestoreNodeSubtree(
          node: node,
          ancestorIds: ['a'],
          siblingIndex: 1,
        ),
      );
    });

    test('every field participates in equality', () {
      const base = RestoreNodeSubtree(
        node: node,
        ancestorIds: ['a'],
        siblingIndex: 1,
      );
      expect(
        base,
        isNot(
          const RestoreNodeSubtree(
            node: otherNode,
            ancestorIds: ['a'],
            siblingIndex: 1,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const RestoreNodeSubtree(
            node: node,
            ancestorIds: ['b'],
            siblingIndex: 1,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const RestoreNodeSubtree(
            node: node,
            ancestorIds: ['a'],
            siblingIndex: 2,
          ),
        ),
      );
    });
  });

  group('RestoreExample', () {
    test('equal for identical fields', () {
      expect(
        RestoreExample(nodeId: 'n', example: example, exampleIndex: 0),
        RestoreExample(nodeId: 'n', example: example, exampleIndex: 0),
      );
    });

    test('every field participates in equality', () {
      final base = RestoreExample(
        nodeId: 'n',
        example: example,
        exampleIndex: 0,
      );
      expect(
        base,
        isNot(RestoreExample(nodeId: 'm', example: example, exampleIndex: 0)),
      );
      expect(
        base,
        isNot(
          RestoreExample(nodeId: 'n', example: otherExample, exampleIndex: 0),
        ),
      );
      expect(
        base,
        isNot(RestoreExample(nodeId: 'n', example: example, exampleIndex: 1)),
      );
    });
  });
}
