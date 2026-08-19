// Regression test for the offstage section-strip desync: a live-but-offstage
// RequestConfigSection (TabContentStack keeps up to kMaxLiveTabViews alive
// under TickerMode(enabled: false)) must show the newly selected section's
// content when it comes back on stage — including NON-adjacent section jumps
// (e.g. PARAMS -> HEADERS), which TabBarView warps with a child swap + a
// 300 ms page animation that a muted ticker stalls forever.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
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
import 'package:getman/features/tabs/presentation/widgets/headers_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/params_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

class _MockTabsRepository extends Mock implements TabsRepository {}

class _MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class _MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class _MockPutEnvironmentUseCase extends Mock
    implements PutEnvironmentUseCase {}

class _MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class _MockGetRequestRulesUseCase extends Mock
    implements GetRequestRulesUseCase {}

class _MockSaveRequestRulesUseCase extends Mock
    implements SaveRequestRulesUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

class _FakeRules extends Fake implements RequestRulesEntity {}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc() : super(CollectionsState());

  @override
  Future<void> flushPendingSaves() async {}
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(const HistoryState());
}

SettingsBloc _settingsBloc() {
  final save = _MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

EnvironmentsBloc _environmentsBloc() {
  final get = _MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => const <EnvironmentEntity>[]);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: _MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: _MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: _MockDeleteEnvironmentUseCase(),
  );
}

RulesBloc _rulesBloc() {
  final get = _MockGetRequestRulesUseCase();
  final save = _MockSaveRequestRulesUseCase();
  when(() => get.call(any())).thenAnswer(
    (inv) async =>
        RequestRulesEntity(configId: inv.positionalArguments.first as String),
  );
  when(() => save.call(any())).thenAnswer((_) async {});
  return RulesBloc(getRequestRulesUseCase: get, saveRequestRulesUseCase: save);
}

Future<TabsBloc> _loadedBloc(
  _MockTabsRepository repository,
  _MockSendRequestUseCase useCase,
) async {
  const t1 = HttpRequestTabEntity(
    tabId: 't1',
    config: HttpRequestConfigEntity(id: 't1'),
  );
  const t2 = HttpRequestTabEntity(
    tabId: 't2',
    config: HttpRequestConfigEntity(id: 't2'),
  );
  when(() => repository.getPanels()).thenAnswer(
    (_) async => [
      const PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [t1, t2],
        activeTabId: 't1',
      ),
    ],
  );
  when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase)
    ..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

