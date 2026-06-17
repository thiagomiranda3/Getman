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
}
