import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/openapi/import_selection.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

CollectionNodeEntity get _root => const CollectionNodeEntity(
  id: 'root',
  name: 'API',
  children: [
    CollectionNodeEntity(
      id: 'f1',
      name: 'Users',
      children: [
        CollectionNodeEntity(
          id: 'l1',
          name: 'a',
          isFolder: false,
          config: HttpRequestConfigEntity(id: 'c1'),
        ),
        CollectionNodeEntity(
          id: 'l2',
          name: 'b',
          isFolder: false,
          config: HttpRequestConfigEntity(id: 'c2'),
        ),
      ],
    ),
    CollectionNodeEntity(
      id: 'f2',
      name: 'Pets',
      children: [
        CollectionNodeEntity(
          id: 'l3',
          name: 'c',
          isFolder: false,
          config: HttpRequestConfigEntity(id: 'c3'),
        ),
      ],
    ),
  ],
);

void main() {
  test('collectLeafIds returns every request leaf id', () {
    expect(collectLeafIds(_root), {'l1', 'l2', 'l3'});
  });

  test('applySelection keeps only selected leaves and drops empty folders', () {
    final full = ImportResult(root: _root);
    final pruned = applySelection(full, {'l1'});
    expect(pruned.root.children, hasLength(1)); // only Users
    final users = pruned.root.children.single;
    expect(users.name, 'Users');
    expect(users.children.single.id, 'l1'); // l2 dropped, Pets folder dropped
  });

  test('applySelection preserves environments and warnings', () {
    final full = ImportResult(
      root: _root,
      warnings: const ['w'],
    );
    final pruned = applySelection(full, {'l3'});
    expect(pruned.warnings, ['w']);
  });
}
