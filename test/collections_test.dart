import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  late MockCollectionsRepository mockRepository;
  late GetCollectionsUseCase getCollectionsUseCase;
  late SaveCollectionsUseCase saveCollectionsUseCase;
  late CollectionsBloc collectionsBloc;

  setUp(() {
    mockRepository = MockCollectionsRepository();
    getCollectionsUseCase = GetCollectionsUseCase(mockRepository);
    saveCollectionsUseCase = SaveCollectionsUseCase(mockRepository);
    collectionsBloc = CollectionsBloc(
      getCollectionsUseCase: getCollectionsUseCase,
      saveCollectionsUseCase: saveCollectionsUseCase,
      // Keep the debounce tiny so `untilCalled(saveCollections)` resolves fast.
      saveDebounce: const Duration(milliseconds: 10),
    );
  });

  tearDown(() {
    collectionsBloc.close();
  });

  const tNode = CollectionNodeEntity(
    id: '1',
    name: 'Folder',
    isFolder: true,
  );

  test('initial state should be CollectionsState with empty list', () {
    expect(collectionsBloc.state, const CollectionsState());
  });

  test('should emit [isLoading: true, collections: [...]] when LoadCollections is added', () async {
    // Arrange
    when(() => mockRepository.getCollections()).thenAnswer((_) async => [tNode]);

    // Act
    collectionsBloc.add(const LoadCollections());

    // Assert
    await expectLater(
      collectionsBloc.stream,
      emitsInOrder([
        const CollectionsState(collections: [], isLoading: true),
        const CollectionsState(collections: [tNode], isLoading: false),
      ]),
    );
  });

  test('clears isLoading and keeps current tree when the read fails', () async {
    // Arrange
    when(() => mockRepository.getCollections())
        .thenThrow(const PersistenceFailure('corrupted box'));

    // Act
    collectionsBloc.add(const LoadCollections());

    // Assert
    await expectLater(
      collectionsBloc.stream,
      emitsInOrder([
        const CollectionsState(collections: [], isLoading: true),
        const CollectionsState(collections: [], isLoading: false),
      ]),
    );
  });

  test('should call saveCollections when AddFolder is added', () async {
    // Arrange
    when(() => mockRepository.getCollections()).thenAnswer((_) async => []);
    when(() => mockRepository.saveCollections(any())).thenAnswer((_) async => {});

    // Act
    collectionsBloc.add(const AddFolder('New Folder'));

    // Assert
    await untilCalled(() => mockRepository.saveCollections(any()));
    verify(() => mockRepository.saveCollections(any())).called(1);
  });

  group('tree mutations', () {
    const child = CollectionNodeEntity(id: 'child', name: 'Child', isFolder: true);
    const parent = CollectionNodeEntity(
      id: 'parent',
      name: 'Parent',
      isFolder: true,
      children: [child],
    );

    setUp(() async {
      when(() => mockRepository.getCollections()).thenAnswer((_) async => [parent]);
      when(() => mockRepository.saveCollections(any())).thenAnswer((_) async => {});
      collectionsBloc.add(const LoadCollections());
      await expectLater(
        collectionsBloc.stream,
        emitsThrough(predicate<CollectionsState>((s) => !s.isLoading && s.collections.isNotEmpty)),
      );
    });

    test('AddFolder appends to the root when the parent no longer exists', () async {
      collectionsBloc.add(const AddFolder('Orphan', parentId: 'ghost'));
      await untilCalled(() => mockRepository.saveCollections(any()));

      final roots = collectionsBloc.state.collections;
      expect(roots.map((n) => n.name), containsAll(['Parent', 'Orphan']));
    });

    test('MoveNode rejects a move into the node\'s own subtree', () async {
      collectionsBloc.add(const MoveNode('parent', 'child'));
      await Future<void>.delayed(Duration.zero);

      // Tree unchanged: parent still at root, child still inside it.
      final roots = collectionsBloc.state.collections;
      expect(roots.single.id, 'parent');
      expect(roots.single.children.single.id, 'child');
    });

    test('MoveNode to null re-roots the node', () async {
      collectionsBloc.add(const MoveNode('child', null));
      await untilCalled(() => mockRepository.saveCollections(any()));

      final roots = collectionsBloc.state.collections;
      expect(roots.map((n) => n.id), containsAll(['parent', 'child']));
      expect(roots.firstWhere((n) => n.id == 'parent').children, isEmpty);
    });

    test('ImportCollections appends the imported roots', () async {
      const imported = CollectionNodeEntity(id: 'imp', name: 'Imported', isFolder: true);
      collectionsBloc.add(const ImportCollections([imported]));
      await untilCalled(() => mockRepository.saveCollections(any()));

      expect(collectionsBloc.state.collections.map((n) => n.id), containsAll(['parent', 'imp']));
    });

    test('ReplaceCollections swaps the whole tree', () async {
      const replacement = CollectionNodeEntity(id: 'ws', name: 'FromDisk', isFolder: true);
      collectionsBloc.add(const ReplaceCollections([replacement]));
      await untilCalled(() => mockRepository.saveCollections(any()));

      expect(collectionsBloc.state.collections.map((n) => n.id), ['ws']);
    });
  });

  group('debounced persistence', () {
    test('coalesces a burst of edits into a single save', () async {
      when(() => mockRepository.getCollections()).thenAnswer((_) async => []);
      when(() => mockRepository.saveCollections(any())).thenAnswer((_) async {});
      final bloc = CollectionsBloc(
        getCollectionsUseCase: getCollectionsUseCase,
        saveCollectionsUseCase: saveCollectionsUseCase,
        saveDebounce: const Duration(milliseconds: 100),
      );
      addTearDown(bloc.close);

      bloc.add(const AddFolder('A'));
      bloc.add(const AddFolder('B'));
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verify(() => mockRepository.saveCollections(any())).called(1);
      expect(bloc.state.collections.map((n) => n.name), containsAll(['A', 'B']));
    });

    test('close flushes a pending save', () async {
      when(() => mockRepository.getCollections()).thenAnswer((_) async => []);
      when(() => mockRepository.saveCollections(any())).thenAnswer((_) async {});
      final bloc = CollectionsBloc(
        getCollectionsUseCase: getCollectionsUseCase,
        saveCollectionsUseCase: saveCollectionsUseCase,
        saveDebounce: const Duration(seconds: 30), // won't fire on its own in-test
      );

      bloc.add(const AddFolder('A'));
      await Future<void>.delayed(Duration.zero); // let the event emit
      verifyNever(() => mockRepository.saveCollections(any())); // still debounced
      await bloc.close(); // flush on close

      verify(() => mockRepository.saveCollections(any())).called(1);
    });
  });
}
