// TabsBloc ReorderTabs panel-identity tests (D3): a reorder carrying
// ReorderTabs.panelId applies to the panel the drag indices were captured
// against — resolved by id — even when the user switched the active panel
// mid-drag (Cmd+Shift+], Cmd+Shift+T reopen). A vanished panel is a no-op;
// a null panelId keeps the legacy active-panel targeting.
// Split out of tabs_bloc_test.dart (function_lines_of_code metric gate).
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

/// Records errors reported to `Bloc.observer.onError` so a test can assert an
/// event handler did NOT throw.
class _RecordingBlocObserver extends BlocObserver {
  final List<Object> errors = <Object>[];

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(bloc, error, stackTrace);
  }
}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;
  late TabsBloc bloc;

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
    bloc = TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    );
  });

  tearDown(() => bloc.close());

  HttpRequestTabEntity tab(String id) => HttpRequestTabEntity(
    tabId: id,
    config: HttpRequestConfigEntity(id: id, url: 'https://$id.dev'),
  );

  Matcher hasPanelTabIds(List<String> ids) => isA<PanelEntity>().having(
    (p) => p.tabs.map((t) => t.tabId).toList(),
    'tab ids',
    ids,
  );

  /// Seeds two panels — p1 [a, b, c] and p2 [x, y] — with [activeId] active.
  Future<void> loadTwoPanels({required String activeId}) async {
    final p1 = PanelEntity(
      id: 'p1',
      name: 'Panel 1',
      tabs: [tab('a'), tab('b'), tab('c')],
      activeTabId: 'a',
    );
    final p2 = PanelEntity(
      id: 'p2',
      name: 'Panel 2',
      tabs: [tab('x'), tab('y')],
      activeTabId: 'x',
    );
    when(() => repository.getPanels()).thenAnswer((_) async => [p1, p2]);
    when(() => repository.getActivePanelId()).thenAnswer((_) async => activeId);
    bloc.add(const LoadTabs());
    await expectLater(
      bloc.stream,
      emitsThrough(predicate<TabsState>((s) => !s.isLoading)),
    );
  }

  List<String> panelOrder(String panelId) => bloc.state.panels
      .firstWhere((p) => p.id == panelId)
      .tabs
      .map((t) => t.tabId)
      .toList();

  test(
    'a reorder carrying panelId applies to THAT panel even when another '
    'panel became active mid-drag — never the active one',
    () async {
      await loadTwoPanels(activeId: 'p1');
      // The panel switch that races the drop (Cmd+Shift+] / Cmd+Shift+T
      // reopen activating another panel).
      bloc.add(const SetActivePanel('p2'));
      await pumpEventQueue();
      expect(bloc.state.activePanelId, 'p2');

      bloc.add(const ReorderTabs(0, 2, panelId: 'p1'));
      await pumpEventQueue();

      // The captured panel got the reorder its indices described…
      expect(panelOrder('p1'), ['b', 'c', 'a']);
      // …the active panel was never touched, and the right panel persisted.
      expect(panelOrder('p2'), ['x', 'y']);
      expect(bloc.state.activePanelId, 'p2');
      verify(
        () => repository.putPanel(any(that: hasPanelTabIds(['b', 'c', 'a']))),
      ).called(1);
    },
  );

  test('a reorder whose panel has vanished is a no-op', () async {
    final observer = _RecordingBlocObserver();
    final previous = Bloc.observer;
    Bloc.observer = observer;
    addTearDown(() => Bloc.observer = previous);

    await loadTwoPanels(activeId: 'p1');
    observer.errors.clear();

    bloc.add(const ReorderTabs(0, 1, panelId: 'ghost'));
    await pumpEventQueue();

    expect(observer.errors, isEmpty);
    expect(panelOrder('p1'), ['a', 'b', 'c']);
    expect(panelOrder('p2'), ['x', 'y']);
    verifyNever(() => repository.putPanel(any()));
  });

  test(
    'a null panelId keeps the legacy behavior: the active panel at '
    'processing time',
    () async {
      await loadTwoPanels(activeId: 'p2');

      bloc.add(const ReorderTabs(0, 1));
      await pumpEventQueue();

      expect(panelOrder('p2'), ['y', 'x']);
      expect(panelOrder('p1'), ['a', 'b', 'c']);
    },
  );

  test(
    'stale indices against the panelId-resolved panel still bail '
    '(bounds guard runs on the target panel)',
    () async {
      final observer = _RecordingBlocObserver();
      final previous = Bloc.observer;
      Bloc.observer = observer;
      addTearDown(() => Bloc.observer = previous);

      await loadTwoPanels(activeId: 'p1');
      observer.errors.clear();

      // Valid for p1 (3 tabs) but out of range for p2 (2 tabs): the guard
      // must evaluate against the event's panel, not the active one.
      bloc.add(const ReorderTabs(0, 2, panelId: 'p2'));
      await pumpEventQueue();

      expect(observer.errors, isEmpty);
      expect(panelOrder('p1'), ['a', 'b', 'c']);
      expect(panelOrder('p2'), ['x', 'y']);
    },
  );
}
