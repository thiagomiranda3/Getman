// Widget tests for RequestView: renders url bar, SEND button, no overflow,
// clamp behavior with extreme split-ratio settings, the loading/missing-tab
// states, unified compact layout, splitter drag commit, body/GraphQL
// controller<->bloc syncing, the BeautifyJsonIntent action, and the
// SaveRequestIntent flows (update linked node / save dialog / stale link).
// Uses a real TabsBloc with mocked repository + use case, plus mock blocs
// for the surrounding features.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/screens/request_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/tabs/presentation/widgets/response_area.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

// ── mocks ────────────────────────────────────────────────────────────────

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

class MockRealtimeBloc extends Mock implements RealtimeBloc {}

// Fake fallback values.
class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

class _FakeEnvironmentsEvent extends Fake implements EnvironmentsEvent {}

class _FakeSettingsEvent extends Fake implements SettingsEvent {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

class _FakeRealtimeEvent extends Fake implements RealtimeEvent {}

// ── helpers ──────────────────────────────────────────────────────────────────

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

MockEnvironmentsBloc _envBloc() {
  final b = MockEnvironmentsBloc();
  when(() => b.state).thenReturn(const EnvironmentsState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  return b;
}

MockSettingsBloc _settingsBloc({double splitRatio = 0.5}) {
  final b = MockSettingsBloc();
  when(() => b.state).thenReturn(
    SettingsState(settings: SettingsEntity(splitRatio: splitRatio)),
  );
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  when(() => b.add(any())).thenReturn(null);
  return b;
}

MockCollectionsBloc _collectionsBloc() {
  final b = MockCollectionsBloc();
  when(() => b.state).thenReturn(CollectionsState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  return b;
}

MockRealtimeBloc _realtimeBloc() {
  final b = MockRealtimeBloc();
  when(() => b.state).thenReturn(const RealtimeState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  when(() => b.add(any())).thenReturn(null);
  return b;
}

Future<void> _pump(
  WidgetTester tester, {
  required TabsBloc tabsBloc,
  required String tabId,
  MockSettingsBloc? settings,
  MockEnvironmentsBloc? environments,
  MockCollectionsBloc? collections,
  MockRealtimeBloc? realtime,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    RepositoryProvider<UrlFocusRegistry>(
      create: (_) => UrlFocusRegistry(),
      child: ChangeNotifierProvider<RequestSectionIndex>(
        create: (_) => RequestSectionIndex(),
        child: MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<TabsBloc>.value(value: tabsBloc),
                BlocProvider<SettingsBloc>.value(
                  value: settings ?? _settingsBloc(),
                ),
                BlocProvider<EnvironmentsBloc>.value(
                  value: environments ?? _envBloc(),
                ),
                BlocProvider<CollectionsBloc>.value(
                  value: collections ?? _collectionsBloc(),
                ),
                BlocProvider<RealtimeBloc>.value(
                  value: realtime ?? _realtimeBloc(),
                ),
              ],
              child: RequestView(tabId: tabId),
            ),
          ),
        ),
      ),
    ),
  );
  // A looping progress indicator never settles — loading tests pump once.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

// ── tests ────────────────────────────────────────────────────────────────

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(_FakeEnvironmentsEvent());
    registerFallbackValue(_FakeSettingsEvent());
    registerFallbackValue(_FakeCollectionsEvent());
    registerFallbackValue(_FakeRealtimeEvent());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(
      const Connect(tabId: 'x', kind: RequestKind.webSocket, url: 'ws://x'),
    );
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
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
  });

  testWidgets('renders url bar and split panes without overflow', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rv1',
      config: HttpRequestConfigEntity(id: 'rv1', url: 'https://example.com'),
    );
    final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv1');

    expect(find.byKey(const ValueKey('url_field')), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'split ratio 0.0 (below minimum) is clamped to 0.1 — both panes non-zero',
    (
      tester,
    ) async {
      const tab = HttpRequestTabEntity(
        tabId: 'rv2',
        config: HttpRequestConfigEntity(id: 'rv2', url: 'https://example.com'),
      );
      final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(tabsBloc.close);

      // splitRatio=0.0 is BELOW the [0.1, 0.9] range. Without the clamp in
      // _ratioToFlex, the request pane would get flex=0 and occupy zero width.
      // The clamp floors it to 0.1 (flex=100), keeping both panes non-zero.
      // Use a wide surface so the clamped 10% pane (~300 px) is wide enough for
      // the inner tab strip: the clamp is what we test, so the pump stays
      // overflow-clean and we assert strictly (no draining).
      tester.view.physicalSize = const Size(3000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        tabsBloc: tabsBloc,
        tabId: 'rv2',
        settings: _settingsBloc(splitRatio: 0),
      );

      expect(tester.takeException(), isNull);

      // The essential assertion: both panes must be laid out with positive
      // width, proving the clamp converted flex=0 → flex=100.
      final requestSize = tester.getSize(find.byType(RequestConfigSection));
      final responseSize = tester.getSize(find.byType(ResponseArea));
      expect(
        requestSize.width,
        greaterThan(0),
        reason: 'clamp must prevent zero-width request pane',
      );
      expect(
        responseSize.width,
        greaterThan(0),
        reason: 'response pane must still be visible',
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'split ratio 1.0 (above maximum) is clamped to 0.9 — both panes non-zero',
    (
      tester,
    ) async {
      const tab = HttpRequestTabEntity(
        tabId: 'rv3',
        config: HttpRequestConfigEntity(id: 'rv3', url: 'https://example.com'),
      );
      final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(tabsBloc.close);

      // splitRatio=1.0 is ABOVE the [0.1, 0.9] range. Without the clamp in
      // _ratioToFlex, the response pane would get flex=_ratioToFlex(1-1.0)=0
      // and occupy zero width. The clamp caps it to 0.9 so the response pane
      // retains flex=100 (10% of total) and remains visible.
      // Wide surface so the clamped 10% response pane is wide enough for its
      // inner widgets — the clamp is what we test, so we assert strictly.
      tester.view.physicalSize = const Size(3000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        tabsBloc: tabsBloc,
        tabId: 'rv3',
        settings: _settingsBloc(splitRatio: 1),
      );

      expect(tester.takeException(), isNull);

      // The essential assertion: both panes must be laid out with positive
      // width, proving the clamp converted flex=0 → flex=100.
      final requestSize = tester.getSize(find.byType(RequestConfigSection));
      final responseSize = tester.getSize(find.byType(ResponseArea));
      expect(
        requestSize.width,
        greaterThan(0),
        reason: 'request pane must still be visible',
      );
      expect(
        responseSize.width,
        greaterThan(0),
        reason: 'clamp must prevent zero-width response pane',
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('tapping SEND button marks tab as isSending', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rv4',
      config: HttpRequestConfigEntity(id: 'rv4', url: 'https://example.com'),
    );
    final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    // Completer that we'll complete after checking isSending.
    final completer = Completer<HttpResponseEntity>();
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => completer.future);

    await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv4');

    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump(); // let the synchronous isSending=true emit

    expect(tabsBloc.state.tabs.byId('rv4')!.isSending, isTrue);

    // Complete with an error so the bloc clears isSending cleanly.
    completer.completeError(
      Exception('test-cancel'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();
    // After isSending=true, _c IS initialized so the SizedBox unmount is clean.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('no overflow on default pump', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rv5',
      config: HttpRequestConfigEntity(
        id: 'rv5',
        url: 'https://httpbin.org/get',
      ),
    );
    final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv5');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('shows a progress indicator while tabs are loading', (
    tester,
  ) async {
    final completer = Completer<List<PanelEntity>>();
    when(() => repository.getPanels()).thenAnswer((_) => completer.future);
    when(() => repository.getActivePanelId()).thenAnswer((_) async => null);
    final tabsBloc = TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    )..add(const LoadTabs());
    addTearDown(tabsBloc.close);
    await tabsBloc.stream.firstWhere((s) => s.isLoading);

    await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv-loading', settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Finish the load (no tabs) — the missing tab renders as nothing.
    completer.complete(const <PanelEntity>[]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('url_field')), findsNothing);
  });

  testWidgets('a tabId with no matching tab renders nothing', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rv-present',
      config: HttpRequestConfigEntity(id: 'rv-present'),
    );
    final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv-missing');

    expect(find.byKey(const ValueKey('url_field')), findsNothing);
    expect(find.byType(RequestConfigSection), findsNothing);
  });

  testWidgets('compact width collapses to the unified request panel', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rv-compact',
      config: HttpRequestConfigEntity(id: 'rv-compact'),
    );
    final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    // ≤700 px wide → useUnifiedRequestTabs: single 4-tab strip, no splitter.
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv-compact');

    expect(find.byType(UnifiedRequestPanel), findsOneWidget);
    expect(find.byType(Splitter), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('dragging the splitter commits UpdateSplitRatio on release', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rv-split',
      config: HttpRequestConfigEntity(id: 'rv-split'),
    );
    final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);
    final settings = _settingsBloc();

    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      tabId: 'rv-split',
      settings: settings,
    );

    await tester.drag(find.byType(Splitter), const Offset(300, 0));
    await tester.pumpAndSettle();

    final committed =
        verify(
              () => settings.add(captureAny(that: isA<UpdateSplitRatio>())),
            ).captured.single
            as UpdateSplitRatio;
    expect(
      committed.ratio,
      greaterThan(0.5),
      reason: 'a rightwards drag must grow the request pane share',
    );
    expect(committed.ratio, lessThanOrEqualTo(0.9));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'an external body update syncs into the editor and BeautifyJsonIntent '
    'formats it back through the bloc',
    (tester) async {
      const ugly = '{"a":1,"b":[2,3]}';
      const tab = HttpRequestTabEntity(
        tabId: 'rv-beauty',
        config: HttpRequestConfigEntity(id: 'rv-beauty'),
      );
      final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(tabsBloc.close);

      await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv-beauty');

      // External update (e.g. revert / curl paste) — the BlocConsumer listener
      // must push the new body into the editor controller.
      final live = tabsBloc.state.tabs.byId('rv-beauty')!;
      tabsBloc.add(
        UpdateTab(live.copyWith(config: live.config.copyWith(body: ugly))),
      );
      await tester.pumpAndSettle();

      // Beautify hops to an isolate (compute) — drive it under runAsync.
      String? expected;
      await tester.runAsync(() async {
        expected = await JsonUtils.prettify(ugly);
        final result = Actions.invoke(
          tester.element(find.byKey(const ValueKey('url_field'))),
          const BeautifyJsonIntent(),
        );
        if (result is Future) await result;
      });
      await tester.pumpAndSettle();

      expect(expected, isNot(ugly));
      expect(
        tabsBloc.state.tabs.byId('rv-beauty')!.config.body,
        expected,
        reason:
            'the prettified text must round-trip through _onBodyChanged '
            'into an UpdateTab',
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'GraphQL variables sync both ways between the editor and the bloc',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'rv-gql',
        config: HttpRequestConfigEntity(
          id: 'rv-gql',
          bodyType: BodyType.graphql,
          body: 'query { me { id } }',
          graphqlVariables: '{"a":1}',
        ),
      );
      final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(tabsBloc.close);

      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, tabsBloc: tabsBloc, tabId: 'rv-gql');

      // Open the request pane's BODY tab (the response section has its own
      // BODY label — the request one comes first in the tree).
      await tester.tap(find.text('BODY').first);
      await tester.pumpAndSettle();

      // didChangeDependencies seeded the variables controller from the tab.
      final editors = tester.widgetList<CodeEditor>(find.byType(CodeEditor));
      final varsController = editors
          .map((e) => e.controller)
          .firstWhere((c) => c?.text == '{"a":1}');
      expect(varsController, isNotNull);

      // Editor → bloc: typing dispatches UpdateTab with the new variables.
      varsController!.text = '{"a":2}';
      await tester.pumpAndSettle();
      expect(
        tabsBloc.state.tabs.byId('rv-gql')!.config.graphqlVariables,
        '{"a":2}',
      );

      // Bloc → editor: an external update lands back in the controller.
      final live = tabsBloc.state.tabs.byId('rv-gql')!;
      tabsBloc.add(
        UpdateTab(
          live.copyWith(
            config: live.config.copyWith(graphqlVariables: '{"a":3}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(varsController.text, '{"a":3}');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 11));
    },
  );

  group('SaveRequestIntent', () {
    testWidgets(
      'unlinked tab opens the save dialog and links the tab on confirm',
      (tester) async {
        const tab = HttpRequestTabEntity(
          tabId: 'rv-save',
          config: HttpRequestConfigEntity(
            id: 'rv-save',
            url: 'https://api.dev/new',
          ),
        );
        final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(tabsBloc.close);
        final collections = _collectionsBloc();

        await _pump(
          tester,
          tabsBloc: tabsBloc,
          tabId: 'rv-save',
          collections: collections,
        );

        Actions.invoke(
          tester.element(find.byKey(const ValueKey('url_field'))),
          const SaveRequestIntent(),
        );
        await tester.pumpAndSettle();

        expect(find.text('SAVE TO COLLECTION'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('name_prompt_field')),
          'MY REQUEST',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(NamePromptDialog),
            matching: find.text('SAVE'),
          ),
        );
        await tester.pumpAndSettle();

        final saved =
            verify(
                  () => collections.add(
                    captureAny(that: isA<SaveRequestToCollection>()),
                  ),
                ).captured.single
                as SaveRequestToCollection;
        expect(saved.name, 'MY REQUEST');
        expect(saved.id, isNotNull);
        expect(saved.config.url, 'https://api.dev/new');

        // The open tab linked itself to the SAME pre-generated node id.
        final linked = tabsBloc.state.tabs.byId('rv-save')!;
        expect(linked.collectionName, 'MY REQUEST');
        expect(linked.collectionNodeId, saved.id);

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'tab linked to an existing node updates it in place (no dialog)',
      (tester) async {
        const config = HttpRequestConfigEntity(
          id: 'rv-upd',
          url: 'https://api.dev/edited',
        );
        const tab = HttpRequestTabEntity(
          tabId: 'rv-upd',
          config: config,
          collectionNodeId: 'n1',
          collectionName: 'Saved req',
        );
        final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(tabsBloc.close);

        final collections = _collectionsBloc();
        when(() => collections.state).thenReturn(
          CollectionsState(
            collections: const [
              CollectionNodeEntity(
                id: 'n1',
                name: 'Saved req',
                isFolder: false,
                config: HttpRequestConfigEntity(
                  id: 'rv-upd',
                  url: 'https://api.dev/original',
                ),
              ),
            ],
          ),
        );

        await _pump(
          tester,
          tabsBloc: tabsBloc,
          tabId: 'rv-upd',
          collections: collections,
        );

        Actions.invoke(
          tester.element(find.byKey(const ValueKey('url_field'))),
          const SaveRequestIntent(),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NamePromptDialog), findsNothing);
        expect(find.text('REQUEST UPDATED!'), findsOneWidget);
        final updated =
            verify(
                  () => collections.add(
                    captureAny(that: isA<UpdateNodeRequest>()),
                  ),
                ).captured.single
                as UpdateNodeRequest;
        expect(updated.id, 'n1');
        expect(updated.config, config);

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'a stale link (node deleted while open) is cleared and the dialog opens',
      (tester) async {
        const tab = HttpRequestTabEntity(
          tabId: 'rv-stale',
          config: HttpRequestConfigEntity(id: 'rv-stale'),
          collectionNodeId: 'ghost',
          collectionName: 'Deleted node',
        );
        final tabsBloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(tabsBloc.close);
        final collections = _collectionsBloc(); // empty tree — no 'ghost'

        await _pump(
          tester,
          tabsBloc: tabsBloc,
          tabId: 'rv-stale',
          collections: collections,
        );

        Actions.invoke(
          tester.element(find.byKey(const ValueKey('url_field'))),
          const SaveRequestIntent(),
        );
        await tester.pumpAndSettle();

        // Falls back to save-as-new, dropping the dangling link.
        expect(find.text('SAVE TO COLLECTION'), findsOneWidget);
        final cleared = tabsBloc.state.tabs.byId('rv-stale')!;
        expect(cleared.collectionNodeId, isNull);
        expect(cleared.collectionName, isNull);

        await tester.tap(
          find.descendant(
            of: find.byType(NamePromptDialog),
            matching: find.text('CANCEL'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pump(const Duration(seconds: 11));
      },
    );
  });
}
