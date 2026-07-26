// Widget tests for UrlBar: URL field and SEND button presence, cURL paste
// auto-parse, SEND button marks tab as isSending, WS/SSE shows RealtimeButton
// instead, CANCEL mid-send, code-export live re-read, layout toggle, MCP
// connect button, the narrow-width overflow menu, the {{var}} hover popover,
// and env/settings/collections re-sync listeners. Uses a real TabsBloc with
// mocked repository + use case, plus mock blocs for EnvironmentsBloc/
// SettingsBloc/CollectionsBloc/RealtimeBloc/McpBloc.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
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
import 'package:getman/features/tabs/presentation/widgets/url_bar.dart';
import 'package:mocktail/mocktail.dart';

// Real bloc mocks.
class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

// Stub blocs — we only need state + stream (no dispatch needed from test code).
class MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

class MockHistoryBloc extends Mock implements HistoryBloc {}

class MockRealtimeBloc extends Mock implements RealtimeBloc {}

class MockMcpBloc extends Mock implements McpBloc {}

// Fake fallback values.
class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

class _FakeEnvironmentsEvent extends Fake implements EnvironmentsEvent {}

class _FakeSettingsEvent extends Fake implements SettingsEvent {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

class _FakeRealtimeEvent extends Fake implements RealtimeEvent {}

class _FakeMcpEvent extends Fake implements McpEvent {}

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

MockEnvironmentsBloc _defaultEnvBloc() {
  final b = MockEnvironmentsBloc();
  when(() => b.state).thenReturn(const EnvironmentsState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  return b;
}

MockSettingsBloc _defaultSettingsBloc() {
  final b = MockSettingsBloc();
  when(
    () => b.state,
  ).thenReturn(const SettingsState(settings: SettingsEntity()));
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  when(() => b.add(any())).thenReturn(null);
  return b;
}

MockCollectionsBloc _defaultCollectionsBloc() {
  final b = MockCollectionsBloc();
  when(() => b.state).thenReturn(CollectionsState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  return b;
}

MockHistoryBloc _defaultHistoryBloc([
  List<HttpRequestConfigEntity> history = const [],
]) {
  final b = MockHistoryBloc();
  when(() => b.state).thenReturn(HistoryState(history: history));
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  return b;
}

MockRealtimeBloc _defaultRealtimeBloc() {
  final b = MockRealtimeBloc();
  when(() => b.state).thenReturn(const RealtimeState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  when(() => b.add(any())).thenReturn(null);
  return b;
}

MockMcpBloc _defaultMcpBloc() {
  final b = MockMcpBloc();
  when(() => b.state).thenReturn(const McpState());
  when(() => b.stream).thenAnswer((_) => const Stream.empty());
  when(() => b.add(any())).thenReturn(null);
  return b;
}

Future<void> _pump(
  WidgetTester tester,
  TabsBloc bloc,
  String tabId, {
  MockEnvironmentsBloc? envBloc,
  MockSettingsBloc? settingsBloc,
  MockCollectionsBloc? collectionsBloc,
  MockRealtimeBloc? realtimeBloc,
  MockHistoryBloc? historyBloc,
  MockMcpBloc? mcpBloc,
  double? width,
  VoidCallback? onSave,
}) async {
  final urlBar = UrlBar(tabId: tabId, onSave: onSave ?? () {});
  await tester.pumpWidget(
    RepositoryProvider<UrlFocusRegistry>(
      create: (_) => UrlFocusRegistry(),
      child: MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<EnvironmentsBloc>.value(
                value: envBloc ?? _defaultEnvBloc(),
              ),
              BlocProvider<SettingsBloc>.value(
                value: settingsBloc ?? _defaultSettingsBloc(),
              ),
              BlocProvider<CollectionsBloc>.value(
                value: collectionsBloc ?? _defaultCollectionsBloc(),
              ),
              BlocProvider<RealtimeBloc>.value(
                value: realtimeBloc ?? _defaultRealtimeBloc(),
              ),
              BlocProvider<HistoryBloc>.value(
                value: historyBloc ?? _defaultHistoryBloc(),
              ),
              BlocProvider<McpBloc>.value(
                value: mcpBloc ?? _defaultMcpBloc(),
              ),
            ],
            // width < 560 exercises the isNarrow overflow-menu layout.
            child: width == null
                ? urlBar
                : Center(
                    child: SizedBox(width: width, child: urlBar),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    registerFallbackValue(_FakeMcpEvent());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(
      const Connect(tabId: 'x', kind: RequestKind.webSocket, url: 'ws://x'),
    );
    registerFallbackValue(const Disconnect('x'));
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

  testWidgets('renders url field and SEND button for HTTP kind', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u1',
      config: HttpRequestConfigEntity(id: 'u1', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'u1');

    expect(find.byKey(const ValueKey('url_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('send')), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'entering curl string dispatches UpdateTab with parsed method and url',
    (
      tester,
    ) async {
      const tab = HttpRequestTabEntity(
        tabId: 'u2',
        config: HttpRequestConfigEntity(id: 'u2'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'u2');

      await tester.enterText(
        find.byKey(const ValueKey('url_field')),
        "curl https://example.com -X POST -H 'Content-Type: application/json'",
      );
      await tester.pump();
      // Wait for compute() to return in the cURL parse path.
      await tester.pumpAndSettle();

      final updated = bloc.state.tabs.byId('u2')!.config;
      expect(updated.method, 'POST');
      expect(updated.url, 'https://example.com');

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'typing in the URL field must not revert a body edited since the last '
    'URL-bar rebuild',
    (tester) async {
      // UrlBar's buildWhen deliberately excludes config.body/url edits, so
      // its builder snapshot goes stale — the dispatch must re-read the
      // live tab or it wipes the newer body (regression).
      const tab = HttpRequestTabEntity(
        tabId: 'u8',
        config: HttpRequestConfigEntity(id: 'u8', url: 'https://a.dev'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'u8');

      // The body editor updates the config (UrlBar does not rebuild).
      final live = bloc.state.tabs.byId('u8')!;
      bloc.add(
        UpdateTab(
          live.copyWith(config: live.config.copyWith(body: '{"x":1}')),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('url_field')),
        'https://a.dev/v2',
      );
      await tester.pump();

      final updated = bloc.state.tabs.byId('u8')!.config;
      expect(updated.url, 'https://a.dev/v2');
      expect(
        updated.body,
        '{"x":1}',
        reason: 'a URL edit must not clobber the newer body edit',
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'changing the method must not revert a URL typed since the last '
    'URL-bar rebuild',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'u9',
        config: HttpRequestConfigEntity(id: 'u9'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'u9');

      await tester.enterText(
        find.byKey(const ValueKey('url_field')),
        'https://typed.dev',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('method_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('POST').last);
      await tester.pumpAndSettle();

      final updated = bloc.state.tabs.byId('u9')!.config;
      expect(updated.method, 'POST');
      expect(
        updated.url,
        'https://typed.dev',
        reason: 'a method change must not clobber the newer URL edit',
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('tapping SEND button marks tab isSending=true', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u3',
      config: HttpRequestConfigEntity(id: 'u3', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    // Completer that we'll complete after checking isSending — keeps the
    // request alive long enough to assert, then resolves cleanly.
    final completer = Completer<HttpResponseEntity>();
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => completer.future);

    await _pump(tester, bloc, 'u3');

    await tester.tap(find.byKey(const ValueKey('send')));
    // One pump to process the bloc event up to the first await.
    await tester.pump();

    expect(bloc.state.tabs.byId('u3')!.isSending, isTrue);

    // Complete with an error so the bloc clears isSending cleanly.
    completer.completeError(
      Exception('test-cancel'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();
    // Unmount before the debounced save timer fires so the bloc closes cleanly.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('pressing Enter in the focused URL field sends the request', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u10',
      config: HttpRequestConfigEntity(id: 'u10', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    final completer = Completer<HttpResponseEntity>();
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => completer.future);

    await _pump(tester, bloc, 'u10');

    // Focus the URL field, then submit it (what Enter does in a single-line
    // TextField).
    await tester.tap(find.byKey(const ValueKey('url_field')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      bloc.state.tabs.byId('u10')!.isSending,
      isTrue,
      reason: 'Enter in the URL field must dispatch the same send as SEND',
    );

    completer.completeError(Exception('test-cancel'), StackTrace.current);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('Enter while a send is in flight does not dispatch another', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u11',
      config: HttpRequestConfigEntity(id: 'u11', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    final completer = Completer<HttpResponseEntity>();
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => completer.future);

    await _pump(tester, bloc, 'u11');

    await tester.tap(find.byKey(const ValueKey('url_field')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(bloc.state.tabs.byId('u11')!.isSending, isTrue);

    // A second Enter mid-send must be a no-op (not a cancel, not a re-send).
    await tester.tap(find.byKey(const ValueKey('url_field')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    verify(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).called(1);
    expect(bloc.state.tabs.byId('u11')!.isSending, isTrue);

    completer.completeError(Exception('test-cancel'), StackTrace.current);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('Enter in the URL field of a WS tab does not send', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u12',
      config: HttpRequestConfigEntity(
        id: 'u12',
        url: 'wss://example.com/socket',
        kind: RequestKind.webSocket,
      ),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'u12');

    await tester.tap(find.byKey(const ValueKey('url_field')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    verifyNever(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    );
    expect(bloc.state.tabs.byId('u12')!.isSending, isFalse);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('in-flight spinner drops its track ring (animation visible)', (
    tester,
  ) async {
    // Regression: themes whose progressIndicatorTheme.circularTrackColor is
    // nearly identical to onError (AURIS) made the spinning arc blend into the
    // track, reading as a static ring. The spinner pins backgroundColor to
    // transparent so only the moving arc paints.
    const tab = HttpRequestTabEntity(
      tabId: 'u9',
      config: HttpRequestConfigEntity(id: 'u9', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    final completer = Completer<HttpResponseEntity>();
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => completer.future);

    await _pump(tester, bloc, 'u9');
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.backgroundColor, Colors.transparent);

    completer.completeError(Exception('test-cancel'), StackTrace.current);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('WS kind shows RealtimeButton (CONNECT) instead of SEND', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u4',
      config: HttpRequestConfigEntity(
        id: 'u4',
        url: 'ws://example.com',
        kind: RequestKind.webSocket,
      ),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'u4');

    expect(
      find.byKey(const ValueKey('realtime_connect_button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('send')), findsNothing);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    "URL bar re-syncs {{var}} highlighting when the tab's collectionNodeId "
    'changes — regression guard (A8)',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'u10',
        config: HttpRequestConfigEntity(
          id: 'u10',
          url: 'https://{{base}}/path',
        ),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      const folder = CollectionNodeEntity(
        id: 'folder1',
        name: 'Folder',
        variables: {'base': 'collection.example.com'},
        children: [
          CollectionNodeEntity(id: 'req1', name: 'Req', isFolder: false),
        ],
      );
      final collectionsBloc = MockCollectionsBloc();
      when(
        () => collectionsBloc.state,
      ).thenReturn(CollectionsState(collections: const [folder]));
      when(
        () => collectionsBloc.stream,
      ).thenAnswer((_) => const Stream.empty());

      await _pump(tester, bloc, 'u10', collectionsBloc: collectionsBloc);

      VariableHighlightController urlController() =>
          tester
                  .widget<TextField>(find.byKey(const ValueKey('url_field')))
                  .controller!
              as VariableHighlightController;

      expect(
        urlController().variables.containsKey('base'),
        isFalse,
        reason: 'not linked to the collection yet — base must be unresolved',
      );

      // Simulate save-to-collection: link the tab to the leaf node WITHOUT
      // changing the URL (no EnvironmentsBloc/SettingsBloc/CollectionsBloc
      // change accompanies it).
      final live = bloc.state.tabs.byId('u10')!;
      bloc.add(UpdateTab(live.copyWith(collectionNodeId: 'req1')));
      await tester.pump();

      expect(
        urlController().variables['base'],
        'collection.example.com',
        reason:
            "linking the tab must re-sync highlighting so a folder's "
            '{{var}} resolves without an unrelated env/settings/collections '
            'change',
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('no overflow', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'u5',
      config: HttpRequestConfigEntity(id: 'u5', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'u5');

    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 11));
  });

  group('URL autocomplete from history + collections (B4)', () {
    testWidgets(
      'typing 3+ chars suggests matching history URLs; tapping one '
      'replaces the whole field and updates the tab',
      (tester) async {
        const tab = HttpRequestTabEntity(
          tabId: 'b4a',
          config: HttpRequestConfigEntity(id: 'b4a'),
        );
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);

        final historyBloc = _defaultHistoryBloc(const [
          HttpRequestConfigEntity(id: 'h1', url: 'https://api.dev/users'),
          HttpRequestConfigEntity(id: 'h2', url: 'https://api.dev/orders'),
        ]);

        await _pump(tester, bloc, 'b4a', historyBloc: historyBloc);

        await tester.enterText(find.byKey(const ValueKey('url_field')), 'api');
        await tester.pumpAndSettle();

        expect(find.text('https://api.dev/users'), findsOneWidget);
        expect(find.text('https://api.dev/orders'), findsOneWidget);

        await tester.tap(find.text('https://api.dev/users'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('url_field')),
        );
        expect(field.controller!.text, 'https://api.dev/users');
        expect(
          bloc.state.tabs.byId('b4a')!.config.url,
          'https://api.dev/users',
          reason: 'accepting must dispatch UpdateTab with the full URL',
        );

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets('saved collection request URLs are suggested too', (
      tester,
    ) async {
      const tab = HttpRequestTabEntity(
        tabId: 'b4b',
        config: HttpRequestConfigEntity(id: 'b4b'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      const folder = CollectionNodeEntity(
        id: 'f1',
        name: 'Folder',
        children: [
          CollectionNodeEntity(
            id: 'r1',
            name: 'Req',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'r1',
              url: 'https://saved.dev/items',
            ),
          ),
        ],
      );
      final collectionsBloc = MockCollectionsBloc();
      when(
        () => collectionsBloc.state,
      ).thenReturn(CollectionsState(collections: const [folder]));
      when(
        () => collectionsBloc.stream,
      ).thenAnswer((_) => const Stream.empty());

      await _pump(tester, bloc, 'b4b', collectionsBloc: collectionsBloc);

      await tester.enterText(find.byKey(const ValueKey('url_field')), 'saved');
      await tester.pumpAndSettle();

      expect(find.text('https://saved.dev/items'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('a {{ token keeps variable mode — no URL rows', (
      tester,
    ) async {
      const tab = HttpRequestTabEntity(
        tabId: 'b4c',
        config: HttpRequestConfigEntity(id: 'b4c'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final historyBloc = _defaultHistoryBloc(const [
        HttpRequestConfigEntity(id: 'h1', url: 'https://guid.dev/api'),
      ]);

      await _pump(tester, bloc, 'b4c', historyBloc: historyBloc);

      await tester.enterText(find.byKey(const ValueKey('url_field')), '{{gu');
      await tester.pumpAndSettle();

      expect(
        find.text(r'$guid'),
        findsOneWidget,
        reason: 'variable mode (dynamic built-ins) must win inside {{',
      );
      expect(find.text('https://guid.dev/api'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('under 3 typed chars there are no URL suggestions', (
      tester,
    ) async {
      const tab = HttpRequestTabEntity(
        tabId: 'b4d',
        config: HttpRequestConfigEntity(id: 'b4d'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final historyBloc = _defaultHistoryBloc(const [
        HttpRequestConfigEntity(id: 'h1', url: 'https://api.dev/users'),
      ]);

      await _pump(tester, bloc, 'b4d', historyBloc: historyBloc);

      await tester.enterText(find.byKey(const ValueKey('url_field')), 'ap');
      await tester.pumpAndSettle();

      expect(find.text('https://api.dev/users'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    });
  });

  testWidgets(
    'SEND and save tooltips carry platform shortcut hints (macOS)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      const tab = HttpRequestTabEntity(
        tabId: 'tt1',
        collectionNodeId: 'node-1', // linked → "Update Request" face
        config: HttpRequestConfigEntity(id: 'tt1', url: 'https://x.dev'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'tt1');
      // Reset within the body: the testWidgets invariant check runs before
      // addTearDown, and it forbids a leaked foundation debug override.
      debugDefaultTargetPlatformOverride = null;

      expect(
        find.byTooltip(
          'Send — ${shortcutHint(AppShortcutAction.send, useMeta: true)}',
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Update Request — '
          '${shortcutHint(AppShortcutAction.save, useMeta: true)}',
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'save tooltip spells Ctrl on non-macOS and unlinked face persists',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      const tab = HttpRequestTabEntity(
        tabId: 'tt2',
        config: HttpRequestConfigEntity(id: 'tt2', url: 'https://x.dev'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'tt2');
      // Reset within the body: the testWidgets invariant check runs before
      // addTearDown, and it forbids a leaked foundation debug override.
      debugDefaultTargetPlatformOverride = null;

      expect(
        find.byTooltip(
          'Send — ${shortcutHint(AppShortcutAction.send, useMeta: false)}',
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Save to Collection — '
          '${shortcutHint(AppShortcutAction.save, useMeta: false)}',
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'unresolved-vars chip appears in the URL bar and SEND stays enabled',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'uv1',
        config: HttpRequestConfigEntity(id: 'uv1', url: '{{nope}}/x'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'uv1');

      expect(
        find.byKey(const ValueKey('unresolved_vars_chip')),
        findsOneWidget,
      );
      final send = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.byKey(const ValueKey('send')),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(send.onPressed, isNotNull, reason: 'chip must never block SEND');

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('CANCEL face mid-send cancels the in-flight request handle', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'c1',
      config: HttpRequestConfigEntity(id: 'c1', url: 'https://example.com'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    final completer = Completer<HttpResponseEntity>();
    NetworkCancelHandle? capturedHandle;
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((invocation) {
      capturedHandle =
          invocation.namedArguments[#cancelHandle] as NetworkCancelHandle?;
      return completer.future;
    });

    await _pump(tester, bloc, 'c1');

    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();
    expect(bloc.state.tabs.byId('c1')!.isSending, isTrue);
    expect(capturedHandle, isNotNull);
    expect(capturedHandle!.isCancelled, isFalse);

    // Mid-send the button shows the CANCEL face — pressing it must cancel
    // the handle that was passed into the use case.
    await tester.tap(find.byKey(const ValueKey('cancel')));
    await tester.pump();

    expect(
      capturedHandle!.isCancelled,
      isTrue,
      reason: 'CANCEL must dispatch CancelRequest for the in-flight handle',
    );

    completer.completeError(Exception('test-cancel'), StackTrace.current);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'code-export button opens GENERATE CODE with the live (re-read) URL',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'ce1',
        config: HttpRequestConfigEntity(id: 'ce1', url: 'https://old.dev'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'ce1');

      // Edit the URL — UrlBar's buildWhen excludes url edits, so the builder
      // snapshot goes stale. The export must re-read the live tab.
      await tester.enterText(
        find.byKey(const ValueKey('url_field')),
        'https://edited.dev/v2',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('code_export_button')));
      await tester.pumpAndSettle();

      expect(find.text('GENERATE CODE'), findsOneWidget);
      final snippet = tester.widget<SelectableText>(
        find.byKey(const ValueKey('generated_code_text')),
      );
      expect(
        snippet.data,
        contains('https://edited.dev/v2'),
        reason: 'export must use the live config, not the stale snapshot',
      );

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'layout toggle button dispatches UpdateVerticalLayout with the flipped '
    'value',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'lt1',
        config: HttpRequestConfigEntity(id: 'lt1', url: 'https://x.dev'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final settingsBloc = _defaultSettingsBloc(); // isVerticalLayout: false
      await _pump(tester, bloc, 'lt1', settingsBloc: settingsBloc);

      await tester.tap(find.byTooltip('Vertical Layout'));
      await tester.pump();

      verify(
        () => settingsBloc.add(
          const UpdateVerticalLayout(isVerticalLayout: true),
        ),
      ).called(1);

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('MCP kind shows the MCP connect button instead of SEND', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'm1',
      config: HttpRequestConfigEntity(
        id: 'm1',
        url: 'https://mcp.example.com',
        kind: RequestKind.mcp,
      ),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'm1');

    expect(find.byKey(const ValueKey('mcp_connect_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('send')), findsNothing);
    expect(find.byKey(const ValueKey('realtime_connect_button')), findsNothing);

    await tester.pump(const Duration(seconds: 11));
  });

  group('narrow-width overflow menu', () {
    testWidgets(
      'collapses code/save/layout buttons; SAVE TO COLLECTION invokes onSave',
      (tester) async {
        const tab = HttpRequestTabEntity(
          tabId: 'n1',
          config: HttpRequestConfigEntity(id: 'n1', url: 'https://x.dev'),
        );
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);

        var saved = false;
        await _pump(tester, bloc, 'n1', width: 520, onSave: () => saved = true);

        // The three wide-layout buttons collapse behind "More actions".
        expect(find.byKey(const ValueKey('code_export_button')), findsNothing);
        expect(find.byKey(const ValueKey('save_request_button')), findsNothing);
        expect(find.byTooltip('More actions'), findsOneWidget);

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SAVE TO COLLECTION'));
        await tester.pumpAndSettle();

        expect(saved, isTrue, reason: 'overflow SAVE must call onSave');

        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'GENERATE CODE opens the dialog and the layout entry dispatches '
      'UpdateVerticalLayout',
      (tester) async {
        const tab = HttpRequestTabEntity(
          tabId: 'n2',
          config: HttpRequestConfigEntity(id: 'n2', url: 'https://nrw.dev'),
        );
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);

        final settingsBloc = _defaultSettingsBloc(); // isVerticalLayout: false
        await _pump(
          tester,
          bloc,
          'n2',
          width: 520,
          settingsBloc: settingsBloc,
        );

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GENERATE CODE'));
        await tester.pumpAndSettle();

        expect(find.text('GENERATE CODE'), findsOneWidget);
        final snippet = tester.widget<SelectableText>(
          find.byKey(const ValueKey('generated_code_text')),
        );
        expect(snippet.data, contains('https://nrw.dev'));

        await tester.tap(find.text('CLOSE'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('VERTICAL LAYOUT'));
        await tester.pumpAndSettle();

        verify(
          () => settingsBloc.add(
            const UpdateVerticalLayout(isVerticalLayout: true),
          ),
        ).called(1);

        await tester.pump(const Duration(seconds: 11));
      },
    );
  });

  testWidgets(
    'hovering a {{var}} token shows the layered resolution popover '
    '(collection var wins over nothing, env label shown)',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'hp1',
        collectionNodeId: 'req1',
        config: HttpRequestConfigEntity(
          id: 'hp1',
          url: 'https://{{base}}/path',
        ),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      const folder = CollectionNodeEntity(
        id: 'folder1',
        name: 'Folder',
        variables: {'base': 'collection.example.com'},
        children: [
          CollectionNodeEntity(id: 'req1', name: 'Req', isFolder: false),
        ],
      );
      final collectionsBloc = MockCollectionsBloc();
      when(
        () => collectionsBloc.state,
      ).thenReturn(CollectionsState(collections: const [folder]));
      when(
        () => collectionsBloc.stream,
      ).thenAnswer((_) => const Stream.empty());

      await _pump(tester, bloc, 'hp1', collectionsBloc: collectionsBloc);

      // Drive the highlight controller's hover callback directly (the same
      // sink the field's token hit-testing feeds) — pointer-positioning over
      // a specific painted token is not reproducible across font rasters.
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('url_field')),
      );
      final controller = field.controller! as VariableHighlightController;
      controller.onVariableEnter!('base', const Offset(200, 40));
      await tester.pump();

      expect(find.text('{{base}}'), findsOneWidget);
      expect(find.text('collection.example.com'), findsOneWidget);

      // Leaving the token schedules the delayed hide.
      controller.onVariableExit!();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('{{base}}'), findsNothing);

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('curl paste with a JSON body prettifies the body off-thread', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'cb1',
      config: HttpRequestConfigEntity(id: 'cb1'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'cb1');

    await tester.enterText(
      find.byKey(const ValueKey('url_field')),
      'curl -X POST https://example.com -d \'{"a":1}\'',
    );
    await tester.pump();
    // prettify() hops to a REAL isolate via compute(); fake-async pumps never
    // advance it, so poll under real async until the prettified body lands.
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (bloc.state.tabs.byId('cb1')!.config.body.contains('\n')) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    final updated = bloc.state.tabs.byId('cb1')!.config;
    expect(updated.method, 'POST');
    expect(
      updated.body,
      contains('\n'),
      reason: 'the parsed body must arrive prettified, not single-line',
    );
    expect(updated.body, contains('"a": 1'));

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
    'environment/settings/collections emissions re-sync {{var}} highlighting',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'ls1',
        config: HttpRequestConfigEntity(
          id: 'ls1',
          url: 'https://{{base}}/path',
        ),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final envController = StreamController<EnvironmentsState>.broadcast();
      final settingsController = StreamController<SettingsState>.broadcast();
      final collectionsController =
          StreamController<CollectionsState>.broadcast();
      addTearDown(envController.close);
      addTearDown(settingsController.close);
      addTearDown(collectionsController.close);

      final envBloc = MockEnvironmentsBloc();
      when(() => envBloc.state).thenReturn(const EnvironmentsState());
      when(() => envBloc.stream).thenAnswer((_) => envController.stream);

      final settingsBloc = MockSettingsBloc();
      when(
        () => settingsBloc.state,
      ).thenReturn(const SettingsState(settings: SettingsEntity()));
      when(
        () => settingsBloc.stream,
      ).thenAnswer((_) => settingsController.stream);

      final collectionsBloc = MockCollectionsBloc();
      when(() => collectionsBloc.state).thenReturn(CollectionsState());
      when(
        () => collectionsBloc.stream,
      ).thenAnswer((_) => collectionsController.stream);

      await _pump(
        tester,
        bloc,
        'ls1',
        envBloc: envBloc,
        settingsBloc: settingsBloc,
        collectionsBloc: collectionsBloc,
      );

      VariableHighlightController urlController() =>
          tester
                  .widget<TextField>(find.byKey(const ValueKey('url_field')))
                  .controller!
              as VariableHighlightController;

      expect(urlController().variables.containsKey('base'), isFalse);

      // 1. Environments change: the env now exists, but no active id yet.
      final env = EnvironmentEntity(
        id: 'e1',
        name: 'Dev',
        variables: const {'base': 'env.example.com'},
      );
      final envState = EnvironmentsState(environments: [env]);
      when(() => envBloc.state).thenReturn(envState);
      envController.add(envState);
      await tester.pump();
      expect(
        urlController().variables.containsKey('base'),
        isFalse,
        reason: 'no active environment id yet',
      );

      // 2. Settings change: activating the environment must re-sync.
      const activeSettings = SettingsState(
        settings: SettingsEntity(activeEnvironmentId: 'e1'),
      );
      when(() => settingsBloc.state).thenReturn(activeSettings);
      settingsController.add(activeSettings);
      await tester.pump();
      expect(
        urlController().variables['base'],
        'env.example.com',
        reason: 'activating an environment must re-color the URL tokens',
      );

      // 3. Collections change: the listener re-syncs without breaking the
      // already-resolved env layer.
      final collState = CollectionsState(
        collections: const [CollectionNodeEntity(id: 'f1', name: 'F')],
      );
      when(() => collectionsBloc.state).thenReturn(collState);
      collectionsController.add(collState);
      await tester.pump();
      expect(urlController().variables['base'], 'env.example.com');

      await tester.pump(const Duration(seconds: 11));
    },
  );
}
