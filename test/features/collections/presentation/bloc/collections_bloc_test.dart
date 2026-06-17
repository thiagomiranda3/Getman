import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
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

  CollectionsBloc build({
    Duration debounce = const Duration(milliseconds: 5),
  }) => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: debounce,
  );

  CollectionNodeEntity folder(
    String id,
    String name, {
    List<CollectionNodeEntity> children = const [],
  }) => CollectionNodeEntity(id: id, name: name, children: children);

  CollectionNodeEntity leaf(String id, String name) => CollectionNodeEntity(
    id: id,
    name: name,
    isFolder: false,
    config: HttpRequestConfigEntity(id: id),
  );

  /// Seeds the tree and waits for the (immediate) replace emit.
  Future<void> seed(
    CollectionsBloc bloc,
    List<CollectionNodeEntity> nodes,
  ) async {
    bloc.add(ReplaceCollections(nodes));
    await bloc.stream.first;
  }

  group('mutations', () {
    test('AddFolder appends a folder to the root', () async {
      final bloc = build();
      addTearDown(bloc.close);
      bloc.add(const AddFolder('Auth'));
      await bloc.stream.first;
      expect(
        bloc.state.collections.where((n) => n.name == 'Auth' && n.isFolder),
        hasLength(1),
      );
    });

    test('SaveRequestToCollection honors a caller-supplied node id', () async {
      // The save dialog pre-generates the node id so the open tab can link to
      // it immediately (otherwise the tab stays unlinked → dirty forever +
      // re-save duplicates). The bloc must use that id, not generate its own.
      final bloc = build();
      addTearDown(bloc.close);

      bloc.add(
        const SaveRequestToCollection(
          'Login',
          HttpRequestConfigEntity(id: 'cfg-1'),
          id: 'node-fixed-id',
        ),
      );
      await bloc.stream.first;

      final node = bloc.state.collections.singleWhere((n) => n.name == 'Login');
      expect(node.id, 'node-fixed-id');
      expect(node.isFolder, isFalse);
    });

    test('SaveRequestToCollection still generates an id when none given', () {
      final bloc = build();
      addTearDown(bloc.close);

      bloc.add(
        const SaveRequestToCollection(
          'Anon',
          HttpRequestConfigEntity(id: 'cfg-2'),
        ),
      );

      return expectLater(
        bloc.stream.first.then(
          (_) => bloc.state.collections.singleWhere((n) => n.name == 'Anon').id,
        ),
        completion(isNotEmpty),
      );
    });

    test(
      'UpdateNodeDescription sets and then clears a node description',
      () async {
        final bloc = build();
        addTearDown(bloc.close);
        await seed(bloc, [leaf('R', 'R')]);

        bloc.add(const UpdateNodeDescription('R', 'auth endpoint'));
        await bloc.stream.first;
        expect(
          CollectionsTreeHelper.findNode(
            bloc.state.collections,
            'R',
          )?.description,
          'auth endpoint',
        );

        bloc.add(const UpdateNodeDescription('R', ''));
        await bloc.stream.first;
        expect(
          CollectionsTreeHelper.findNode(
            bloc.state.collections,
            'R',
          )?.description,
          '',
        );
      },
    );

    test('DeleteNode removes the node from the tree', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A'), leaf('R', 'R')]);

      bloc.add(const DeleteNode('R'));
      await bloc.stream.first;

      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'R'),
        isNull,
      );
      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'A'),
        isNotNull,
      );
    });

    test('RenameNode renames in place', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A')]);

      bloc.add(const RenameNode('A', 'Renamed'));
      await bloc.stream.first;

      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'A')!.name,
        'Renamed',
      );
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

  group('saved examples', () {
    SavedExampleEntity example(String id, String name) => SavedExampleEntity(
      id: id,
      name: name,
      capturedAt: DateTime.utc(2026, 6, 14),
      config: const HttpRequestConfigEntity(
        id: 'R',
        statusCode: 200,
        responseBody: 'ok',
      ),
    );

    test('SaveExampleToNode appends to the leaf', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [leaf('R', 'R')]);

      bloc.add(SaveExampleToNode('R', example('e1', 'First')));
      await bloc.stream.first;

      final node = CollectionsTreeHelper.findNode(bloc.state.collections, 'R')!;
      expect(node.examples.map((e) => e.id), ['e1']);
      expect(node.examples.single.config.statusCode, 200);
    });

    test('SaveExampleToNode is a no-op for a missing node', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [leaf('R', 'R')]);

      bloc.add(SaveExampleToNode('nope', example('e1', 'First')));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'R')!.examples,
        isEmpty,
      );
    });

    test('DeleteExample removes the example', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [
        leaf(
          'R',
          'R',
        ).copyWith(examples: [example('e1', 'First'), example('e2', 'Second')]),
      ]);

      bloc.add(const DeleteExample('R', 'e1'));
      await bloc.stream.first;

      expect(
        CollectionsTreeHelper.findNode(
          bloc.state.collections,
          'R',
        )!.examples.map((e) => e.id),
        ['e2'],
      );
    });

    test('RenameExample renames the example', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [
        leaf('R', 'R').copyWith(examples: [example('e1', 'First')]),
      ]);

      bloc.add(const RenameExample('R', 'e1', 'Renamed'));
      await bloc.stream.first;

      expect(
        CollectionsTreeHelper.findNode(
          bloc.state.collections,
          'R',
        )!.examples.single.name,
        'Renamed',
      );
    });
  });

  group('move safety', () {
    test(
      'rejects moving a node into its own descendant (no orphaning)',
      () async {
        final bloc = build();
        addTearDown(bloc.close);
        // A contains B.
        await seed(bloc, [
          folder('A', 'A', children: [folder('B', 'B')]),
        ]);

        bloc.add(const MoveNode('A', 'B')); // would strip the whole subtree
        // The handler returns without emitting, so give the event loop a turn.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final a = CollectionsTreeHelper.findNode(bloc.state.collections, 'A');
        expect(a, isNotNull, reason: 'A must survive the rejected move');
        expect(
          CollectionsTreeHelper.findNode(bloc.state.collections, 'B'),
          isNotNull,
        );
        expect(a!.children.any((n) => n.id == 'B'), isTrue);
      },
    );

    test('rejects moving a node onto itself', () async {
      final bloc = build();
      addTearDown(bloc.close);
      await seed(bloc, [folder('A', 'A')]);

      bloc.add(const MoveNode('A', 'A'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'A'),
        isNotNull,
      );
    });
  });

  group('UpdateNodeVariables', () {
    blocTest<CollectionsBloc, CollectionsState>(
      'sets variables + secretKeys on the target folder',
      build: build,
      seed: () => CollectionsState(
        collections: [folder('f1', 'API')],
      ),
      act: (bloc) => bloc.add(
        const UpdateNodeVariables('f1', {'base': 'x'}, {'base'}),
      ),
      expect: () => [
        isA<CollectionsState>()
            .having(
              (s) => CollectionsTreeHelper.findNode(
                s.collections,
                'f1',
              )!.variables,
              'variables',
              {'base': 'x'},
            )
            .having(
              (s) => CollectionsTreeHelper.findNode(
                s.collections,
                'f1',
              )!.secretKeys,
              'secretKeys',
              {'base'},
            ),
      ],
    );

    blocTest<CollectionsBloc, CollectionsState>(
      'is a no-op for an unknown id',
      build: build,
      seed: () => CollectionsState(collections: [folder('f1', 'API')]),
      act: (bloc) =>
          bloc.add(const UpdateNodeVariables('ghost', {'a': 'b'}, {})),
      expect: () => const <CollectionsState>[],
    );
  });

  group('persistence', () {
    test('coalesces a burst of edits into a single debounced save', () async {
      final bloc = build(debounce: const Duration(milliseconds: 30));
      addTearDown(bloc.close);

      bloc
        ..add(const AddFolder('One'))
        ..add(const AddFolder('Two'))
        ..add(const AddFolder('Three'));
      await untilCalled(() => repo.saveCollections(any()));
      // Let any stray timers fire.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      verify(() => repo.saveCollections(any())).called(1);
    });

    test('close() flushes a pending debounced save', () async {
      // Long debounce so the timer can't fire before close.
      final bloc = build(debounce: const Duration(seconds: 10))
        ..add(const AddFolder('Pending'));
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
      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'I'),
        isNotNull,
      );
    });
  });
}
