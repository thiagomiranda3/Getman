// Widget tests for HistoryList: renders entries, tap opens a tab, search
// filters results, empty state shows the placeholder.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/history/presentation/widgets/history_list.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

class _FakeHistoryEvent extends Fake implements HistoryEvent {}

HttpRequestConfigEntity _config(String id, {String method = 'GET'}) =>
    HttpRequestConfigEntity(
      id: id,
      url: 'https://example.com/$id',
      method: method,
    );

Widget _host({
  required HistoryBloc historyBloc,
  required TabsBloc tabsBloc,
}) {
  return MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
        ],
        child: const HistoryList(),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(_FakeHistoryEvent());
  });

  late MockHistoryBloc historyBloc;
  late MockTabsBloc tabsBloc;

  setUp(() {
    historyBloc = MockHistoryBloc();
    tabsBloc = MockTabsBloc();
    when(() => tabsBloc.state).thenReturn(const TabsState());
  });

  testWidgets('renders history entries from state', (tester) async {
    final c1 = _config('1');
    final c2 = _config('2');
    when(() => historyBloc.state).thenReturn(
      HistoryState(history: [c1, c2]),
    );

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('https://example.com/1'), findsOneWidget);
    expect(find.text('https://example.com/2'), findsOneWidget);
  });

  testWidgets('renders entries in newest-first order (state index 0 at top)', (
    tester,
  ) async {
    // The repository reverses insertion order, so the state list is
    // newest-first: index 0 = newest. The widget must preserve this order.
    final newest = _config('newest');
    final older = _config('older');
    when(() => historyBloc.state).thenReturn(
      HistoryState(history: [newest, older]), // newest first, as the repo gives
    );

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final newestFinder = find.text('https://example.com/newest');
    final olderFinder = find.text('https://example.com/older');
    expect(newestFinder, findsOneWidget);
    expect(olderFinder, findsOneWidget);

    // The newest entry's top edge must be above the older entry's top edge.
    final newestTop = tester.getTopLeft(newestFinder).dy;
    final olderTop = tester.getTopLeft(olderFinder).dy;
    expect(newestTop, lessThan(olderTop));
  });

  testWidgets('tapping an entry dispatches AddTab with the config', (
    tester,
  ) async {
    final c1 = _config('t1');
    when(() => historyBloc.state).thenReturn(
      HistoryState(history: [c1]),
    );

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('https://example.com/t1'));
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => tabsBloc.add(any(that: isA<AddTab>()))).called(1);
  });

  testWidgets('search filters entries matching the query', (tester) async {
    final cGet = _config('get-req');
    final cPost = _config('post-req', method: 'POST');
    when(() => historyBloc.state).thenReturn(
      HistoryState(history: [cGet, cPost]),
    );

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Type in the search field and wait for the Debouncer to flush.
    await tester.enterText(
      find.byKey(const ValueKey('history_search_field')),
      'get-req',
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('https://example.com/get-req'), findsOneWidget);
    expect(find.text('https://example.com/post-req'), findsNothing);
  });

  testWidgets('empty history shows NO RESULTS FOUND', (tester) async {
    when(() => historyBloc.state).thenReturn(const HistoryState());

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('NO RESULTS FOUND'), findsOneWidget);
  });

  testWidgets(
    'shows loading indicator when state is loading with no history',
    (tester) async {
      when(() => historyBloc.state).thenReturn(
        const HistoryState(isLoading: true),
      );

      await tester.pumpWidget(
        _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );
}
