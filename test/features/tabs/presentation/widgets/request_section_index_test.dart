// Widget tests for the session-global PARAMS/AUTH/HEADERS/BODY/RULES
// selection (RequestSectionIndex): the section strip selection is shared
// across request tabs instead of being remembered per tab.

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
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
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
  when(
    () => get.call(any()),
  ).thenAnswer(
    (inv) async => RequestRulesEntity(
      configId: inv.positionalArguments.first as String,
    ),
  );
  when(() => save.call(any())).thenAnswer((_) async {});
  return RulesBloc(getRequestRulesUseCase: get, saveRequestRulesUseCase: save);
}

/// TabsBloc loaded with two request tabs (t1 active).
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

  /// Wraps [child] with the full provider set the section views need, plus
  /// the shared [RequestSectionIndex] under test.
  Widget host({
    required TabsBloc bloc,
    required RulesBloc rulesBloc,
    required RequestSectionIndex sectionIndex,
    required Widget child,
  }) {
    return MaterialApp(
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
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets('tapping a section writes the shared index', (tester) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final rulesBloc = _rulesBloc();
    addTearDown(rulesBloc.close);
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    final bodyController = CodeLineEditingController();
    addTearDown(bodyController.dispose);
    final variablesController = CodeLineEditingController();
    addTearDown(variablesController.dispose);

    await tester.pumpWidget(
      host(
        bloc: bloc,
        rulesBloc: rulesBloc,
        sectionIndex: sectionIndex,
        child: RequestConfigSection(
          tabId: 't1',
          bodyController: bodyController,
          variablesController: variablesController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(sectionIndex.value, 0);
    await tester.tap(find.byKey(const ValueKey('reqtab_tab_BODY')));
    await tester.pumpAndSettle();

    expect(sectionIndex.value, 3);
  });

  testWidgets('a newly mounted section strip seeds from the shared index', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final rulesBloc = _rulesBloc();
    addTearDown(rulesBloc.close);
    // As if HEADERS was picked in some other request tab earlier.
    final sectionIndex = RequestSectionIndex()..value = 2;
    addTearDown(sectionIndex.dispose);
    final bodyController = CodeLineEditingController();
    addTearDown(bodyController.dispose);
    final variablesController = CodeLineEditingController();
    addTearDown(variablesController.dispose);

    await tester.pumpWidget(
      host(
        bloc: bloc,
        rulesBloc: rulesBloc,
        sectionIndex: sectionIndex,
        child: RequestConfigSection(
          tabId: 't2',
          bodyController: bodyController,
          variablesController: variablesController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HeadersTabView), findsOneWidget);
    expect(find.byType(ParamsTabView), findsNothing);
  });

  testWidgets('live offstage section strips follow the shared selection', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final rulesBloc = _rulesBloc();
    addTearDown(rulesBloc.close);
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    // Separate controllers per section: two JsonCodeEditors must not share
    // one controller (the editor is keyed by GlobalObjectKey(controller)).
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
    Widget stack({required bool showFirst}) => host(
      bloc: bloc,
      rulesBloc: rulesBloc,
      sectionIndex: sectionIndex,
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
    );

    await tester.pumpWidget(stack(showFirst: true));
    await tester.pumpAndSettle();

    // Tap AUTH in the visible strip (scoped: the offstage strip has the same
    // tab keys).
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('host_a')),
        matching: find.byKey(const ValueKey('reqtab_tab_AUTH')),
      ),
    );
    await tester.pumpAndSettle();
    expect(sectionIndex.value, 1);

    // Switch request tabs: the other strip is already on AUTH.
    await tester.pumpWidget(stack(showFirst: false));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('host_b')),
        matching: find.byType(AuthTabView),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('host_b')),
        matching: find.byType(ParamsTabView),
      ),
      findsNothing,
    );
  });

  testWidgets('phone RESPONSE tab stays local; sections still sync', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final rulesBloc = _rulesBloc();
    addTearDown(rulesBloc.close);
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    final bodyController = CodeLineEditingController();
    addTearDown(bodyController.dispose);
    final variablesController = CodeLineEditingController();
    addTearDown(variablesController.dispose);
    final responseController = CodeLineEditingController();
    addTearDown(responseController.dispose);

    await tester.pumpWidget(
      host(
        bloc: bloc,
        rulesBloc: rulesBloc,
        sectionIndex: sectionIndex,
        child: UnifiedRequestPanel(
          tabId: 't1',
          bodyController: bodyController,
          variablesController: variablesController,
          responseController: responseController,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    // Picking a section syncs it globally.
    await tester.tap(find.text('HEADERS'));
    await tester.pumpAndSettle();
    expect(sectionIndex.value, 2);

    // RESPONSE is layout-specific: selecting it must not clobber the shared
    // section index.
    await tester.tap(find.text('RESPONSE'));
    await tester.pumpAndSettle();
    expect(sectionIndex.value, 2);

    // An external change (another request tab picked PARAMS) moves this
    // strip too.
    sectionIndex.value = 0;
    await tester.pumpAndSettle();
    expect(find.byType(ParamsTabView), findsOneWidget);
  });
}
