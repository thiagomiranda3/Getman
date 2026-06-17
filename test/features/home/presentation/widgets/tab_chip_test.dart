import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/home/presentation/widgets/tab_chip.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

HttpRequestTabEntity _tab(String id) => HttpRequestTabEntity(
  tabId: id,
  config: HttpRequestConfigEntity(id: id),
);

PanelEntity _panel(String id, String name, List<String> tabIds) => PanelEntity(
  id: id,
  name: name,
  tabs: [for (final t in tabIds) _tab(t)],
  activeTabId: tabIds.first,
);

Widget _host(TabsBloc bloc) {
  return MaterialApp(
    theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
    home: Scaffold(
      body: BlocProvider<TabsBloc>.value(
        value: bloc,
        child: TabChip(
          onRequestClose: (context, tabId) async => true,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
  });

  late MockTabsBloc bloc;

  setUp(() {
    bloc = MockTabsBloc();
  });

  testWidgets('shows panel name and counter in badge — Panel 1 · 1/1 ▾', (
    tester,
  ) async {
    final panel = _panel('p1', 'Panel 1', ['t1']);
    final state = TabsState(
      panels: [panel],
      activePanelId: 'p1',
      tabs: panel.tabs,
    );
    when(() => bloc.state).thenReturn(state);

    await tester.pumpWidget(_host(bloc));

    // The badge shows "Panel 1 · 1/1 ▾"
    expect(find.text('Panel 1 · 1/1 ▾'), findsOneWidget);
  });

  testWidgets('shows panel name with correct counter for second tab', (
    tester,
  ) async {
    final panel = _panel('p1', 'Panel 1', ['t1', 't2', 't3', 't4', 't5']);
    final state = TabsState(
      panels: [panel],
      activePanelId: 'p1',
      tabs: panel.tabs,
      activeIndex: 1, // second tab (2/5)
    );
    when(() => bloc.state).thenReturn(state);

    await tester.pumpWidget(_host(bloc));

    // The badge shows "Panel 1 · 2/5 ▾"
    expect(find.text('Panel 1 · 2/5 ▾'), findsOneWidget);
  });

  testWidgets('shows "0" when there are no tabs', (tester) async {
    const state = TabsState();
    when(() => bloc.state).thenReturn(state);

    await tester.pumpWidget(_host(bloc));

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('shows active tab title next to the badge', (tester) async {
    final panel = _panel('p1', 'Panel 1', ['t1']);
    final state = TabsState(
      panels: [panel],
      activePanelId: 'p1',
      tabs: panel.tabs,
    );
    when(() => bloc.state).thenReturn(state);

    await tester.pumpWidget(_host(bloc));

    // The active tab's displayTitle should appear as separate text
    expect(find.text(panel.tabs.first.displayTitle), findsOneWidget);
  });

  testWidgets('uses the active panel name from state.activePanel', (
    tester,
  ) async {
    final panel1 = _panel('p1', 'Personal', ['t1']);
    final panel2 = _panel('p2', 'Work', ['t2']);
    final state = TabsState(
      panels: [panel1, panel2],
      activePanelId: 'p2', // Work panel is active
      tabs: panel2.tabs,
    );
    when(() => bloc.state).thenReturn(state);

    await tester.pumpWidget(_host(bloc));

    expect(find.text('Work · 1/1 ▾'), findsOneWidget);
  });
}
