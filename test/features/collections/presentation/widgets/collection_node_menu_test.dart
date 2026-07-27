// Widget tests for CollectionNodeMenu (the row's trailing "⋮" menu) and the
// shared right-click entry point showCollectionNodeMenuAt: which entries show
// for folders vs requests, and that each selection routes to the right
// CollectionsBloc event / dialog / snackbar (favorite, rename, describe,
// variables, add subfolder, export, export docs, delete with UNDO).

import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_menu.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockEnvironmentsBloc
    extends MockBloc<EnvironmentsEvent, EnvironmentsState>
    implements EnvironmentsBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

const _folderNode = CollectionNodeEntity(id: 'f1', name: 'My Folder');

const _favoriteFolderNode = CollectionNodeEntity(
  id: 'f2',
  name: 'Starred',
  isFavorite: true,
);

const _requestNode = CollectionNodeEntity(
  id: 'r1',
  name: 'My Request',
  isFolder: false,
  config: HttpRequestConfigEntity(id: 'r1', url: 'https://example.com'),
);

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
  });

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc buildBloc() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  /// Hosts [child] under all the blocs the menu actions may reach
  /// (CollectionsBloc for events, Environments/Settings for the API-docs
  /// export dialog).
  Widget host(CollectionsBloc bloc, Widget child) {
    final environments = MockEnvironmentsBloc();
    whenListen(
      environments,
      const Stream<EnvironmentsState>.empty(),
      initialState: const EnvironmentsState(),
    );
    final settings = MockSettingsBloc();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: const SettingsState(settings: SettingsEntity()),
    );
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<CollectionsBloc>.value(value: bloc),
            BlocProvider<EnvironmentsBloc>.value(value: environments),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: child,
        ),
      ),
    );
  }

  /// Pumps the trailing "⋮" menu button for [node] and opens the menu.
  Future<CollectionsBloc> openMenu(
    WidgetTester tester,
    CollectionNodeEntity node, {
    List<CollectionNodeEntity>? seedTree,
  }) async {
    final bloc = buildBloc();
    if (seedTree != null) {
      bloc.add(ReplaceCollections(seedTree));
      await bloc.stream.first;
    }
    await tester.pumpWidget(host(bloc, CollectionNodeMenu(node: node)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('node_menu_${node.id}')));
    await tester.pumpAndSettle();
    return bloc;
  }

  group('menu entries', () {
    testWidgets('folder menu shows all folder entries', (tester) async {
      final bloc = await openMenu(tester, _folderNode);
      addTearDown(bloc.close);

      expect(find.text('FAVORITE'), findsOneWidget);
      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text('EDIT DESCRIPTION'), findsOneWidget);
      expect(find.text('VARIABLES'), findsOneWidget);
      expect(find.text('ADD SUBFOLDER'), findsOneWidget);
      expect(find.text('EXPORT TO POSTMAN'), findsOneWidget);
      expect(find.text('EXPORT AS API DOCS…'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });

    testWidgets('favorite folder shows UNFAVORITE instead of FAVORITE', (
      tester,
    ) async {
      final bloc = await openMenu(tester, _favoriteFolderNode);
      addTearDown(bloc.close);

      expect(find.text('UNFAVORITE'), findsOneWidget);
      expect(find.text('FAVORITE'), findsNothing);
    });

    testWidgets('request menu hides folder-only entries', (tester) async {
      final bloc = await openMenu(tester, _requestNode);
      addTearDown(bloc.close);

      expect(find.text('FAVORITE'), findsNothing);
      expect(find.text('VARIABLES'), findsNothing);
      expect(find.text('ADD SUBFOLDER'), findsNothing);
      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text('EXPORT TO POSTMAN'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('FAVORITE dispatches ToggleFavorite and shows a snackbar', (
      tester,
    ) async {
      final bloc = await openMenu(
        tester,
        _folderNode,
        seedTree: [_folderNode],
      );
      addTearDown(bloc.close);

      await tester.tap(find.text('FAVORITE'));
      await tester.pumpAndSettle();

      expect(
        CollectionsTreeHelper.findNode(
          bloc.state.collections,
          'f1',
        )!.isFavorite,
        isTrue,
      );
      expect(find.text('Added to favorites'), findsOneWidget);
    });

    testWidgets(
      'UNFAVORITE un-stars the folder and shows the removal snackbar',
      (tester) async {
        final bloc = await openMenu(
          tester,
          _favoriteFolderNode,
          seedTree: [_favoriteFolderNode],
        );
        addTearDown(bloc.close);

        await tester.tap(find.text('UNFAVORITE'));
        await tester.pumpAndSettle();

        expect(
          CollectionsTreeHelper.findNode(
            bloc.state.collections,
            'f2',
          )!.isFavorite,
          isFalse,
        );
        expect(find.text('Removed from favorites'), findsOneWidget);
      },
    );

    testWidgets('RENAME confirm dispatches RenameNode and shows a snackbar', (
      tester,
    ) async {
      final bloc = await openMenu(
        tester,
        _folderNode,
        seedTree: [_folderNode],
      );
      addTearDown(bloc.close);

      await tester.tap(find.text('RENAME'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('name_prompt_field')),
        'Renamed Folder',
      );
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'f1')!.name,
        'Renamed Folder',
      );
      expect(find.text('Renamed to "Renamed Folder"'), findsOneWidget);
    });

    testWidgets(
      'EDIT DESCRIPTION confirm dispatches UpdateNodeDescription (trimmed) '
      'and shows a snackbar',
      (tester) async {
        final bloc = await openMenu(
          tester,
          _requestNode,
          seedTree: [_requestNode],
        );
        addTearDown(bloc.close);

        await tester.tap(find.text('EDIT DESCRIPTION'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('name_prompt_field')),
          '  calls the auth endpoint  ',
        );
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        expect(
          CollectionsTreeHelper.findNode(
            bloc.state.collections,
            'r1',
          )!.description,
          'calls the auth endpoint',
        );
        expect(find.text('Description updated'), findsOneWidget);
      },
    );

    testWidgets('VARIABLES opens the collection variables dialog', (
      tester,
    ) async {
      final bloc = await openMenu(
        tester,
        _folderNode,
        seedTree: [_folderNode],
      );
      addTearDown(bloc.close);

      await tester.tap(find.text('VARIABLES'));
      await tester.pumpAndSettle();

      expect(find.textContaining('VARIABLES — My Folder'), findsOneWidget);
    });

    testWidgets(
      'ADD SUBFOLDER confirm dispatches AddFolder under the node and shows '
      'a snackbar',
      (tester) async {
        final bloc = await openMenu(
          tester,
          _folderNode,
          seedTree: [_folderNode],
        );
        addTearDown(bloc.close);

        await tester.tap(find.text('ADD SUBFOLDER'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('name_prompt_field')),
          'Nested',
        );
        // The confirm button starts disabled (empty field) and re-enables via
        // a ValueListenableBuilder — pump a frame so the tap lands on the
        // enabled button.
        await tester.pump();
        await tester.tap(find.text('ADD'));
        await tester.pumpAndSettle();

        final parent = CollectionsTreeHelper.findNode(
          bloc.state.collections,
          'f1',
        )!;
        expect(
          parent.children.where((n) => n.name == 'Nested' && n.isFolder),
          hasLength(1),
        );
        expect(find.text('Folder "Nested" created'), findsOneWidget);
      },
    );

    testWidgets('EXPORT AS API DOCS… opens the export dialog', (tester) async {
      final bloc = await openMenu(
        tester,
        _folderNode,
        seedTree: [_folderNode],
      );
      addTearDown(bloc.close);

      await tester.tap(find.text('EXPORT AS API DOCS…'));
      await tester.pumpAndSettle();

      expect(find.text('EXPORT AS API DOCS'), findsOneWidget);
      expect(find.text('OpenAPI 3.0.3 (JSON)'), findsOneWidget);
    });

    testWidgets(
      'EXPORT TO POSTMAN writes the collection JSON to the picked path and '
      'confirms with a snackbar',
      (tester) async {
        // Mock the file_picker channel: the "save" dialog picks a temp path.
        final dir = Directory.systemTemp.createTempSync('getman_menu_export');
        addTearDown(() => dir.deleteSync(recursive: true));
        final savePath = '${dir.path}/my_folder.postman_collection.json';
        const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'save' ? savePath : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );

        final bloc = await openMenu(
          tester,
          _folderNode,
          seedTree: [_folderNode],
        );
        addTearDown(bloc.close);

        await tester.tap(find.text('EXPORT TO POSTMAN'));
        await tester.pumpAndSettle();
        // The export's real file write completes over several event-loop
        // turns interleaved with fake-async microtask flushes — alternate
        // (bounded) until the feedback snackbar lands.
        for (
          var i = 0;
          i < 20 && find.byType(SnackBar).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Exported to'), findsOneWidget);
        expect(
          File(savePath).readAsStringSync(),
          contains('My Folder'),
          reason: 'the exported Postman JSON should carry the node name',
        );
      },
    );

    testWidgets(
      'DELETE on a request removes it instantly and UNDO restores it',
      (tester) async {
        final bloc = await openMenu(
          tester,
          _requestNode,
          seedTree: [_requestNode],
        );
        addTearDown(bloc.close);

        await tester.tap(find.text('DELETE'));
        await tester.pumpAndSettle();

        // Instant delete: no confirm dialog for a single request.
        expect(find.text('Delete folder?'), findsNothing);
        expect(
          CollectionsTreeHelper.findNode(bloc.state.collections, 'r1'),
          isNull,
        );
        expect(find.text('Deleted "My Request"'), findsOneWidget);

        await tester.tap(find.text('UNDO'));
        await tester.pumpAndSettle();
        expect(
          CollectionsTreeHelper.findNode(bloc.state.collections, 'r1'),
          _requestNode,
        );
      },
    );

    testWidgets('DELETE on a folder confirms first, then deletes with UNDO', (
      tester,
    ) async {
      final bloc = await openMenu(
        tester,
        _folderNode,
        seedTree: [_folderNode],
      );
      addTearDown(bloc.close);

      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      expect(find.text('Delete folder?'), findsOneWidget);
      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'f1'),
        isNotNull,
        reason: 'nothing is deleted before the confirm',
      );

      await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
      await tester.pumpAndSettle();

      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'f1'),
        isNull,
      );
      expect(find.text('UNDO'), findsOneWidget);
    });
  });

  group('showCollectionNodeMenuAt (right-click entry point)', () {
    testWidgets(
      'opens the same menu at a position and routes the selection to the '
      'shared action handler',
      (tester) async {
        final bloc = buildBloc();
        addTearDown(bloc.close);
        bloc.add(const ReplaceCollections([_folderNode]));
        await bloc.stream.first;

        await tester.pumpWidget(
          host(
            bloc,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showCollectionNodeMenuAt(
                  context,
                  _folderNode,
                  const Offset(100, 100),
                ),
                child: const Text('OPEN AT'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OPEN AT'));
        await tester.pumpAndSettle();

        // Same entries as the "⋮" menu.
        expect(find.text('FAVORITE'), findsOneWidget);
        expect(find.text('ADD SUBFOLDER'), findsOneWidget);
        expect(find.text('DELETE'), findsOneWidget);

        // Selecting routes through the shared handler.
        await tester.tap(find.text('FAVORITE'));
        await tester.pumpAndSettle();
        expect(
          CollectionsTreeHelper.findNode(
            bloc.state.collections,
            'f1',
          )!.isFavorite,
          isTrue,
        );
        expect(find.text('Added to favorites'), findsOneWidget);
      },
    );

    testWidgets('dismissing the positioned menu performs no action', (
      tester,
    ) async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      bloc.add(const ReplaceCollections([_folderNode]));
      await bloc.stream.first;

      await tester.pumpWidget(
        host(
          bloc,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCollectionNodeMenuAt(
                context,
                _folderNode,
                const Offset(100, 100),
              ),
              child: const Text('OPEN AT'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OPEN AT'));
      await tester.pumpAndSettle();
      expect(find.text('DELETE'), findsOneWidget);

      // Dismiss by tapping outside the menu.
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();

      expect(find.text('DELETE'), findsNothing);
      expect(
        CollectionsTreeHelper.findNode(bloc.state.collections, 'f1'),
        isNotNull,
        reason: 'dismissing without a selection must not mutate the tree',
      );
    });
  });
}
