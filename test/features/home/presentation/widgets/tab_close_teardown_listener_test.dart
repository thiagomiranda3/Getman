// Widget tests for TabCloseTeardownListener: when tab ids disappear from
// TabsBloc's panels (close, close-others, panel close), it dispatches
// RealtimeTabsClosed / McpTabsClosed for the closed ids that hold a live
// realtime/MCP session — and stays silent for moves between panels (same id
// union) and for closed tabs with no session. Recording fakes capture the
// exact events dispatched.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/home/presentation/widgets/tab_close_teardown_listener.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Controllable TabsBloc: tests seed an initial state and push follow-ups so
/// the listener's prev/next comparison is driven directly.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  void push(TabsState next) => emit(next);

  @override
  bool get canReopenClosedTab => false;

  @override
  Future<void> flushPendingSaves() async {}
}

/// Records added events instead of running handlers, so tests assert the
/// exact teardown event the listener dispatches (or that none was).
class _RecordingRealtimeBloc extends Bloc<RealtimeEvent, RealtimeState>
    implements RealtimeBloc {
  _RecordingRealtimeBloc(super.initialState);

  final added = <RealtimeEvent>[];

  @override
  void add(RealtimeEvent event) => added.add(event);
}

class _RecordingMcpBloc extends Bloc<McpEvent, McpState> implements McpBloc {
  _RecordingMcpBloc(super.initialState);

  final added = <McpEvent>[];

  @override
  void add(McpEvent event) => added.add(event);
}

const _t1 = HttpRequestTabEntity(
  tabId: 't1',
  config: HttpRequestConfigEntity(id: 't1'),
);
const _t2 = HttpRequestTabEntity(
  tabId: 't2',
  config: HttpRequestConfigEntity(id: 't2'),
);

TabsState _panelsState(List<PanelEntity> panels) =>
    TabsState(panels: panels, activePanelId: panels.first.id);

PanelEntity _panel(String id, List<HttpRequestTabEntity> tabs) => PanelEntity(
  id: id,
  name: 'Panel $id',
  tabs: tabs,
  activeTabId: tabs.isEmpty ? '' : tabs.first.tabId,
);

void main() {
  late _FakeTabsBloc tabsBloc;
  late _RecordingRealtimeBloc realtimeBloc;
  late _RecordingMcpBloc mcpBloc;

  Future<void> pumpListener(
    WidgetTester tester, {
    RealtimeState realtimeState = const RealtimeState(),
    McpState mcpState = const McpState(),
  }) async {
    tabsBloc = _FakeTabsBloc(
      _panelsState([
        _panel('p1', [_t1, _t2]),
      ]),
    );
    addTearDown(tabsBloc.close);
    realtimeBloc = _RecordingRealtimeBloc(realtimeState);
    addTearDown(realtimeBloc.close);
    mcpBloc = _RecordingMcpBloc(mcpState);
    addTearDown(mcpBloc.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<RealtimeBloc>.value(value: realtimeBloc),
          BlocProvider<McpBloc>.value(value: mcpBloc),
        ],
        child: const TabCloseTeardownListener(child: SizedBox()),
      ),
    );
  }

  testWidgets(
    'closing a tab with a realtime session dispatches RealtimeTabsClosed '
    'for it — and leaves an McpBloc whose sessions all survive alone',
    (tester) async {
      await pumpListener(
        tester,
        realtimeState: const RealtimeState(
          sessions: {'t1': RealtimeSession(connected: true)},
        ),
        mcpState: const McpState(
          sessions: {
            't2': McpTabSession(status: McpConnectionStatus.connected),
          },
        ),
      );

      // t1 closes; only t2 remains.
      tabsBloc.push(
        _panelsState([
          _panel('p1', [_t2]),
        ]),
      );
      await tester.pump();

      expect(realtimeBloc.added, const [
        RealtimeTabsClosed({'t1'}),
      ]);
      expect(
        mcpBloc.added,
        isEmpty,
        reason: "mcp's only session (t2) is still open — nothing to tear down",
      );
    },
  );

  testWidgets(
    'closing a tab with an MCP session dispatches McpTabsClosed for it',
    (tester) async {
      await pumpListener(
        tester,
        mcpState: const McpState(
          sessions: {
            't1': McpTabSession(status: McpConnectionStatus.connected),
          },
        ),
      );

      tabsBloc.push(
        _panelsState([
          _panel('p1', [_t2]),
        ]),
      );
      await tester.pump();

      expect(mcpBloc.added, const [
        McpTabsClosed({'t1'}),
      ]);
      expect(realtimeBloc.added, isEmpty);
    },
  );

  testWidgets(
    'a move between panels (same union of tab ids) dispatches nothing',
    (tester) async {
      await pumpListener(
        tester,
        realtimeState: const RealtimeState(
          sessions: {'t1': RealtimeSession(connected: true)},
        ),
        mcpState: const McpState(
          sessions: {
            't1': McpTabSession(status: McpConnectionStatus.connected),
          },
        ),
      );

      // t1 moves from p1 to a new p2 — every id stays alive in the union.
      tabsBloc.push(
        _panelsState([
          _panel('p1', [_t2]),
          _panel('p2', [_t1]),
        ]),
      );
      await tester.pump();

      expect(realtimeBloc.added, isEmpty);
      expect(mcpBloc.added, isEmpty);
    },
  );

  testWidgets(
    'closing a tab that holds no realtime or MCP session dispatches nothing',
    (tester) async {
      await pumpListener(tester);

      tabsBloc.push(
        _panelsState([
          _panel('p1', [_t2]),
        ]),
      );
      await tester.pump();

      expect(realtimeBloc.added, isEmpty);
      expect(mcpBloc.added, isEmpty);
    },
  );
}
