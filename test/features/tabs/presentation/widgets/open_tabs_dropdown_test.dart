// Widget tests for the D1 desktop open-tabs dropdown: opens grouped by
// panel, search filters by name/method/url, clicking a row activates
// panel + tab, Esc closes, dirty tabs show the star.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/open_tabs_dropdown.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

HttpRequestTabEntity _tab(
  String id, {
  String method = 'GET',
  String url = '',
}) => HttpRequestTabEntity(
  tabId: id,
  config: HttpRequestConfigEntity(id: id, method: method, url: url),
);

TabsState _twoPanelState() {
  final p1 = PanelEntity(
    id: 'p1',
    name: 'Main',
    tabs: [_tab('t1', url: 'https://a.dev/users')],
    activeTabId: 't1',
  );
  final p2 = PanelEntity(
    id: 'p2',
    name: 'Work',
    tabs: [
      _tab('t2', method: 'POST', url: 'https://b.dev/orders'),
      _tab('t3'),
    ],
    activeTabId: 't2',
  );
  return TabsState(panels: [p1, p2], activePanelId: 'p1', tabs: p1.tabs);
}

Widget _host(TabsBloc tabs, CollectionsBloc collections) {
  return MaterialApp(
    theme: resolveTheme('brutalist')(Brightness.light, isCompact: false),
    home: Scaffold(
      body: RepositoryProvider<TabDirtyChecker>.value(
        value: const TabDirtyChecker(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<CollectionsBloc>.value(value: collections),
          ],
          child: const Align(
            alignment: Alignment.topRight,
            child: OpenTabsDropdown(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
  });

  late MockTabsBloc tabs;
  late MockCollectionsBloc collections;

  setUp(() {
    tabs = MockTabsBloc();
    collections = MockCollectionsBloc();
    when(() => tabs.state).thenReturn(_twoPanelState());
    when(() => collections.state).thenReturn(CollectionsState());
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(_host(tabs, collections));
    await tester.tap(find.byKey(const ValueKey('open_tabs_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('button opens a dropdown of all open tabs grouped by panel', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('MAIN'), findsOneWidget);
    expect(find.text('WORK'), findsOneWidget);
    expect(find.byKey(const ValueKey('open_tabs_row_t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('open_tabs_row_t2')), findsOneWidget);
    expect(find.byKey(const ValueKey('open_tabs_row_t3')), findsOneWidget);
  });

  testWidgets('search filters rows by method and drops empty panel groups', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('open_tabs_search_field')),
      'post',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open_tabs_row_t2')), findsOneWidget);
    expect(find.byKey(const ValueKey('open_tabs_row_t1')), findsNothing);
    expect(find.byKey(const ValueKey('open_tabs_row_t3')), findsNothing);
    expect(find.text('MAIN'), findsNothing);
  });

  testWidgets(
    'clicking a row activates its panel then its tab (panel-relative index)',
    (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const ValueKey('open_tabs_row_t3')));
      await tester.pumpAndSettle();

      verifyInOrder([
        () => tabs.add(const SetActivePanel('p2')),
        () => tabs.add(const SetActiveIndex(1)),
      ]);
      // Menu closed after activation.
      expect(
        find.byKey(const ValueKey('open_tabs_search_field')),
        findsNothing,
      );
    },
  );

  testWidgets('Esc closes the dropdown', (tester) async {
    await open(tester);
    expect(
      find.byKey(const ValueKey('open_tabs_search_field')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open_tabs_search_field')), findsNothing);
  });

  testWidgets('dirty tabs show the star, pristine tabs do not', (tester) async {
    await open(tester);

    // t2 is unlinked with a non-default config (URL set) -> dirty per
    // TabDirtyChecker; t3 is unlinked and pristine -> clean.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open_tabs_row_t2')),
        matching: find.text('*'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open_tabs_row_t3')),
        matching: find.text('*'),
      ),
      findsNothing,
    );
  });
}
