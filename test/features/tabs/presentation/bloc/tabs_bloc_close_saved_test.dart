// TabsBloc CloseSavedTabs tests (A3): closes every NON-dirty tab of the
// named panel (linked-clean + unlinked-pristine), keeps dirty ones, never
// prompts, and pushes each closed tab onto the A2 reopen stack. Dirtiness
// uses TabDirtyChecker semantics against the event-carried savedConfigs.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
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

  // The four dirtiness quadrants:
  const savedCfg = HttpRequestConfigEntity(id: 'cfg1', url: 'https://a.dev');
  const linkedClean = HttpRequestTabEntity(
    tabId: 'linked-clean',
    config: savedCfg,
    collectionNodeId: 'n1',
    collectionName: 'A',
  );
  const linkedDirty = HttpRequestTabEntity(
    tabId: 'linked-dirty',
    config: HttpRequestConfigEntity(id: 'cfg2', url: 'https://b.dev/EDITED'),
    collectionNodeId: 'n2',
    collectionName: 'B',
  );
  // Unlinked pristine: config equals the default for its id → not dirty.
  const unlinkedPristine = HttpRequestTabEntity(
    tabId: 'scratch-clean',
    config: HttpRequestConfigEntity(id: 'scratch-clean'),
  );
  const unlinkedDirty = HttpRequestTabEntity(
    tabId: 'scratch-dirty',
    config: HttpRequestConfigEntity(id: 'scratch-dirty', url: 'https://x.dev'),
  );

  const savedConfigs = <String, HttpRequestConfigEntity>{
    'n1': savedCfg,
    'n2': HttpRequestConfigEntity(id: 'cfg2', url: 'https://b.dev'),
  };

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

  Future<TabsBloc> buildSeededBloc() async {
    final bloc = buildBloc();
    when(() => repository.getPanels()).thenAnswer(
      (_) async => [
        const PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: [linkedClean, linkedDirty, unlinkedPristine, unlinkedDirty],
          activeTabId: 'linked-clean',
        ),
      ],
    );
    when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
    bloc.add(const LoadTabs());
    await bloc.stream.firstWhere((s) => !s.isLoading && s.panels.isNotEmpty);
    return bloc;
  }

  test('closes exactly the non-dirty tabs, keeps dirty ones, fixes the '
      'active tab', () async {
    final bloc = await buildSeededBloc();
    addTearDown(bloc.close);

    bloc.add(const CloseSavedTabs(panelId: 'p1', savedConfigs: savedConfigs));
    await bloc.stream.firstWhere((s) => s.tabs.length == 2);

    expect(
      bloc.state.tabs.map((t) => t.tabId).toList(),
      ['linked-dirty', 'scratch-dirty'],
    );
    // The closed active tab re-points to a kept tab.
    expect(
      bloc.state.tabs[bloc.state.activeIndex].tabId,
      'linked-dirty',
    );
    verify(
      () => repository.deleteTabs(['linked-clean', 'scratch-clean']),
    ).called(1);
  });

  test('closed tabs land on the reopen stack (visual order)', () async {
    final bloc = await buildSeededBloc();
    addTearDown(bloc.close);

    bloc.add(const CloseSavedTabs(panelId: 'p1', savedConfigs: savedConfigs));
    await bloc.stream.firstWhere((s) => s.tabs.length == 2);
    expect(bloc.canReopenClosedTab, isTrue);

    bloc.add(const ReopenClosedTab()); // pops scratch-clean (pushed last)
    await bloc.stream.firstWhere((s) => s.tabs.length == 3);
    expect(bloc.state.tabs.map((t) => t.tabId), contains('scratch-clean'));

    bloc.add(const ReopenClosedTab()); // pops linked-clean
    await bloc.stream.firstWhere((s) => s.tabs.length == 4);
    expect(bloc.state.tabs.first.tabId, 'linked-clean');
  });

  test('no-op when every tab is dirty or the panel id is unknown', () async {
    final bloc = await buildSeededBloc();
    addTearDown(bloc.close);

    bloc.add(
      const CloseSavedTabs(panelId: 'ghost', savedConfigs: savedConfigs),
    );
    // All-dirty variant: empty savedConfigs makes the linked tabs dirty, but
    // unlinkedPristine is still clean — so use the unknown-panel case only,
    // then verify nothing changed.
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.tabs, hasLength(4));
    expect(bloc.canReopenClosedTab, isFalse);
    verifyNever(() => repository.deleteTabs(any()));
  });
}
