// Widget tests for the collections tree:
//  - H2 fix: folders stay expanded across unrelated mutations.
//  - Import menu opens.
//  - Active-tab linkage: focusing a tab linked to a saved request auto-expands
//    its ancestor folders and highlights the matching row.
//  - D2: tree search matches name/URL/method; collapse-all button disabled
//    during active search and doesn't resurrect pre-search expansion state.

import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/widgets/collection_node_row.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:getman/features/collections/presentation/widgets/node_drag_data.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockWorkspaceDataSource extends Mock
    implements WorkspaceCollectionsDataSource {}

class MockReviewService extends Mock implements ReviewService {}

class MockNetworkService extends Mock implements NetworkService {}

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class MockEnvironmentsBloc
    extends MockBloc<EnvironmentsEvent, EnvironmentsState>
    implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

HttpRequestTabEntity _tab(String tabId, {String? linkedNodeId}) =>
    HttpRequestTabEntity(
      tabId: tabId,
      config: HttpRequestConfigEntity(id: tabId),
      collectionNodeId: linkedNodeId,
    );

TabsState _stateWith(HttpRequestTabEntity tab) => TabsState(tabs: [tab]);

void main() {
  late MockCollectionsRepository repo;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(_FakeTabsEvent());
  });

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc build() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  // Builds the widget under a CollectionsBloc + a MockTabsBloc.
  // [tabsStates], if given, are emitted so the active-tab listener fires.
  Widget host(
    CollectionsBloc collections,
    MockTabsBloc tabs, {
    TabsState tabsInitial = const TabsState(),
    List<TabsState> tabsStates = const [],
  }) {
    when(() => tabs.state).thenReturn(
      tabsStates.isNotEmpty ? tabsStates.last : tabsInitial,
    );
    whenListen(
      tabs,
      Stream<TabsState>.fromIterable(tabsStates),
      initialState: tabsInitial,
    );
    final settings = MockSettingsBloc();
    when(() => settings.state).thenReturn(
      const SettingsState(settings: SettingsEntity()),
    );
    when(() => settings.stream).thenAnswer((_) => const Stream.empty());
    final environments = MockEnvironmentsBloc();
    whenListen(
      environments,
      const Stream<EnvironmentsState>.empty(),
      initialState: const EnvironmentsState(),
    );
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<WorkspaceSyncService>(
              create: (_) => WorkspaceSyncService(MockWorkspaceDataSource()),
            ),
            RepositoryProvider<NetworkService>(
              create: (_) => MockNetworkService(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<CollectionsBloc>.value(value: collections),
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<EnvironmentsBloc>.value(value: environments),
              BlocProvider<ReviewBloc>(
                create: (_) => ReviewBloc(service: MockReviewService()),
              ),
            ],
            child: const CollectionsList(),
          ),
        ),
      ),
    );
  }

  testWidgets('folder stays expanded after a child inside it is renamed', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const child = CollectionNodeEntity(
      id: 'C',
      name: 'ChildReq',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'C'),
    );
    const folder = CollectionNodeEntity(
      id: 'F',
      name: 'Folder',
      children: [child],
    );
    const sibling = CollectionNodeEntity(
      id: 'S',
      name: 'Sibling',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'S'),
    );

    bloc.add(const ReplaceCollections([folder, sibling]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    expect(find.text('ChildReq'), findsNothing);

    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    expect(find.text('ChildReq'), findsOneWidget);

    bloc.add(const RenameNode('C', 'ChildRenamed'));
    await bloc.stream.first;
    await tester.pumpAndSettle();

    expect(find.text('ChildRenamed'), findsOneWidget);
  });

  testWidgets('import button opens a menu with Postman + OpenAPI entries', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload));
    await tester.pumpAndSettle();

    expect(find.text('FROM POSTMAN'), findsOneWidget);
    expect(find.text('FROM OPENAPI / SWAGGER'), findsOneWidget);
  });

  testWidgets(
    'focusing a tab linked to a request inside a collapsed folder reveals + '
    'highlights it',
    (tester) async {
      final bloc = build();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      const child = CollectionNodeEntity(
        id: 'req-1',
        name: 'GetUser',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'req-1'),
      );
      const folder = CollectionNodeEntity(
        id: 'F',
        name: 'ApiFolder',
        children: [child],
      );

      bloc.add(const ReplaceCollections([folder]));
      await bloc.stream.first;

      // Emit a state whose active tab is linked to the nested request.
      await tester.pumpWidget(
        host(
          bloc,
          tabs,
          tabsStates: [_stateWith(_tab('t1', linkedNodeId: 'req-1'))],
        ),
      );
      await tester.pumpAndSettle();

      // The folder auto-expanded → the nested request row is now rendered.
      expect(find.text('GetUser'), findsOneWidget);

      // And that row is marked selected.
      final row = tester.widget<CollectionNodeRow>(
        find.byType(CollectionNodeRow).last,
      );
      expect(row.node.id, 'req-1');
      expect(row.isSelected, isTrue);
    },
  );

  testWidgets('tree search matches the request method (case-insensitive)', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const getReq = CollectionNodeEntity(
      id: 'g',
      name: 'FetchUsers',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'g', url: 'https://api.dev/users'),
    );
    const postReq = CollectionNodeEntity(
      id: 'p',
      name: 'CreateUser',
      isFolder: false,
      config: HttpRequestConfigEntity(
        id: 'p',
        method: 'POST',
        url: 'https://api.dev/users',
      ),
    );

    bloc.add(const ReplaceCollections([getReq, postReq]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'post');
    // Past the search Debouncer.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('CreateUser'), findsOneWidget);
    expect(find.text('FetchUsers'), findsNothing);
  });

  testWidgets('collapse-all button collapses every expanded folder', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const child = CollectionNodeEntity(
      id: 'C2',
      name: 'NestedReq',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'C2'),
    );
    const folder = CollectionNodeEntity(
      id: 'F2',
      name: 'ApiFolder2',
      children: [child],
    );

    bloc.add(const ReplaceCollections([folder]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ApiFolder2'));
    await tester.pumpAndSettle();
    expect(find.text('NestedReq'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collections_collapse_all')));
    await tester.pumpAndSettle();

    expect(find.text('NestedReq'), findsNothing);
  });

  testWidgets('collapse-all button is disabled while search query is active', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const child = CollectionNodeEntity(
      id: 'C3',
      name: 'NestedReq',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'C3'),
    );
    const folder = CollectionNodeEntity(
      id: 'F3',
      name: 'ApiFolder',
      children: [child],
    );

    bloc.add(const ReplaceCollections([folder]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    // Button is enabled initially.
    var button = tester.widget<IconButton>(
      find.byKey(const ValueKey('collections_collapse_all')),
    );
    expect(button.onPressed, isNotNull);

    // Type a search query.
    await tester.enterText(find.byType(TextField), 'Nested');
    // Past the search Debouncer (400ms).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Button is disabled during active search.
    button = tester.widget<IconButton>(
      find.byKey(const ValueKey('collections_collapse_all')),
    );
    expect(button.onPressed, isNull);

    // Clear the search.
    await tester.enterText(find.byType(TextField), '');
    // Past the search Debouncer.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Button is enabled again.
    button = tester.widget<IconButton>(
      find.byKey(const ValueKey('collections_collapse_all')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
    'collapse-all after search + clear fully collapses and does not resurrect '
    'pre-search expansion',
    (tester) async {
      final bloc = build();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      const child = CollectionNodeEntity(
        id: 'C4',
        name: 'NestedReq',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'C4'),
      );
      const folder = CollectionNodeEntity(
        id: 'F4',
        name: 'ApiFolder',
        children: [child],
      );

      bloc.add(const ReplaceCollections([folder]));
      await bloc.stream.first;

      await tester.pumpWidget(host(bloc, tabs));
      await tester.pumpAndSettle();

      // Manually expand the folder.
      await tester.tap(find.text('ApiFolder'));
      await tester.pumpAndSettle();
      expect(find.text('NestedReq'), findsOneWidget);

      // Type a search query.
      await tester.enterText(find.byType(TextField), 'Nested');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Collapse-all is disabled during search (button unresponsive).
      expect(
        find.text('NestedReq'),
        findsOneWidget,
      ); // still visible due to search
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('collections_collapse_all')),
      );
      expect(button.onPressed, isNull);

      // Clear the search.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Folder reverts to pre-search state (expanded).
      expect(find.text('NestedReq'), findsOneWidget);

      // Now collapse-all works and fully collapses the tree.
      await tester.tap(find.byKey(const ValueKey('collections_collapse_all')));
      await tester.pumpAndSettle();

      expect(find.text('NestedReq'), findsNothing);

      // Verify it stays collapsed by triggering a rebuild via an unrelated
      // tree mutation — not a no-op ReplaceCollections. Bloc.emit() skips
      // emitting a state that equals the current one (bloc_base.dart), so
      // re-adding the identical `folder` value would never complete
      // `bloc.stream.first`. _preSearchExpandedIds must not resurrect the old
      // expansion on this rebuild.
      bloc.add(const RenameNode('F4', 'ApiFolderRenamed'));
      await bloc.stream.first;
      await tester.pumpAndSettle();

      expect(find.text('NestedReq'), findsNothing);
    },
  );

  testWidgets(
    'tree search by method-only match auto-expands ancestor folders',
    (tester) async {
      final bloc = build();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      const nested = CollectionNodeEntity(
        id: 'DEEP',
        // Deliberately no "post" substring in the name — this must match by
        // config.method alone, not piggyback on a name match.
        name: 'CreateUserRecord',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'DEEP',
          method: 'POST',
          url: 'https://api.dev/users',
        ),
      );
      const middleFolder = CollectionNodeEntity(
        id: 'MID',
        name: 'Users',
        children: [nested],
      );
      const rootFolder = CollectionNodeEntity(
        id: 'ROOT',
        name: 'Api',
        children: [middleFolder],
      );

      bloc.add(const ReplaceCollections([rootFolder]));
      await bloc.stream.first;

      await tester.pumpWidget(host(bloc, tabs));
      await tester.pumpAndSettle();

      // Both ancestor folders are collapsed: the root folder always renders
      // (TreeView roots are active regardless of expansion), but its child
      // folder — and the doubly-nested request — are inactive until an
      // ancestor expands.
      expect(find.text('Api'), findsOneWidget);
      expect(find.text('Users'), findsNothing);
      expect(find.text('CreateUserRecord'), findsNothing);

      // Search by method only (no name match).
      await tester.enterText(find.byType(TextField), 'post');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Ancestor folders auto-expanded to show the method-matched request.
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('CreateUserRecord'), findsOneWidget);
    },
  );

  testWidgets('empty tree shows the NO COLLECTIONS YET empty state', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    expect(find.text('NO COLLECTIONS YET'), findsOneWidget);
    expect(
      find.text('Save a request or import from Postman to get started.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a progress indicator while collections are loading', (
    tester,
  ) async {
    final gate = Completer<List<CollectionNodeEntity>>();
    when(() => repo.getCollections()).thenAnswer((_) => gate.future);
    final bloc = build()..add(const LoadCollections());
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    await tester.pumpWidget(host(bloc, tabs));
    // Bounded pumps only — the spinner animates forever, so pumpAndSettle
    // would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(const [
      CollectionNodeEntity(id: 'F', name: 'Loaded'),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Loaded'), findsOneWidget);
  });

  testWidgets('tree search matches the request URL', (tester) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const byUrl = CollectionNodeEntity(
      id: 'u',
      name: 'Health',
      isFolder: false,
      config: HttpRequestConfigEntity(
        id: 'u',
        url: 'https://status.internal.dev/ping',
      ),
    );
    const other = CollectionNodeEntity(
      id: 'o',
      name: 'Users',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'o', url: 'https://api.dev/users'),
    );

    bloc.add(const ReplaceCollections([byUrl, other]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'status.internal');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Health'), findsOneWidget);
    expect(find.text('Users'), findsNothing);
  });

  testWidgets('tapping an expanded folder collapses it again', (tester) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    const child = CollectionNodeEntity(
      id: 'C5',
      name: 'InsideReq',
      isFolder: false,
      config: HttpRequestConfigEntity(id: 'C5'),
    );
    const folder = CollectionNodeEntity(
      id: 'F5',
      name: 'ToggleFolder',
      children: [child],
    );

    bloc.add(const ReplaceCollections([folder]));
    await bloc.stream.first;

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ToggleFolder'));
    await tester.pumpAndSettle();
    expect(find.text('InsideReq'), findsOneWidget);

    await tester.tap(find.text('ToggleFolder'));
    await tester.pumpAndSettle();
    expect(find.text('InsideReq'), findsNothing);
  });

  testWidgets(
    'dropping a node on the list-level target moves it to the root',
    (tester) async {
      final bloc = build();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      const child = CollectionNodeEntity(
        id: 'C6',
        name: 'NestedReq',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'C6'),
      );
      const folder = CollectionNodeEntity(
        id: 'F6',
        name: 'HoldingFolder',
        children: [child],
      );

      bloc.add(const ReplaceCollections([folder]));
      await bloc.stream.first;

      await tester.pumpWidget(host(bloc, tabs));
      await tester.pumpAndSettle();

      // The list-level root drop target is the outermost DragTarget (the
      // rows' own targets are its descendants).
      final rootTarget = tester.widget<DragTarget<NodeDragData>>(
        find.byType(DragTarget<NodeDragData>).first,
      );
      rootTarget.onAcceptWithDetails!(
        DragTargetDetails<NodeDragData>(
          data: const NodeDragData('C6'),
          offset: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        bloc.state.collections.map((n) => n.id),
        containsAll(<String>['F6', 'C6']),
        reason: 'the nested request should now sit at the root',
      );
      final holding = bloc.state.collections.firstWhere((n) => n.id == 'F6');
      expect(holding.children, isEmpty);
    },
  );

  testWidgets(
    'FROM POSTMAN imports a picked collection file into the tree',
    (tester) async {
      // Mock the file_picker channel: picking returns one in-memory Postman
      // v2.1 collection file.
      final fileBytes = utf8.encode(
        jsonEncode({
          'info': {
            'name': 'Imported API',
            'schema':
                'https://schema.getpostman.com/json/collection/'
                'v2.1.0/collection.json',
          },
          'item': <dynamic>[],
        }),
      );
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method != 'custom') return null;
          return [
            {
              'path': null,
              'name': 'imported.postman_collection.json',
              'bytes': fileBytes,
              'size': fileBytes.length,
              'identifier': null,
            },
          ];
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final bloc = build();
      addTearDown(bloc.close);
      final tabs = MockTabsBloc();
      addTearDown(tabs.close);

      await tester.pumpWidget(host(bloc, tabs));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.file_upload));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FROM POSTMAN'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        bloc.state.collections.map((n) => n.name),
        contains('Imported API'),
      );
      // The imported root shows in the tree and the summary snackbar.
      expect(find.text('Imported API'), findsOneWidget);
      expect(find.textContaining('Imported 1 collection'), findsOneWidget);
    },
  );

  testWidgets('FROM OPENAPI / SWAGGER opens the spec import dialog', (
    tester,
  ) async {
    final bloc = build();
    addTearDown(bloc.close);
    final tabs = MockTabsBloc();
    addTearDown(tabs.close);

    await tester.pumpWidget(host(bloc, tabs));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_upload));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FROM OPENAPI / SWAGGER'));
    await tester.pumpAndSettle();

    expect(find.text('IMPORT API SPEC'), findsOneWidget);
  });
}
