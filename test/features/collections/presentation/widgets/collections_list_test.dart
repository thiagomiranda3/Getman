// Widget tests for the collections tree:
//  - H2 fix: folders stay expanded across unrelated mutations.
//  - Import menu opens.
//  - Active-tab linkage: focusing a tab linked to a saved request auto-expands
//    its ancestor folders and highlights the matching row.
//  - D2: tree search matches name/URL/method; collapse-all button disabled
//    during active search and doesn't resurrect pre-search expansion state.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
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

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

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
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: RepositoryProvider<WorkspaceSyncService>(
          create: (_) => WorkspaceSyncService(MockWorkspaceDataSource()),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<CollectionsBloc>.value(value: collections),
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<SettingsBloc>.value(value: settings),
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

      // Verify it stays collapsed by triggering a rebuild (e.g., switching
      // themes) — _preSearchExpandedIds doesn't resurrect the old state.
      bloc.add(const ReplaceCollections([folder]));
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
        name: 'PostCreateUser',
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

      // Both ancestor folders are collapsed.
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('PostCreateUser'), findsNothing);

      // Search by method only (no name match).
      await tester.enterText(find.byType(TextField), 'post');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Ancestor folders auto-expanded to show the method-matched request.
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('PostCreateUser'), findsOneWidget);
    },
  );
}
