// Widget tests for HistoryList: renders entries, tap opens a tab, search
// filters results, day-header grouping/ordering (TODAY/YESTERDAY), hover
// delete + UNDO tap-through (restores the captured record via
// RestoreHistoryEntries), CLEAR ALL confirm + UNDO tap-through (restores the
// captured list), and the two distinct empty states — first-run guidance
// ('NO REQUESTS SENT YET') vs. a search miss ('NO RESULTS FOUND').

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
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

HttpRequestConfigEntity _config(
  String id, {
  String method = 'GET',
  DateTime? sentAt,
}) => HttpRequestConfigEntity(
  id: id,
  url: 'https://example.com/$id',
  method: method,
  sentAt: sentAt,
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

  testWidgets('fresh empty history shows the first-run guidance', (
    tester,
  ) async {
    when(() => historyBloc.state).thenReturn(const HistoryState());

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('NO REQUESTS SENT YET'), findsOneWidget);
    expect(
      find.text('Sent requests appear here automatically.'),
      findsOneWidget,
    );
    expect(find.text('NO RESULTS FOUND'), findsNothing);
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

  testWidgets('search with no match keeps NO RESULTS FOUND', (tester) async {
    when(() => historyBloc.state).thenReturn(
      HistoryState(history: [_config('only')]),
    );

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(
      find.byKey(const ValueKey('history_search_field')),
      'zzz-no-match',
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('NO RESULTS FOUND'), findsOneWidget);
    expect(find.text('NO REQUESTS SENT YET'), findsNothing);
  });

  testWidgets('rows group under TODAY / YESTERDAY day headers', (
    tester,
  ) async {
    final now = DateTime.now();
    when(() => historyBloc.state).thenReturn(
      HistoryState(
        history: [
          _config('t', sentAt: now),
          _config('y', sentAt: now.subtract(const Duration(hours: 24))),
        ],
      ),
    );

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    // TODAY header sits above the today row, which sits above YESTERDAY.
    expect(
      tester.getTopLeft(find.text('TODAY')).dy,
      lessThan(tester.getTopLeft(find.text('YESTERDAY')).dy),
    );
  });

  testWidgets('hover delete dispatches DeleteHistoryEntry and UNDO restores', (
    tester,
  ) async {
    final c1 = _config('del-1', sentAt: DateTime.now());
    when(() => historyBloc.state).thenReturn(HistoryState(history: [c1]));

    await tester.pumpWidget(
      _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // The ✕ only appears on hover.
    expect(
      find.byKey(const ValueKey('history_delete_del-1')),
      findsNothing,
    );
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('del-1'))),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('history_delete_del-1')));
    await tester.pumpAndSettle();

    verify(
      () => historyBloc.add(const DeleteHistoryEntry('del-1')),
    ).called(1);

    // UNDO snackbar restores the captured record.
    expect(find.text('UNDO'), findsOneWidget);
    await tester.tap(find.text('UNDO'));
    await tester.pump();
    final restored = verify(
      () => historyBloc.add(captureAny(that: isA<RestoreHistoryEntries>())),
    ).captured;
    expect(
      (restored.single as RestoreHistoryEntries).entries.single.id,
      'del-1',
    );
  });

  testWidgets(
    'CLEAR ALL confirms, dispatches ClearHistory, and UNDO restores the '
    'captured list',
    (tester) async {
      final c1 = _config('c1', sentAt: DateTime.now());
      when(() => historyBloc.state).thenReturn(HistoryState(history: [c1]));

      await tester.pumpWidget(
        _host(historyBloc: historyBloc, tabsBloc: tabsBloc),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('history_clear_all')));
      await tester.pumpAndSettle();
      expect(find.text('CLEAR ALL HISTORY'), findsOneWidget);

      await tester.tap(find.text('CLEAR'));
      await tester.pumpAndSettle();
      verify(() => historyBloc.add(const ClearHistory())).called(1);

      await tester.tap(find.text('UNDO'));
      await tester.pump();
      final restored = verify(
        () => historyBloc.add(captureAny(that: isA<RestoreHistoryEntries>())),
      ).captured;
      expect(
        (restored.single as RestoreHistoryEntries).entries.single.id,
        'c1',
      );
    },
  );
}
