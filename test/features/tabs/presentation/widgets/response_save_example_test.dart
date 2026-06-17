// Widget test for the "Save as example" capture affordance in the response
// BODY view: it appears only when the tab is linked to a collection node and a
// response exists, and dispatches SaveExampleToNode (with the response
// snapshot) on confirm.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_editor/re_editor.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

// Minimal empty HistoryBloc so the response pane's Compare button finds it in
// scope; no history -> the only compare target here is the saved example.
class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(const HistoryState());
}

HttpRequestTabEntity _tab({String? collectionNodeId}) => HttpRequestTabEntity(
  tabId: 'tab1',
  config: const HttpRequestConfigEntity(id: 'node1', url: 'https://api/users'),
  collectionNodeId: collectionNodeId,
  response: const HttpResponseEntity(
    statusCode: 200,
    body: '{"ok":true}',
    headers: {'content-type': 'application/json'},
    durationMs: 42,
  ),
);

void main() {
  late MockTabsRepository tabsRepo;
  late MockSendRequestUseCase sendUseCase;
  late MockCollectionsRepository collectionsRepo;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    tabsRepo = MockTabsRepository();
    sendUseCase = MockSendRequestUseCase();
    collectionsRepo = MockCollectionsRepository();
    when(() => tabsRepo.saveTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putTab(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deleteTabs(any())).thenAnswer((_) async {});
    when(() => tabsRepo.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => tabsRepo.putPanel(any())).thenAnswer((_) async {});
    when(() => tabsRepo.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => tabsRepo.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => const []);
    when(() => collectionsRepo.saveCollections(any())).thenAnswer((_) async {});
  });

  Future<({TabsBloc tabs, CollectionsBloc collections})> pump(
    WidgetTester tester,
    HttpRequestTabEntity tab,
  ) async {
    when(() => tabsRepo.getPanels()).thenAnswer(
      (_) async => [
        PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: [tab],
          activeTabId: tab.tabId,
        ),
      ],
    );
    when(() => tabsRepo.getActivePanelId()).thenAnswer((_) async => 'p1');
    final tabsBloc = TabsBloc(
      repository: tabsRepo,
      sendRequestUseCase: sendUseCase,
    )..add(const LoadTabs());
    await tabsBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);

    final collectionsBloc =
        CollectionsBloc(
          getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
          saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
          saveDebounce: const Duration(milliseconds: 5),
        )..add(
          const ReplaceCollections([
            CollectionNodeEntity(
              id: 'node1',
              name: 'GetUsers',
              isFolder: false,
              config: HttpRequestConfigEntity(id: 'node1'),
            ),
          ]),
        );
    await collectionsBloc.stream.first;

    final settingsSave = MockSaveSettingsUseCase();
    when(() => settingsSave(any())).thenAnswer((_) async {});

    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    addTearDown(tabsBloc.close);
    addTearDown(collectionsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: tabsBloc),
              BlocProvider.value(value: collectionsBloc),
              BlocProvider<HistoryBloc>(create: (_) => _FakeHistoryBloc()),
              BlocProvider<SettingsBloc>(
                create: (_) => SettingsBloc(
                  saveSettingsUseCase: settingsSave,
                  initialSettings: const SettingsEntity(),
                ),
              ),
            ],
            child: ResponseSection(
              tabId: 'tab1',
              responseController: controller,
              showMetadata: false,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    return (tabs: tabsBloc, collections: collectionsBloc);
  }

  testWidgets('hidden when the tab is not linked to a collection node', (
    tester,
  ) async {
    await pump(tester, _tab());
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
  });

  testWidgets('captures the request+response as an example on confirm', (
    tester,
  ) async {
    final blocs = await pump(tester, _tab(collectionNodeId: 'node1'));

    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();

    // The name prompt is shown pre-filled with a default; confirm it.
    expect(find.text('SAVE AS EXAMPLE'), findsOneWidget);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    final node = CollectionsTreeHelper.findNode(
      blocs.collections.state.collections,
      'node1',
    )!;
    expect(node.examples, hasLength(1));
    final example = node.examples.single;
    expect(example.config.statusCode, 200);
    expect(example.config.responseBody, '{"ok":true}');
    expect(example.config.responseHeaders, {
      'content-type': 'application/json',
    });
    expect(example.config.durationMs, 42);
  });
}
