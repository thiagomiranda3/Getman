// Widget tests for RequestView: renders url bar, SEND button, no overflow,
// and clamp behavior with extreme split-ratio settings. Uses a real TabsBloc
// with mocked repository + use case, plus mock blocs for the surrounding
// features.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
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
import 'package:getman/features/tabs/presentation/widgets/response_area.dart';
import 'package:mocktail/mocktail.dart';

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
}) async {
  await tester.pumpWidget(
    RepositoryProvider<UrlFocusRegistry>(
      create: (_) => UrlFocusRegistry(),
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
}
