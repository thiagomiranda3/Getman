// Widget tests for ResponseHistoryTimeline: hidden when < 2 entries,
// visible with 2+, and tapping an entry dispatches ViewResponseHistoryEntry.
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
  HttpResponseEntity? current,
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
            current: current,
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
      current: _response1,
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
        current: _response1,
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
      current: _response1,
    );

    expect(tester.takeException(), isNull);
  });
}
