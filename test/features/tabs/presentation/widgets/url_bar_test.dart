// Widget tests for UrlBar: URL field and SEND button presence, cURL paste
// auto-parse, SEND button marks tab as isSending, and WS/SSE shows
// RealtimeButton instead. Uses a real TabsBloc with mocked repository +
// use case, plus mock blocs for EnvironmentsBloc/SettingsBloc/CollectionsBloc/
// RealtimeBloc.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
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
import 'package:getman/features/tabs/presentation/widgets/url_bar.dart';
import 'package:mocktail/mocktail.dart';

// Real bloc mocks.
class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

// Stub blocs — we only need state + stream (no dispatch needed from test code).
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
  return b;
}

MockCollectionsBloc _defaultCollectionsBloc() {
  final b = MockCollectionsBloc();
  when(() => b.state).thenReturn(CollectionsState());
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

Future<void> _pump(
  WidgetTester tester,
  TabsBloc bloc,
  String tabId, {
  MockEnvironmentsBloc? envBloc,
  MockSettingsBloc? settingsBloc,
  MockCollectionsBloc? collectionsBloc,
  MockRealtimeBloc? realtimeBloc,
}) async {
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
            ],
            child: UrlBar(tabId: tabId, onSave: () {}),
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
}
