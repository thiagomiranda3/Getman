// Widget tests for B2 host wiring in ParamsTabView and HeadersTabView:
// drag-reorder rewrites the URL query / rebuilds the insertion-ordered
// header map; duplicate inserts below (exact copy for params, '-copy' key
// for headers); the trailing blank row has no affordances. Real TabsBloc
// over a mocked repository — harness style mirrors auth_tab_view_test.dart.
//
// Also covers the B1/B2 interaction: the params tab's composed display list
// interleaves parked (disabled) rows among the enabled/URL ones (Task
// 2B.1's ParamRowComposer). A parked row has no live URL position, so
// dragging/duplicating FROM one is a no-op; dragging an enabled row across
// a parked row's display slot must reorder only the enabled/URL sequence
// and leave the parked row's remembered rowIndex anchor untouched.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/headers_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/params_tab_view.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class MockPutEnvironmentUseCase extends Mock implements PutEnvironmentUseCase {}

class MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class MockGetCollectionsUseCase extends Mock implements GetCollectionsUseCase {}

class MockSaveCollectionsUseCase extends Mock
    implements SaveCollectionsUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

SettingsBloc _settingsBloc() {
  final save = MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

EnvironmentsBloc _environmentsBloc() {
  final get = MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => const <EnvironmentEntity>[]);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: MockDeleteEnvironmentUseCase(),
  );
}

CollectionsBloc _collectionsBloc() {
  final get = MockGetCollectionsUseCase();
  when(get.call).thenAnswer((_) async => const <CollectionNodeEntity>[]);
  return CollectionsBloc(
    getCollectionsUseCase: get,
    saveCollectionsUseCase: MockSaveCollectionsUseCase(),
  );
}

Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
  MockSendRequestUseCase useCase,
  HttpRequestTabEntity tab,
) async {
  when(() => repository.getPanels()).thenAnswer(
    (_) async => [
      PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [tab],
        activeTabId: tab.tabId,
      ),
    ],
  );
  when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase)
    ..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

