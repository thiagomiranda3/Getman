import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

class _FakeCollectionsDataSource implements CollectionsLocalDataSource {
  _FakeCollectionsDataSource([this.stored = const []]);
  List<CollectionNode> stored;
  List<CollectionNode>? savedList;
  List<CollectionNode>? putList;
  List<String>? deletedIds;
  bool throwOnGet = false;

  @override
  Future<List<CollectionNode>> getCollections() async {
    if (throwOnGet) throw PersistenceException('boom');
    return stored;
  }

  @override
  Future<void> saveCollections(List<CollectionNode> collections) async =>
      savedList = collections;

  @override
  Future<void> putRoots(List<CollectionNode> roots) async => putList = roots;

  @override
  Future<void> deleteRoots(Iterable<String> ids) async =>
      deletedIds = ids.toList();
}

void main() {
  test('getCollections maps each model (with children) to an entity', () async {
    final ds = _FakeCollectionsDataSource([
      CollectionNode.fromEntity(
        const CollectionNodeEntity(
          id: 'root',
          name: 'Root',
          children: [
            CollectionNodeEntity(id: 'child', name: 'Child', isFolder: false),
          ],
        ),
      ),
    ]);
    final repo = CollectionsRepositoryImpl(ds);

    final result = await repo.getCollections();
    expect(result, hasLength(1));
    expect(result.single.name, 'Root');
    expect(result.single.children.single.name, 'Child');
  });

  test(
    'saveCollections does a full keyed replace when disk state is unknown',
    () async {
      final ds = _FakeCollectionsDataSource();
      final repo = CollectionsRepositoryImpl(ds);

      // No prior getCollections → snapshot unknown → full replace.
      await repo.saveCollections(const [
        CollectionNodeEntity(id: 'a', name: 'A'),
        CollectionNodeEntity(id: 'b', name: 'B'),
      ]);

      expect(ds.savedList?.map((m) => m.id), ['a', 'b']);
      expect(ds.putList, isNull);
    },
  );

  test(
    'after a load, saveCollections rewrites only changed roots (L12 diff)',
    () async {
      final ds = _FakeCollectionsDataSource([
        CollectionNode.fromEntity(
          const CollectionNodeEntity(id: 'a', name: 'A'),
        ),
        CollectionNode.fromEntity(
          const CollectionNodeEntity(id: 'b', name: 'B'),
        ),
      ]);
      final repo = CollectionsRepositoryImpl(ds);

      await repo.getCollections(); // seeds the snapshot

      // Change only root 'b'; leave 'a' untouched.
      await repo.saveCollections(const [
        CollectionNodeEntity(id: 'a', name: 'A'),
        CollectionNodeEntity(id: 'b', name: 'B-renamed'),
      ]);

      expect(
        ds.savedList,
        isNull,
        reason: 'no full replace once disk state is known',
      );
      expect(ds.putList?.map((m) => m.id), ['b']);
      expect(ds.deletedIds ?? const [], isEmpty);
    },
  );

  test(
    'saveCollections deletes roots removed since the last persist',
    () async {
      final ds = _FakeCollectionsDataSource([
        CollectionNode.fromEntity(
          const CollectionNodeEntity(id: 'a', name: 'A'),
        ),
        CollectionNode.fromEntity(
          const CollectionNodeEntity(id: 'b', name: 'B'),
        ),
      ]);
      final repo = CollectionsRepositoryImpl(ds);

      await repo.getCollections();

      // Drop root 'b'.
      await repo.saveCollections(const [
        CollectionNodeEntity(id: 'a', name: 'A'),
      ]);

      expect(ds.deletedIds, ['b']);
      // 'a' unchanged → not re-written.
      expect(ds.putList ?? const [], isEmpty);
    },
  );

  test('translates a PersistenceException into a PersistenceFailure', () async {
    final ds = _FakeCollectionsDataSource()..throwOnGet = true;
    final repo = CollectionsRepositoryImpl(ds);

    expect(repo.getCollections(), throwsA(isA<PersistenceFailure>()));
  });
}
