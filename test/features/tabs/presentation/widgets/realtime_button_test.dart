// Widget tests for RealtimeButton: CONNECT/DISCONNECT state, stale-URL
// regression guard (button reads current tab URL at press time, not the
// constructor-captured config), and Disconnect dispatch. Uses a real TabsBloc
// for the stale-URL test and a mock RealtimeBloc throughout.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/realtime_button.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockRealtimeBloc extends Mock implements RealtimeBloc {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

class _FakeRealtimeEvent extends Fake implements RealtimeEvent {}

Future<TabsBloc> _loadedTabsBloc(
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

MockRealtimeBloc _buildRealtimeBloc({
  bool connected = false,
  String tabId = 'rt',
}) {
  final mock = MockRealtimeBloc();
  final session = connected
      ? const RealtimeSession(connected: true)
      : const RealtimeSession();
  final state = RealtimeState(
    sessions: connected ? {tabId: session} : const {},
  );
  when(() => mock.state).thenReturn(state);
  when(() => mock.stream).thenAnswer((_) => const Stream.empty());
  when(() => mock.add(any())).thenReturn(null);
  return mock;
}

Future<void> _pump(
  WidgetTester tester, {
  required TabsBloc tabsBloc,
  required MockRealtimeBloc realtimeBloc,
  required String tabId,
  required HttpRequestConfigEntity config,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<RealtimeBloc>.value(value: realtimeBloc),
          ],
          child: RealtimeButton(
            tabId: tabId,
            config: config,
            isNarrow: false,
            activeVars: const {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
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

  testWidgets('shows CONNECT when not connected', (tester) async {
    const tabId = 'rt1';
    const config = HttpRequestConfigEntity(
      id: tabId,
      url: 'ws://example.com',
      kind: RequestKind.webSocket,
    );
    const tab = HttpRequestTabEntity(tabId: tabId, config: config);
    final tabsBloc = await _loadedTabsBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    final realtimeBloc = _buildRealtimeBloc(tabId: tabId);

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      realtimeBloc: realtimeBloc,
      tabId: tabId,
      config: config,
    );

    expect(find.text('CONNECT'), findsOneWidget);
    expect(find.text('DISCONNECT'), findsNothing);
  });

  testWidgets('shows DISCONNECT when connected', (tester) async {
    const tabId = 'rt2';
    const config = HttpRequestConfigEntity(
      id: tabId,
      url: 'ws://example.com',
      kind: RequestKind.webSocket,
    );
    const tab = HttpRequestTabEntity(tabId: tabId, config: config);
    final tabsBloc = await _loadedTabsBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    final realtimeBloc = _buildRealtimeBloc(connected: true, tabId: tabId);

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      realtimeBloc: realtimeBloc,
      tabId: tabId,
      config: config,
    );

    expect(find.text('DISCONNECT'), findsOneWidget);
    expect(find.text('CONNECT'), findsNothing);
  });

  testWidgets(
    'CONNECT reads current tab URL not stale config — regression guard',
    (tester) async {
      const tabId = 'rt3';
      const initialConfig = HttpRequestConfigEntity(
        id: tabId,
        url: 'ws://initial',
        kind: RequestKind.webSocket,
      );
      const tab = HttpRequestTabEntity(
        tabId: tabId,
        config: initialConfig,
      );
      final tabsBloc = await _loadedTabsBloc(
        repository,
        sendRequestUseCase,
        tab,
      );
      addTearDown(tabsBloc.close);

      final realtimeBloc = _buildRealtimeBloc(tabId: tabId);

      // Pump with the initial config.
      await _pump(
        tester,
        tabsBloc: tabsBloc,
        realtimeBloc: realtimeBloc,
        tabId: tabId,
        config: initialConfig,
      );

      // Now update the tab URL via the bloc (simulates user editing URL bar).
      final updatedConfig = initialConfig.copyWith(url: 'ws://updated');
      final updatedTab = tab.copyWith(config: updatedConfig);
      tabsBloc.add(UpdateTab(updatedTab));
      await tester.pump(); // let the event process

      // Tap CONNECT.
      await tester.tap(find.byKey(const ValueKey('realtime_connect_button')));
      await tester.pumpAndSettle();

      // Capture the Connect event.
      final captured = verify(() => realtimeBloc.add(captureAny())).captured;
      expect(captured, isNotEmpty);
      final connectEvent = captured.whereType<Connect>().first;
      expect(connectEvent.url, 'ws://updated');

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets('tapping DISCONNECT dispatches Disconnect event', (tester) async {
    const tabId = 'rt4';
    const config = HttpRequestConfigEntity(
      id: tabId,
      url: 'ws://example.com',
      kind: RequestKind.webSocket,
    );
    const tab = HttpRequestTabEntity(tabId: tabId, config: config);
    final tabsBloc = await _loadedTabsBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    final realtimeBloc = _buildRealtimeBloc(connected: true, tabId: tabId);

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      realtimeBloc: realtimeBloc,
      tabId: tabId,
      config: config,
    );

    await tester.tap(find.byKey(const ValueKey('realtime_connect_button')));
    await tester.pumpAndSettle();

    verify(() => realtimeBloc.add(any(that: isA<Disconnect>()))).called(1);
  });

  testWidgets('no overflow', (tester) async {
    const tabId = 'rt5';
    const config = HttpRequestConfigEntity(
      id: tabId,
      url: 'ws://example.com',
      kind: RequestKind.webSocket,
    );
    const tab = HttpRequestTabEntity(tabId: tabId, config: config);
    final tabsBloc = await _loadedTabsBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    final realtimeBloc = _buildRealtimeBloc(tabId: tabId);

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      realtimeBloc: realtimeBloc,
      tabId: tabId,
      config: config,
    );

    expect(tester.takeException(), isNull);
  });
}