void main() {
  late _MockTabsRepository repository;
  late _MockSendRequestUseCase sendUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(_FakeRules());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    repository = _MockTabsRepository();
    sendUseCase = _MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => repository.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
  });

  testWidgets(
    'offstage strip shows the right section after a NON-adjacent jump',
    (tester) async {
      final bloc = await _loadedBloc(repository, sendUseCase);
      addTearDown(bloc.close);
      final rulesBloc = _rulesBloc();
      addTearDown(rulesBloc.close);
      final sectionIndex = RequestSectionIndex();
      addTearDown(sectionIndex.dispose);
      final bodyA = CodeLineEditingController();
      addTearDown(bodyA.dispose);
      final varsA = CodeLineEditingController();
      addTearDown(varsA.dispose);
      final bodyB = CodeLineEditingController();
      addTearDown(bodyB.dispose);
      final varsB = CodeLineEditingController();
      addTearDown(varsB.dispose);

      // Mimics TabContentStack: both request tabs' views stay alive; only one
      // is on stage.
      Widget stack({required bool showFirst}) => MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: ChangeNotifierProvider<RequestSectionIndex>.value(
            value: sectionIndex,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: bloc),
                BlocProvider<SettingsBloc>(create: (_) => _settingsBloc()),
                BlocProvider<EnvironmentsBloc>(
                  create: (_) => _environmentsBloc(),
                ),
                BlocProvider<CollectionsBloc>(
                  create: (_) => _FakeCollectionsBloc(),
                ),
                BlocProvider<HistoryBloc>(create: (_) => _FakeHistoryBloc()),
                BlocProvider<RulesBloc>.value(value: rulesBloc),
              ],
              child: Stack(
                children: [
                  Offstage(
                    key: const ValueKey('host_a'),
                    offstage: !showFirst,
                    child: TickerMode(
                      enabled: showFirst,
                      child: RequestConfigSection(
                        tabId: 't1',
                        bodyController: bodyA,
                        variablesController: varsA,
                      ),
                    ),
                  ),
                  Offstage(
                    key: const ValueKey('host_b'),
                    offstage: showFirst,
                    child: TickerMode(
                      enabled: !showFirst,
                      child: RequestConfigSection(
                        tabId: 't2',
                        bodyController: bodyB,
                        variablesController: varsB,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(stack(showFirst: true));
      await tester.pumpAndSettle();

      // Tap HEADERS (index 2 — NON-adjacent to PARAMS at 0) in the visible
      // strip. The offstage strip must follow without getting stuck mid-warp.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('host_a')),
          matching: find.byKey(const ValueKey('reqtab_tab_HEADERS')),
        ),
      );
      await tester.pumpAndSettle();
      expect(sectionIndex.value, 2);

      // Switch request tabs. The very first frame the user sees must already
      // show HEADERS content — not another section's content stuck mid-warp.
      await tester.pumpWidget(stack(showFirst: false));
      await tester.pump();

      final headersInB = find.descendant(
        of: find.byKey(const ValueKey('host_b')),
        matching: find.byType(HeadersTabView),
      );
      final paramsInB = find.descendant(
        of: find.byKey(const ValueKey('host_b')),
        matching: find.byType(ParamsTabView),
      );

      // HEADERS content is on stage in host_b; PARAMS content is not visible.
      expect(headersInB.hitTestable(), findsOneWidget);
      expect(paramsInB.hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'offstage unified panel follows a non-adjacent section change',
    (tester) async {
      final bloc = await _loadedBloc(repository, sendUseCase);
      addTearDown(bloc.close);
      final rulesBloc = _rulesBloc();
      addTearDown(rulesBloc.close);
      final sectionIndex = RequestSectionIndex();
      addTearDown(sectionIndex.dispose);
      final body = CodeLineEditingController();
      addTearDown(body.dispose);
      final vars = CodeLineEditingController();
      addTearDown(vars.dispose);
      final response = CodeLineEditingController();
      addTearDown(response.dispose);

      Widget page({required bool onStage}) => MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: ChangeNotifierProvider<RequestSectionIndex>.value(
            value: sectionIndex,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: bloc),
                BlocProvider<SettingsBloc>(create: (_) => _settingsBloc()),
                BlocProvider<EnvironmentsBloc>(
                  create: (_) => _environmentsBloc(),
                ),
                BlocProvider<CollectionsBloc>(
                  create: (_) => _FakeCollectionsBloc(),
                ),
                BlocProvider<HistoryBloc>(create: (_) => _FakeHistoryBloc()),
                BlocProvider<RulesBloc>.value(value: rulesBloc),
              ],
              child: Offstage(
                offstage: !onStage,
                child: TickerMode(
                  enabled: onStage,
                  child: UnifiedRequestPanel(
                    tabId: 't1',
                    bodyController: body,
                    variablesController: vars,
                    responseController: response,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(page(onStage: true));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      // The user switches away; this panel goes offstage with muted tickers.
      await tester.pumpWidget(page(onStage: false));
      await tester.pump();

      // Another request tab's strip picks HEADERS (non-adjacent to PARAMS).
      sectionIndex.value = 2;
      await tester.pump();

      // Back on stage: the FIRST frame must already show HEADERS content.
      await tester.pumpWidget(page(onStage: true));
      await tester.pump();

      expect(find.byType(HeadersTabView).hitTestable(), findsOneWidget);
      expect(find.byType(ParamsTabView).hitTestable(), findsNothing);
    },
  );
}
