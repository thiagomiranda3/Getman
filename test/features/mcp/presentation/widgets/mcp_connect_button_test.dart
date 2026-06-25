// Widget tests for McpConnectButton: CONNECT/DISCONNECT state, dispatch on
// press. Mirrors realtime_button_test.dart in structure.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_connect_button.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class _MockTabsRepository extends Mock implements TabsRepository {}

class _MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockMcpBloc extends Mock implements McpBloc {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

class _FakeMcpEvent extends Fake implements McpEvent {}

Future<TabsBloc> _loadedTabsBloc(
  _MockTabsRepository repository,
  _MockSendRequestUseCase useCase,
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

_MockMcpBloc _buildMcpBloc({
  String tabId = 'mc',
  McpConnectionStatus status = McpConnectionStatus.disconnected,
}) {
  final mock = _MockMcpBloc();
  final session = McpTabSession(status: status);
  final state = McpState(
    sessions: status == McpConnectionStatus.disconnected
        ? const {}
        : {tabId: session},
  );
  when(() => mock.state).thenReturn(state);
  when(() => mock.stream).thenAnswer((_) => const Stream.empty());
  when(() => mock.add(any())).thenReturn(null);
  return mock;
}

Future<void> _pump(
  WidgetTester tester, {
  required TabsBloc tabsBloc,
  required _MockMcpBloc mcpBloc,
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
            BlocProvider<McpBloc>.value(value: mcpBloc),
          ],
          child: McpConnectButton(
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
  late _MockTabsRepository repository;
  late _MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(_FakeMcpEvent());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(
      const McpConnectRequested(tabId: 'x', url: 'https://x'),
    );
    registerFallbackValue(const McpDisconnectRequested('x'));
  });

  setUp(() {
    repository = _MockTabsRepository();
    sendRequestUseCase = _MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
  });

  testWidgets('shows CONNECT when disconnected and dispatches connect', (
    tester,
  ) async {
    const tabId = 'mc1';
    const config = HttpRequestConfigEntity(
      id: tabId,
      url: 'https://mcp.dev/',
      kind: RequestKind.mcp,
    );
    const tab = HttpRequestTabEntity(tabId: tabId, config: config);
    final tabsBloc = await _loadedTabsBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    final mcpBloc = _buildMcpBloc(tabId: tabId);

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      mcpBloc: mcpBloc,
      tabId: tabId,
      config: config,
    );

    expect(find.text('CONNECT'), findsOneWidget);
    expect(find.text('DISCONNECT'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mcp_connect_button')));
    await tester.pump();

    verify(
      () => mcpBloc.add(any(that: isA<McpConnectRequested>())),
    ).called(1);
  });

  testWidgets('shows DISCONNECT when connected', (tester) async {
    const tabId = 'mc2';
    const config = HttpRequestConfigEntity(
      id: tabId,
      url: 'https://mcp.dev/',
      kind: RequestKind.mcp,
    );
    const tab = HttpRequestTabEntity(tabId: tabId, config: config);
    final tabsBloc = await _loadedTabsBloc(repository, sendRequestUseCase, tab);
    addTearDown(tabsBloc.close);

    final mcpBloc = _buildMcpBloc(
      tabId: tabId,
      status: McpConnectionStatus.connected,
    );

    await _pump(
      tester,
      tabsBloc: tabsBloc,
      mcpBloc: mcpBloc,
      tabId: tabId,
      config: config,
    );

    expect(find.text('DISCONNECT'), findsOneWidget);
    expect(find.text('CONNECT'), findsNothing);
  });
}
