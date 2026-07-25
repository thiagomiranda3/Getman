// TabsBloc reopen-closed-tab tests (A2): every close path pushes onto the
// in-memory LIFO stack (max 10); ReopenClosedTab restores content (incl.
// response + time-travel history) into the original panel at the clamped
// original position — falling back to the active panel when the original
// panel is gone — and activates it. Harness mirrors tabs_bloc_panels_test.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
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

  HttpRequestTabEntity tab(String id) => HttpRequestTabEntity(
    tabId: id,
    config: HttpRequestConfigEntity(id: id, url: 'https://$id.dev'),
  );

  const response = HttpResponseEntity(
    statusCode: 200,
    body: '{"ok":true}',
    headers: {'content-type': 'application/json'},
    durationMs: 12,
  );

  /// A tab carrying a response + one time-travel entry — reopen must restore
  /// BOTH (the whole entity round-trips, dirty edits included).
  HttpRequestTabEntity tabWithResponse(String id) => HttpRequestTabEntity(
    tabId: id,
    config: HttpRequestConfigEntity(id: id, url: 'https://$id.dev/edited'),
    response: response,
    responseHistory: const [
      ResponseHistoryEntry(id: 'h1', response: response, capturedAt: 1),
    ],
  );

  PanelEntity panel(String id, List<HttpRequestTabEntity> tabs) => PanelEntity(
    id: id,
    name: id,
    tabs: tabs,
    activeTabId: tabs.isEmpty ? '' : tabs.first.tabId,
  );

  TabsBloc buildBloc() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
    return TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    );
  }

  /// Bloc loaded with [panels] (first panel active unless [active] given).
  Future<TabsBloc> buildSeededBloc(
    List<PanelEntity> panels, {
    String? active,
  }) async {
    final bloc = buildBloc();
    when(() => repository.getPanels()).thenAnswer((_) async => panels);
    when(
      () => repository.getActivePanelId(),
    ).thenAnswer((_) async => active ?? panels.first.id);
    bloc.add(const LoadTabs());
    await bloc.stream.firstWhere((s) => !s.isLoading && s.panels.isNotEmpty);
    return bloc;
  }

  group('ReopenClosedTab', () {
    test(
      'canReopenClosedTab is false before any close; reopen is a no-op',
      () async {
        final bloc = await buildSeededBloc([
          panel('p1', [tab('t1')]),
        ]);
        addTearDown(bloc.close);

        expect(bloc.canReopenClosedTab, isFalse);
        bloc.add(const ReopenClosedTab());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.tabs, hasLength(1));
      },
    );

    test('close then reopen round-trips content, response, history, panel, '
        'and position — and activates the tab', () async {
      final closed = tabWithResponse('t2');
      final bloc = await buildSeededBloc([
        panel('p1', [tab('t1'), closed, tab('t3')]),
      ]);
      addTearDown(bloc.close);

      bloc.add(const RemoveTab('t2'));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);
      expect(bloc.canReopenClosedTab, isTrue);

      bloc.add(const ReopenClosedTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      final restored = bloc.state.tabs[1];
      expect(restored, closed); // Equatable deep-equal: dirty config +
      // response + time-travel history all preserved
      expect(bloc.state.activeIndex, 1);
      expect(bloc.canReopenClosedTab, isFalse);
    });

    test('falls back to the active panel (clamped index) when the original '
        'panel is gone', () async {
      final bloc = await buildSeededBloc([
        panel('p1', [tab('t1')]),
        panel('p2', [tab('t2'), tab('t3')]),
      ]);
      addTearDown(bloc.close);

      bloc.add(const RemoveTab('t3')); // pushed with panelId p2, index 1
      await bloc.stream.firstWhere(
        (s) => s.panels.byId('p2')!.tabs.length == 1,
      );
      bloc.add(const RemovePanel('p2')); // p2 dies (t2 pushed too)
      await bloc.stream.firstWhere((s) => s.panels.length == 1);

      // Pop t2 (top of stack, from the panel close)…
      bloc.add(const ReopenClosedTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);
      // …then t3: original panel p2 is gone → active panel p1, index clamped.
      bloc.add(const ReopenClosedTab());
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(bloc.state.activePanelId, 'p1');
      expect(bloc.state.tabs.map((t) => t.tabId), contains('t3'));
    });

    test('CLOSE OTHERS pushes in visual order; two reopens rebuild the '
        'original strip order', () async {
      final bloc = await buildSeededBloc([
        panel('p1', [tab('t1'), tab('t2'), tab('t3')]),
      ]);
      addTearDown(bloc.close);

      bloc.add(const CloseOtherTabs('t2'));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(const ReopenClosedTab()); // pops t3 (rightmost pushed last)
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);
      bloc.add(const ReopenClosedTab()); // pops t1
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(
        bloc.state.tabs.map((t) => t.tabId).toList(),
        ['t1', 't2', 't3'],
        reason: 'stored strip indices restore the original order',
      );
    });

    test('stack keeps at most 10 — the oldest close is evicted', () async {
      final tabs = [for (var i = 1; i <= 11; i++) tab('t$i')];
      final bloc = await buildSeededBloc([panel('p1', tabs)]);
      addTearDown(bloc.close);

      for (var i = 1; i <= 11; i++) {
        bloc.add(RemoveTab('t$i'));
      }
      await bloc.stream.firstWhere((s) => s.tabs.isEmpty);

      for (var i = 0; i < 11; i++) {
        bloc.add(const ReopenClosedTab());
      }
      await bloc.stream.firstWhere((s) => s.tabs.length == 10);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs, hasLength(10));
      expect(
        bloc.state.tabs.map((t) => t.tabId),
        isNot(contains('t1')),
        reason: 't1 was the oldest close — evicted at depth 10',
      );
      expect(bloc.canReopenClosedTab, isFalse);
    });

    test(
      'CLEAN reopen: reopening a linked tab whose node is already open '
      'elsewhere with the SAME config activates the existing tab instead '
      'of duplicating (FIX I5 — dedup still fires when nothing diverged)',
      () async {
        const linked = HttpRequestTabEntity(
          tabId: 'tL',
          config: HttpRequestConfigEntity(id: 'cfgL'),
          collectionNodeId: 'node1',
          collectionName: 'GetUsers',
        );
        final bloc = await buildSeededBloc([
          panel('p1', [tab('t1'), linked]),
        ]);
        addTearDown(bloc.close);

        bloc.add(const RemoveTab('tL'));
        await bloc.stream.firstWhere((s) => s.tabs.length == 1);

        // The user re-opens the SAME saved request from the tree meanwhile
        // — production always passes the node's own config (stable id), so
        // this carries the identical config the closed tab had.
        bloc.add(
          const AddTab(
            config: HttpRequestConfigEntity(id: 'cfgL'),
            collectionNodeId: 'node1',
            collectionName: 'GetUsers',
          ),
        );
        await bloc.stream.firstWhere((s) => s.tabs.length == 2);

        bloc.add(const ReopenClosedTab());
        await Future<void>.delayed(Duration.zero);

        expect(
          bloc.state.tabs.where((t) => t.collectionNodeId == 'node1'),
          hasLength(1),
          reason: 'mirrors AddTab dedup — no duplicate linked tab',
        );
      },
    );

    test(
      'DIRTY reopen: a DISCARDed dirty snapshot restores as its own tab '
      'instead of being silently swallowed by the clean tab reopened '
      'meanwhile (FIX I5)',
      () async {
        // Closed with edited (dirty) content — this is what DISCARD pushes.
        const dirty = HttpRequestTabEntity(
          tabId: 'tL',
          config: HttpRequestConfigEntity(id: 'cfgL', url: 'https://edited'),
          collectionNodeId: 'node1',
          collectionName: 'GetUsers',
        );
        final bloc = await buildSeededBloc([
          panel('p1', [tab('t1'), dirty]),
        ]);
        addTearDown(bloc.close);

        bloc.add(const RemoveTab('tL'));
        await bloc.stream.firstWhere((s) => s.tabs.length == 1);

        // The user re-opens the same node from the tree — clean, unedited
        // config (same id, but the ORIGINAL url, not the discarded edit).
        bloc.add(
          const AddTab(
            config: HttpRequestConfigEntity(id: 'cfgL'),
            collectionNodeId: 'node1',
            collectionName: 'GetUsers',
          ),
        );
        await bloc.stream.firstWhere((s) => s.tabs.length == 2);

        bloc.add(const ReopenClosedTab());
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);

        final forNode = bloc.state.tabs.where(
          (t) => t.collectionNodeId == 'node1',
        );
        expect(
          forNode,
          hasLength(2),
          reason:
              'the dirty snapshot must restore as ITS OWN tab, not '
              'silently dedup into the clean one — that would destroy the '
              'discarded edit with no way to recover it',
        );
        expect(
          forNode.map((t) => t.config.url),
          containsAll(<String>['https://edited', '']),
          reason: 'both the dirty content and the clean tab must survive',
        );
      },
    );
  });

  // The stack is intentionally NOT persisted (in-memory only, lost on quit —
  // session restore already covers restarts). No repository interaction may
  // store it.
  blocTest<TabsBloc, TabsState>(
    'closing a tab persists the deletion but never a closed-tab record',
    // Stubs live in `build:` (not `setUp:`): bloc_test runs setUp() before
    // build(), and buildBloc() reassigns `repository` to a fresh mock — a
    // setUp stub would land on the previous test's now-orphaned instance.
    build: () {
      final bloc = buildBloc();
      when(() => repository.getPanels()).thenAnswer(
        (_) async => [
          const PanelEntity(
            id: 'p1',
            name: 'p1',
            tabs: [
              HttpRequestTabEntity(
                tabId: 't1',
                config: HttpRequestConfigEntity(id: 't1'),
              ),
            ],
            activeTabId: 't1',
          ),
        ],
      );
      when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
      return bloc;
    },
    act: (b) async {
      b.add(const LoadTabs());
      await b.stream.firstWhere((s) => !s.isLoading);
      b.add(const RemoveTab('t1'));
    },
    verify: (_) {
      verify(() => repository.deleteTabs(['t1'])).called(1);
    },
  );
}
