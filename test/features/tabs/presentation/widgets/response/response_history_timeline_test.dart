// Widget tests for ResponseHistoryTimeline: hidden when < 2 entries,
// visible with 2+, tapping an entry dispatches ViewResponseHistoryEntry, and
// the viewed entry is tracked BY ID (viewedHistoryEntryId) so value-equal
// responses in the history still highlight the picked row (G2).
// Uses a real TabsBloc with mocked repository + use case.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_history_timeline.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

const _response1 = HttpResponseEntity(
  statusCode: 200,
  body: 'ok1',
  headers: {},
  durationMs: 100,
);
const _response2 = HttpResponseEntity(
  statusCode: 201,
  body: 'ok2',
  headers: {},
  durationMs: 200,
);

final _entry1 = ResponseHistoryEntry(
  id: 'e1',
  response: _response1,
  capturedAt: DateTime(2024).millisecondsSinceEpoch,
);
final _entry2 = ResponseHistoryEntry(
  id: 'e2',
  response: _response2,
  capturedAt: DateTime(2024, 1, 2).millisecondsSinceEpoch,
);

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

Future<void> _pump(
  WidgetTester tester,
  TabsBloc bloc, {
  required String tabId,
  required List<ResponseHistoryEntry> history,
  String? viewedHistoryEntryId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: BlocProvider.value(
          value: bloc,
          child: ResponseHistoryTimeline(
            tabId: tabId,
            history: history,
            viewedHistoryEntryId: viewedHistoryEntryId,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps the timeline the way production hosts it: under a BlocBuilder that
/// re-reads the tab's history + viewedHistoryEntryId from every TabsBloc
/// emission — so a suppressed emission (the G2 bug) is visible as a badge
/// that never flips.
Future<void> _pumpLive(
  WidgetTester tester,
  TabsBloc bloc, {
  required String tabId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: BlocProvider.value(
          value: bloc,
          child: BlocBuilder<TabsBloc, TabsState>(
            builder: (context, state) {
              final tab = state.tabs.byId(tabId)!;
              return ResponseHistoryTimeline(
                tabId: tabId,
                history: tab.responseHistory,
                viewedHistoryEntryId: tab.viewedHistoryEntryId,
              );
            },
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
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
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

  testWidgets('hidden when fewer than 2 entries', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rh1',
      config: HttpRequestConfigEntity(id: 'rh1'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    // 0 entries.
    await _pump(tester, bloc, tabId: 'rh1', history: const []);
    expect(find.byKey(const ValueKey('response_history_button')), findsNothing);

    // 1 entry.
    await _pump(tester, bloc, tabId: 'rh1', history: [_entry1]);
    expect(find.byKey(const ValueKey('response_history_button')), findsNothing);
  });

  testWidgets('visible with 2 or more entries', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rh2',
      config: HttpRequestConfigEntity(id: 'rh2'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(
      tester,
      bloc,
      tabId: 'rh2',
      history: [_entry1, _entry2],
    );

    expect(
      find.byKey(const ValueKey('response_history_button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'tapping an entry dispatches ViewResponseHistoryEntry and swaps response',
    (
      tester,
    ) async {
      // Seed the tab with pre-loaded history entries so the bloc can satisfy
      // ViewResponseHistoryEntry (it reads history from tab state).
      final tab = HttpRequestTabEntity(
        tabId: 'rh3',
        config: const HttpRequestConfigEntity(id: 'rh3'),
        response: _response1,
        responseHistory: [_entry1, _entry2],
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(
        tester,
        bloc,
        tabId: 'rh3',
        history: [_entry1, _entry2],
      );

      // Open the popup.
      await tester.tap(find.byKey(const ValueKey('response_history_button')));
      await tester.pumpAndSettle();

      // '#2  ' (with trailing spaces from the _MenuRow widget) is the label
      // for the second (older) entry. Use textContaining to match robustly.
      await tester.tap(find.textContaining('#2'));
      await tester.pumpAndSettle();

      // ViewResponseHistoryEntry replaces tab.response with entry2's response.
      expect(bloc.state.tabs.byId('rh3')!.response, _response2);

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'a viewed-entry id matching no history entry does not falsely label '
    '"Latest" — regression guard (A6)',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'rh5',
        config: HttpRequestConfigEntity(id: 'rh5'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      // The id intentionally matches neither history entry — indexWhere
      // misses (-1).
      await _pump(
        tester,
        bloc,
        tabId: 'rh5',
        history: [_entry1, _entry2],
        viewedHistoryEntryId: 'stale-id-not-in-history',
      );

      // The button must show plain 'HISTORY', not 'HISTORY: #1' (the old
      // .clamp(0, ...) mapped a -1 miss to index 0 = "Latest").
      expect(find.text('HISTORY'), findsOneWidget);
      expect(find.textContaining('HISTORY:'), findsNothing);

      // No entry in the popup should read as selected.
      await tester.tap(find.byKey(const ValueKey('response_history_button')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    },
  );

  testWidgets('no overflow', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 'rh4',
      config: HttpRequestConfigEntity(id: 'rh4'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(
      tester,
      bloc,
      tabId: 'rh4',
      history: [_entry1, _entry2],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picking entry #2 whose response value-equals the latest still flips the '
    'badge and checkmark to #2 — id identity, not value equality (G2)',
    (tester) async {
      // Two history entries holding VALUE-EQUAL responses (identical
      // status/body/headers/duration — trivial against localhost), distinct
      // only by entry id.
      const same = HttpResponseEntity(
        statusCode: 200,
        body: 'same',
        headers: {},
        durationMs: 7,
      );
      final head = ResponseHistoryEntry(
        id: 'eq-head',
        response: same,
        capturedAt: DateTime(2024, 1, 2).millisecondsSinceEpoch,
      );
      final older = ResponseHistoryEntry(
        id: 'eq-older',
        response: same,
        capturedAt: DateTime(2024).millisecondsSinceEpoch,
      );
      final tab = HttpRequestTabEntity(
        tabId: 'rh6',
        config: const HttpRequestConfigEntity(id: 'rh6'),
        response: same,
        responseHistory: [head, older],
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pumpLive(tester, bloc, tabId: 'rh6');
      expect(find.text('HISTORY'), findsOneWidget);

      // Pick the older (#2) entry.
      await tester.tap(find.byKey(const ValueKey('response_history_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('#2'));
      await tester.pump(); // close route starts
      await tester.pump(); // first frame after the bloc emission

      // The emission must not be suppressed: the responses are value-equal,
      // so only viewedHistoryEntryId distinguishes the states.
      expect(bloc.state.tabs.byId('rh6')!.viewedHistoryEntryId, 'eq-older');
      expect(find.text('HISTORY: #2'), findsOneWidget);
      await tester.pumpAndSettle();

      // Reopen: the checkmark must sit on the #2 row, not on "Latest".
      await tester.tap(find.byKey(const ValueKey('response_history_button')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      final checkedRow = find.ancestor(
        of: find.byIcon(Icons.radio_button_checked),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: checkedRow.first, matching: find.text('#2  ')),
        findsOneWidget,
      );

      // Drain the bloc's 10s debounced-save timer before teardown.
      await tester.tap(find.text('HISTORY: #2'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
    },
  );
}
