// TabsBloc RevertTab tests (A4): reverting a dirty LINKED tab restores the
// dispatcher-supplied saved config (the TabDirtyChecker baseline) while
// preserving the displayed response and the time-travel history; unlinked or
// missing tabs are no-ops.
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

  const savedConfig = HttpRequestConfigEntity(
    id: 'cfg1',
    url: 'https://api.dev/users',
  );
  const dirtyConfig = HttpRequestConfigEntity(
    id: 'cfg1',
    url: 'https://api.dev/users?debug=1',
  );
  const response = HttpResponseEntity(
    statusCode: 200,
    body: '{"ok":true}',
    headers: {},
    durationMs: 5,
  );
  const linkedDirty = HttpRequestTabEntity(
    tabId: 't1',
    config: dirtyConfig,
    collectionNodeId: 'n1',
    collectionName: 'Users',
    response: response,
    responseHistory: [
      ResponseHistoryEntry(id: 'h1', response: response, capturedAt: 1),
    ],
  );
  const unlinkedDirty = HttpRequestTabEntity(
    tabId: 't2',
    config: HttpRequestConfigEntity(id: 't2', url: 'https://scratch.dev'),
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
    when(() => repository.getPanels()).thenAnswer(
      (_) async => const [
        PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: [linkedDirty, unlinkedDirty],
          activeTabId: 't1',
        ),
      ],
    );
    when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
    return TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    );
  }

  Future<TabsBloc> loaded() async {
    final bloc = buildBloc()..add(const LoadTabs());
    await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
    return bloc;
  }

  test(
    'revert restores the saved config and PRESERVES response + timeline',
    () async {
      final bloc = await loaded();
      addTearDown(bloc.close);

      bloc.add(const RevertTab(tabId: 't1', savedConfig: savedConfig));
      await bloc.stream.first;

      final tab = bloc.state.tabs.byId('t1')!;
      expect(tab.config, savedConfig);
      expect(tab.response, response, reason: 'displayed response untouched');
      expect(
        tab.responseHistory,
        hasLength(1),
        reason: 'time-travel timeline untouched',
      );
      expect(tab.collectionNodeId, 'n1', reason: 'link untouched');
    },
  );

  test('revert on an UNLINKED tab is a no-op', () async {
    final bloc = await loaded();
    addTearDown(bloc.close);

    bloc.add(const RevertTab(tabId: 't2', savedConfig: savedConfig));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.tabs.byId('t2')!.config.url, 'https://scratch.dev');
  });

  test('revert on a missing tabId is a no-op (no crash)', () async {
    final bloc = await loaded();
    addTearDown(bloc.close);

    bloc.add(const RevertTab(tabId: 'ghost', savedConfig: savedConfig));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.tabs, hasLength(2));
  });
}