Future<void> _pump(WidgetTester tester, TabsBloc bloc, Widget child) async {
  final settingsBloc = _settingsBloc();
  addTearDown(settingsBloc.close);
  final environmentsBloc = _environmentsBloc();
  addTearDown(environmentsBloc.close);
  final collectionsBloc = _collectionsBloc();
  addTearDown(collectionsBloc.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<EnvironmentsBloc>.value(value: environmentsBloc),
            BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
          ],
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dragHandleBy(
  WidgetTester tester,
  Finder handle,
  double dy,
) async {
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveBy(Offset(0, dy / 2));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveBy(Offset(0, dy / 2));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => repository.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
  });

  group('ParamsTabView (URL is the single source of truth)', () {
    const tab = HttpRequestTabEntity(
      tabId: 't',
      config: HttpRequestConfigEntity(
        id: 't',
        url: 'https://x.dev/api?a=1&b=2',
      ),
    );

    testWidgets('drag-reorder rewrites the URL query order', (tester) async {
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);
      await _pump(tester, bloc, const ParamsTabView(tabId: 't'));

      final row0 = tester.getCenter(find.byKey(const ValueKey('param_key_0')));
      final row1 = tester.getCenter(find.byKey(const ValueKey('param_key_1')));
      await _dragHandleBy(
        tester,
        find.byIcon(Icons.drag_indicator).first,
        row1.dy - row0.dy + 8,
      );

      expect(
        bloc.state.tabs.byId('t')!.config.url,
        'https://x.dev/api?b=2&a=1',
      );

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets(
      'duplicate inserts an exact copy below — duplicates are legal in a '
      'query string',
      (tester) async {
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);
        await _pump(tester, bloc, const ParamsTabView(tabId: 't'));

        await tester.tap(find.byIcon(Icons.content_copy).first);
        await tester.pumpAndSettle();

        expect(
          bloc.state.tabs.byId('t')!.config.url,
          'https://x.dev/api?a=1&a=1&b=2',
        );

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets('the trailing blank row has no handle or duplicate button', (
      tester,
    ) async {
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);
      await _pump(tester, bloc, const ParamsTabView(tabId: 't'));

      // 2 data rows -> exactly 2 handles + 2 duplicate buttons (blank: none).
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
      expect(find.byIcon(Icons.content_copy), findsNWidgets(2));

      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('ParamsTabView with a parked (B1) row interleaved', () {
    // Display order (ParamRowComposer.compose): a(0, enabled),
    // z(1, parked), b(2, enabled).
    const tab = HttpRequestTabEntity(
      tabId: 'tp',
      config: HttpRequestConfigEntity(
        id: 'tp',
        url: 'https://x.dev/api?a=1&b=2',
        disabledParams: [ParkedParamEntity(key: 'z', value: '9', rowIndex: 1)],
      ),
    );

    testWidgets(
      'dragging an enabled row across a parked row reorders only the URL '
      "sequence and leaves the parked row's rowIndex anchor untouched",
      (tester) async {
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);
        await _pump(tester, bloc, const ParamsTabView(tabId: 'tp'));

        // Drag the last data row (b, index 2) all the way up past the
        // parked row (z) to land before the first row (a). A large negative
        // delta (mirroring the "past the trailing blank row clamps" case in
        // key_value_list_editor_test.dart) reliably lands at the top slot
        // regardless of live row reflow during the drag.
        await _dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        final result = bloc.state.tabs.byId('tp')!.config;
        expect(result.url, 'https://x.dev/api?b=2&a=1');
        expect(
          result.disabledParams,
          const [ParkedParamEntity(key: 'z', value: '9', rowIndex: 1)],
          reason:
              "the parked row's rowIndex anchor is never rewritten by a "
              'reorder — only the enabled/URL sequence moves',
        );

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'dragging the parked row itself is a no-op — it has no live URL '
      'position to reorder into',
      (tester) async {
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);
        await _pump(tester, bloc, const ParamsTabView(tabId: 'tp'));

        await _dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(1),
          -1000,
        );

        final result = bloc.state.tabs.byId('tp')!.config;
        expect(result.url, 'https://x.dev/api?a=1&b=2');
        expect(result.disabledParams, const [
          ParkedParamEntity(key: 'z', value: '9', rowIndex: 1),
        ]);

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets('duplicating the parked row is a no-op via this affordance', (
      tester,
    ) async {
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);
      await _pump(tester, bloc, const ParamsTabView(tabId: 'tp'));

      await tester.tap(find.byIcon(Icons.content_copy).at(1));
      await tester.pumpAndSettle();

      final result = bloc.state.tabs.byId('tp')!.config;
      expect(result.url, 'https://x.dev/api?a=1&b=2');
      expect(result.disabledParams, const [
        ParkedParamEntity(key: 'z', value: '9', rowIndex: 1),
      ]);

      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('HeadersTabView (insertion-ordered map)', () {
    const tab = HttpRequestTabEntity(
      tabId: 'h',
      config: HttpRequestConfigEntity(
        id: 'h',
        headers: {'Accept': '*/*', 'X-One': '1'},
      ),
    );

    testWidgets('drag-reorder rebuilds the map in the new order', (
      tester,
    ) async {
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);
      await _pump(tester, bloc, const HeadersTabView(tabId: 'h'));

      final row0 = tester.getCenter(
        find.byKey(const ValueKey('header_key_0')),
      );
      final row1 = tester.getCenter(
        find.byKey(const ValueKey('header_key_1')),
      );
      await _dragHandleBy(
        tester,
        find.byIcon(Icons.drag_indicator).first,
        row1.dy - row0.dy + 8,
      );

      expect(
        bloc.state.tabs.byId('h')!.config.headers.keys.toList(),
        ['X-One', 'Accept'],
        reason:
            'requires order-significant equality (Task 2B.2) or the '
            'reordered state emission is suppressed',
      );

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets(
      "duplicate inserts a '-copy' key directly below with the same value",
      (tester) async {
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);
        await _pump(tester, bloc, const HeadersTabView(tabId: 'h'));

        await tester.tap(find.byIcon(Icons.content_copy).first);
        await tester.pumpAndSettle();

        final headers = bloc.state.tabs.byId('h')!.config.headers;
        expect(headers.keys.toList(), ['Accept', 'Accept-copy', 'X-One']);
        expect(headers['Accept-copy'], '*/*');

        await tester.pump(const Duration(seconds: 11));
      },
    );
  });
}
