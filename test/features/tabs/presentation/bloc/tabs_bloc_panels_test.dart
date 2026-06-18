// Panel-aware load/migration tests for TabsBloc (Task 4) plus the shared
// helpers — `tab(...)`, `buildBloc()`, `buildLoadedBloc()` — that the panel
// *event* tests landing in Tasks 5 and 6 reuse. Keep the helpers stable: later
// tasks append `blocTest`s that call them, so changing their contract ripples.
import 'package:bloc_test/bloc_test.dart';
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

void main() {
  // Re-created by [buildBloc] for every bloc under test, so `verify(...)` in a
  // `blocTest` always targets the repository the bloc actually used.
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

  /// A minimal tab whose [tabId] and config id are both [id].
  HttpRequestTabEntity tab(String id) => HttpRequestTabEntity(
    tabId: id,
    config: HttpRequestConfigEntity(id: id, url: 'https://$id.dev'),
  );

  /// Construct a bloc backed by a fresh mocked repository (assigned to the
  /// shared [repository] field) with every write stubbed and the panel reads
  /// defaulted to "no panels persisted" — individual tests override the reads
  /// they care about before adding events.
  TabsBloc buildBloc() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.getPanels()).thenAnswer((_) async => <PanelEntity>[]);
    when(() => repository.getActivePanelId()).thenAnswer((_) async => null);
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => repository.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
    return TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    );
  }

  /// Build a bloc and drive [LoadTabs], waiting until it has settled into a
  /// single "Panel 1". Uses the first-run seed path (empty persisted panels),
  /// so callers (Tasks 5/6) start from exactly one loaded panel with one tab.
  Future<TabsBloc> buildLoadedBloc() async {
    final bloc = buildBloc()..add(const LoadTabs());
    await bloc.stream.firstWhere(
      (s) => !s.isLoading && s.panels.length == 1,
    );
    return bloc;
  }

  group('LoadTabs (panel-aware)', () {
    blocTest<TabsBloc, TabsState>(
      'seeds "Panel 1" with sample request on true first run',
      build: () {
        final bloc = buildBloc();
        when(() => repository.getPanels()).thenAnswer((_) async => []);
        when(() => repository.getActivePanelId()).thenAnswer((_) async => null);
        return bloc;
      },
      act: (b) => b.add(const LoadTabs()),
      verify: (b) {
        expect(b.state.panels.single.name, 'Panel 1');
        expect(b.state.tabs.single.config.url, 'https://httpbin.org/get');
        expect(b.state.activePanelId, b.state.panels.single.id);
      },
    );

    blocTest<TabsBloc, TabsState>(
      'persists migrated panels when meta was absent',
      build: () {
        final bloc = buildBloc();
        final migrated = PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: [tab('t1')],
          activeTabId: 't1',
        );
        when(() => repository.getPanels()).thenAnswer((_) async => [migrated]);
        when(() => repository.getActivePanelId()).thenAnswer((_) async => null);
        return bloc;
      },
      act: (b) => b.add(const LoadTabs()),
      // `blocTest` auto-closes the bloc after `act`, and `close()` also flushes
      // panels/meta — so these writes happen at least once (migration) plus once
      // more on teardown. We assert "at least once" rather than an exact count.
      verify: (_) {
        verify(
          () => repository.putPanel(any()),
        ).called(greaterThanOrEqualTo(1));
        verify(
          () => repository.savePanelMeta(any(), any()),
        ).called(greaterThanOrEqualTo(1));
      },
    );
  });

  // Smoke-test the shared helpers Tasks 5/6 depend on, so a regression in their
  // contract surfaces here rather than in a downstream task.
  test('buildLoadedBloc settles into one panel with one tab', () async {
    final bloc = await buildLoadedBloc();
    addTearDown(bloc.close);
    expect(bloc.state.panels.single.name, 'Panel 1');
    expect(bloc.state.tabs, hasLength(1));
    expect(bloc.state.activePanelId, bloc.state.panels.single.id);
  });

  // ---------------------------------------------------------------------------
  // Task 5: Panel lifecycle events
  // ---------------------------------------------------------------------------
  //
  // blocTest's `build:` parameter expects a synchronous `B Function()`.
  // buildLoadedBloc is async (it awaits stream events), so we use a late
  // variable populated in `setUp` and return it synchronously from `build`.
  // The helpers themselves are unchanged — only the wiring is adapted.

  group('AddPanel', () {
    late TabsBloc prebuilt;
    setUp(() async => prebuilt = await buildLoadedBloc());

    blocTest<TabsBloc, TabsState>(
      'creates an empty "Panel N" and activates it',
      build: () => prebuilt,
      act: (b) => b.add(const AddPanel()),
      verify: (b) {
        expect(b.state.panels.length, 2);
        expect(b.state.panels.last.name, 'Panel 2');
        expect(b.state.panels.last.tabs, isEmpty);
        expect(b.state.panels.last.activeTabId, '');
        expect(b.state.activePanelId, b.state.panels.last.id);
      },
    );
  });

  group('RemovePanel', () {
    late TabsBloc prebuilt;
    setUp(() async => prebuilt = await buildLoadedBloc());

    blocTest<TabsBloc, TabsState>(
      'is rejected when only one panel remains',
      build: () => prebuilt,
      act: (b) => b.add(RemovePanel(b.state.panels.single.id)),
      verify: (b) => expect(b.state.panels.length, 1),
    );

    blocTest<TabsBloc, TabsState>(
      'of the active panel switches to a neighbor',
      build: () => prebuilt,
      act: (b) {
        b.add(const AddPanel()); // now 2 panels, panel 2 active
        final p2 = b.state.panels.last.id;
        b.add(RemovePanel(p2));
      },
      verify: (b) {
        expect(b.state.panels.length, 1);
        expect(b.state.activePanelId, b.state.panels.single.id);
      },
    );
  });

  group('RenamePanel', () {
    late TabsBloc prebuilt;
    setUp(() async => prebuilt = await buildLoadedBloc());

    blocTest<TabsBloc, TabsState>(
      'with empty name resets to default "Panel N"',
      build: () => prebuilt,
      act: (b) => b.add(RenamePanel(b.state.panels.single.id, '   ')),
      verify: (b) => expect(b.state.panels.single.name, 'Panel 1'),
    );
  });

  group('SetActivePanel', () {
    late TabsBloc prebuilt;
    setUp(() async => prebuilt = await buildLoadedBloc());

    blocTest<TabsBloc, TabsState>(
      "restores that panel's remembered active tab",
      build: () => prebuilt,
      act: (b) {
        final p1 = b.state.panels.single.id;
        b
          ..add(const AddPanel()) // creates + activates Panel 2
          ..add(SetActivePanel(p1)); // back to Panel 1
      },
      verify: (b) => expect(b.state.activePanelId, b.state.panels.first.id),
    );
  });

  // Carry-forward from Task 4 review: cross-panel resolution
  // (_replaceTabAcrossPanels) must work when the owning panel is NOT active.
  test(
    'UpdateTab resolves across panels when owning panel is not active',
    () async {
      final bloc = await buildLoadedBloc();
      addTearDown(bloc.close);

      // Capture panel 1's id and its single tab.
      final panel1Id = bloc.state.panels.single.id;

      // Add panel 2 — it becomes active (and starts empty).
      bloc.add(const AddPanel());
      await bloc.stream.firstWhere((s) => s.panels.length == 2);

      // Give panel 2 a tab to mutate (it is the active panel right now).
      bloc.add(const AddTab());
      await bloc.stream.firstWhere((s) => s.panels.last.tabs.length == 1);
      final panel2Tab = bloc.state.panels.last.tabs.single;

      // Switch back to panel 1 — panel 2 is now non-active.
      bloc.add(SetActivePanel(panel1Id));
      await bloc.stream.firstWhere((s) => s.activePanelId == panel1Id);

      // Mutate panel 2's tab (which is in a non-active panel).
      final updatedTab = panel2Tab.copyWith(
        config: panel2Tab.config.copyWith(url: 'https://changed.dev'),
      );
      bloc.add(UpdateTab(updatedTab));
      // UpdateTab is synchronous — give it one microtask to emit.
      await Future<void>.delayed(Duration.zero);

      expect(
        bloc.state.panels[1].tabs.single.config.url,
        'https://changed.dev',
        reason: '_replaceTabAcrossPanels must update the tab in panel 2',
      );
      expect(
        bloc.state.activePanelId,
        panel1Id,
        reason: 'active panel must remain panel 1',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Task 6: Move-tab-between-panels events
  // ---------------------------------------------------------------------------

  group('MoveTabToPanel', () {
    test(
      'moves a tab to the target and stays on the current panel',
      () async {
        final bloc = await buildLoadedBloc();
        addTearDown(bloc.close);

        final p1 = bloc.state.panels.single.id;

        // Panel 1: add a second tab.
        bloc.add(const AddTab());
        await bloc.stream.firstWhere((s) => s.panels.first.tabs.length == 2);

        // Create Panel 2 — it becomes active (and starts empty).
        bloc.add(const AddPanel());
        await bloc.stream.firstWhere((s) => s.panels.length == 2);
        final p2 = bloc.state.panels[1].id;

        // Switch back to Panel 1.
        bloc.add(SetActivePanel(p1));
        await bloc.stream.firstWhere((s) => s.activePanelId == p1);

        // Move Panel 1's last tab into the empty Panel 2.
        final movingId = bloc.state.panels.byId(p1)!.tabs.last.tabId;
        bloc.add(MoveTabToPanel(movingId, p2));
        await bloc.stream.firstWhere(
          (s) => s.panels.byId(p2)!.tabs.length == 1,
        );

        expect(bloc.state.activePanelId, bloc.state.panels.first.id);
        expect(bloc.state.panels[1].tabs.single.tabId, movingId);
      },
    );

    test(
      'moving the last tab out of a panel leaves the source empty',
      () async {
        final bloc = await buildLoadedBloc();
        addTearDown(bloc.close);

        // Panel 1 starts with one tab; create Panel 2 (now empty + active).
        bloc.add(const AddPanel());
        await bloc.stream.firstWhere((s) => s.panels.length == 2);
        final p2 = bloc.state.panels.last.id;
        final p1 = bloc.state.panels.first.id;
        final onlyTab = bloc.state.panels.first.tabs.single.tabId;

        // Move Panel 1's only tab to Panel 2 — Panel 1 must go empty, not
        // re-seed a blank.
        bloc.add(MoveTabToPanel(onlyTab, p2));
        await bloc.stream.firstWhere(
          (s) => s.panels.byId(p1)!.tabs.isEmpty,
        );

        expect(bloc.state.panels.byId(p1)!.tabs, isEmpty);
        expect(bloc.state.panels.byId(p1)!.activeTabId, '');
      },
    );
  });

  group('MoveTabToNewPanel', () {
    test(
      'creates a panel containing only the moved tab',
      () async {
        final bloc = await buildLoadedBloc();
        addTearDown(bloc.close);

        final p1 = bloc.state.panels.single.id;

        // Panel 1: add a second tab.
        bloc.add(const AddTab());
        await bloc.stream.firstWhere((s) => s.panels.first.tabs.length == 2);
        final moving = bloc.state.panels.single.tabs.last.tabId;

        // Move that tab to a brand new panel.
        bloc.add(MoveTabToNewPanel(moving));
        await bloc.stream.firstWhere((s) => s.panels.length == 2);

        expect(bloc.state.panels.length, 2);
        expect(bloc.state.panels.last.tabs.length, 1);
        expect(bloc.state.panels.last.tabs.single.tabId, isNotEmpty);
        expect(bloc.state.activePanelId, p1); // stayed put
      },
    );
  });

  group('RemoveTab (last tab in a panel)', () {
    test('leaves the panel empty rather than re-seeding a blank', () async {
      final bloc = await buildLoadedBloc();
      addTearDown(bloc.close);

      // buildLoadedBloc settles into one panel with one tab.
      final onlyTab = bloc.state.panels.single.tabs.single.tabId;

      bloc.add(RemoveTab(onlyTab));
      await bloc.stream.firstWhere((s) => s.panels.single.tabs.isEmpty);

      expect(bloc.state.panels.single.tabs, isEmpty);
      expect(bloc.state.panels.single.activeTabId, '');
      // The derived active-panel view is empty too — the UI shows the
      // "NO OPEN TABS" placeholder.
      expect(bloc.state.tabs, isEmpty);
    });
  });

  group('empty-panels guard (pre-LoadTabs)', () {
    // All active-panel-scoped handlers must no-op — not throw — when
    // dispatched before LoadTabs fills state.panels (initial TabsState is
    // empty).
    test('SetActiveIndex does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(
        () => bloc.add(const SetActiveIndex(0)),
        returnsNormally,
      );
      // Give the handler a tick to complete.
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty); // state unchanged
    });

    test('AddTab does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(() => bloc.add(const AddTab()), returnsNormally);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty);
    });

    test('ReorderTabs does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(
        () => bloc.add(const ReorderTabs(0, 1)),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty);
    });

    test('CloseOtherTabs does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(
        () => bloc.add(const CloseOtherTabs('x')),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty);
    });

    test('CloseTabsToTheRight does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(
        () => bloc.add(const CloseTabsToTheRight('x')),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty);
    });

    test('CloseTabsToTheLeft does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(
        () => bloc.add(const CloseTabsToTheLeft('x')),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty);
    });

    test('DuplicateTab does not throw on empty panels', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);
      expect(
        () => bloc.add(const DuplicateTab('x')),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.panels, isEmpty);
    });
  });
}
