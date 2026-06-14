import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc build({Duration debounce = const Duration(milliseconds: 5)}) =>
      CollectionsBloc(
        getCollectionsUseCase: GetCollectionsUseCase(repo),
        saveCollectionsUseCase: SaveCollectionsUseCase(repo),
        saveDebounce: debounce,
      );

  CollectionNodeEntity folder(String id, String name, {List<CollectionNodeEntity> children = const []}) =>
      CollectionNodeEntity(id: id, name: name, isFolder: true, children: children);

  CollectionNodeEntity leaf(String id, String name) => CollectionNodeEntity(
        id: id,
        name: name,
        isFolder: false,
        config: HttpRequestConfigEntity(id: id),
      );

  /// Seeds the tree and waits for the (immediate) replace emit.
  Future<void> seed(CollectionsBloc bloc, List<CollectionNodeEntity> nodes) async {
    bloc.add(ReplaceCollections(nodes));
    await bloc.stream.first;
  }

  group('mutations', () {
    test('AddFolder appends a folder to the root', () async {
      final bloc = build();
      addTearDown(bloc.close);
      bloc.add(const AddFolder('Auth'));
      await bloc.stream.first;
      expect(bloc.state.collections.where((n) => n.name == 'Auth' && n.isFolder), hasLength(1));
    });

    test('DeleteNode removes the node from the tree', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A'), leaf('R', 'R')]);

      bloc.add(const DeleteNode('R'));
      await bloc.stream.first;

      expect(CollectionsTreeHelper.findNode(bloc.state.collections, 'R'), isNull);
      expect(CollectionsTreeHelper.findNode(bloc.state.collections, 'A'), isNotNull);
    });

    test('RenameNode renames in place', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A')]);

      bloc.add(const RenameNode('A', 'Renamed'));
      await bloc.stream.first;

      expect(CollectionsTreeHelper.findNode(bloc.state.collections, 'A')!.name, 'Renamed');
    });

    test('MoveNode relocates a leaf into a folder', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A'), leaf('R', 'R')]);

      bloc.add(const MoveNode('R', 'A'));
      await bloc.stream.first;

      // No longer at root, now under A.
      expect(bloc.state.collections.any((n) => n.id == 'R'), isFalse);
      final a = CollectionsTreeHelper.findNode(bloc.state.collections, 'A')!;
      expect(a.children.any((n) => n.id == 'R'), isTrue);
    });
  });

  group('move safety', () {
    test('rejects moving a node into its own descendant (no orphaning)', () async {
      final bloc = build();
      addTearDown(bloc.close);
      // A contains B.
      await seed(bloc, [folder('A', 'A', children: [folder('B', 'B')])]);

      bloc.add(const MoveNode('A', 'B')); // would strip the whole subtree
      // The handler returns without emitting, so give the event loop a turn.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final a = CollectionsTreeHelper.findNode(bloc.state.collections, 'A');
      expect(a, isNotNull, reason: 'A must survive the rejected move');
      expect(CollectionsTreeHelper.findNode(bloc.state.collections, 'B'), isNotNull);
      expect(a!.children.any((n) => n.id == 'B'), isTrue);
    });

    test('rejects moving a node onto itself', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A')]);

      bloc.add(const MoveNode('A', 'A'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(CollectionsTreeHelper.findNode(bloc.state.collections, 'A'), isNotNull);
    });
  });

  group('persistence', () {
    test('coalesces a burst of edits into a single debounced save', () async {
      final bloc = build(debounce: const Duration(milliseconds: 30));
      addTearDown(bloc.close);

      bloc.add(const AddFolder('One'));
      bloc.add(const AddFolder('Two'));
      bloc.add(const AddFolder('Three'));
      await untilCalled(() => repo.saveCollections(any()));
      // Let any stray timers fire.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      verify(() => repo.saveCollections(any())).called(1);
    });

    test('close() flushes a pending debounced save', () async {
      // Long debounce so the timer can't fire before close.
      final bloc = build(debounce: const Duration(seconds: 10));
      bloc.add(const AddFolder('Pending'));
      await bloc.stream.first; // ensure the edit landed

      await bloc.close();

      verify(() => repo.saveCollections(any())).called(1);
    });

    test('ImportCollections persists immediately (no debounce wait)', () async {
      final bloc = build(debounce: const Duration(seconds: 10));
      addTearDown(bloc.close);

      bloc.add(ImportCollections([folder('I', 'Imported')]));
      await untilCalled(() => repo.saveCollections(any()));

      verify(() => repo.saveCollections(any())).called(1);
      expect(CollectionsTreeHelper.findNode(bloc.state.collections, 'I'), isNotNull);
    });
  });
}
