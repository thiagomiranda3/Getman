// Widget tests for the session-global PARAMS/AUTH/HEADERS/BODY/RULES
// selection (RequestSectionIndex): the section strip selection is shared
// across request tabs instead of being remembered per tab.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/scripting/presentation/widgets/scripts_tab_view.dart';
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
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/params_tab_view.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

class _Trust implements ScriptTrustRepository {
  final approved = <RequestScripts>[];
  @override
  Future<bool> isTrusted(String configId, RequestScripts scripts) async =>
      approved.contains(scripts);
  @override
  Future<void> trust(String configId, RequestScripts scripts) async {
    approved.add(scripts);
  }
}

class _DelayedTrust extends _Trust {
  final writesGate = Completer<void>();
  @override
  Future<void> trust(String configId, RequestScripts scripts) async {
    await writesGate.future;
    await super.trust(configId, scripts);
  }
}

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

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

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
            ],
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets('scripts replaces rules at section four on the first frame', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final sectionIndex = RequestSectionIndex()..value = 4;
    addTearDown(sectionIndex.dispose);
    final body = CodeLineEditingController();
    final variables = CodeLineEditingController();
    addTearDown(body.dispose);
    addTearDown(variables.dispose);
    await tester.pumpWidget(
      host(
        bloc: bloc,
        sectionIndex: sectionIndex,
        child: RequestConfigSection(
          tabId: 't1',
          bodyController: body,
          variablesController: variables,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('SCRIPTS').hitTestable(), findsOneWidget);
    expect(find.text('PRE-REQUEST').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('script_editor_pre')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('RULES'), findsNothing);
  });

  testWidgets(
    'offstage script sources sync; selection is inert',
    (tester) async {
      final bloc = await _loadedBloc(repository, sendUseCase);
      addTearDown(bloc.close);
      final trust = _Trust();
      final sectionIndex = RequestSectionIndex();
      addTearDown(sectionIndex.dispose);
      await tester.pumpWidget(
        host(
          bloc: bloc,
          sectionIndex: sectionIndex,
          child: RepositoryProvider<ScriptTrustRepository>.value(
            value: trust,
            child: const Offstage(child: ScriptsTabView(tabId: 't1')),
          ),
        ),
      );
      final original = bloc.state.tabs.byId('t1')!;
      bloc.add(
        UpdateTab(
          original.copyWith(
            config: original.config.copyWith(
              scripts: const RequestScripts(
                preRequest: 'console.log("external");',
                postResponse: 'gm.test("ok", () => {});',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final editors = tester
          .widgetList<JsonCodeEditor>(
            find.byType(JsonCodeEditor, skipOffstage: false),
          )
          .toList();
      expect(editors.first.controller.text, 'console.log("external");');
      final before = bloc.state;
      editors.first.controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );
      await tester.pump();
      expect(bloc.state, before);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      await tester.runAsync(bloc.close);
    },
  );

  testWidgets('trust approval reviews both exact sources before approving', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final trust = _Trust();
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    const scripts = RequestScripts(
      preRequest: 'console.log("pre");',
      postResponse: 'console.log("post");',
    );
    final tab = bloc.state.tabs.byId('t1')!;
    bloc.add(
      UpdateTab(tab.copyWith(config: tab.config.copyWith(scripts: scripts))),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(
        bloc: bloc,
        sectionIndex: sectionIndex,
        child: RepositoryProvider<ScriptTrustRepository>.value(
          value: trust,
          child: const ScriptsTabView(tabId: 't1'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('TRUST SCRIPTS'));
    await tester.pump();
    expect(trust.approved, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('console.log("pre");'), findsOneWidget);
    expect(find.text('console.log("post");'), findsOneWidget);
    await tester.tap(find.text('TRUST EXACT CONTENT'));
    await tester.pump();
    expect(trust.approved, [scripts]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
  });

  testWidgets('JWT snippet inserts into pre-request without sending', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final trust = _Trust();
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    await tester.pumpWidget(
      host(
        bloc: bloc,
        sectionIndex: sectionIndex,
        child: RepositoryProvider<ScriptTrustRepository>.value(
          value: trust,
          child: const ScriptsTabView(tabId: 't1'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('JWT session payload'), findsOneWidget);
    await tester.tap(find.text('INSERT'));
    await tester.pump();
    final scripts = bloc.state.tabs.byId('t1')!.config.scripts;
    expect(scripts.preRequest, contains('gm.jwt'));
    expect(scripts.postResponse, isEmpty);
    expect(bloc.state.tabs.byId('t1')!.isSending, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
  });

  testWidgets('enabling an imported script does not approve its source', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final trust = _Trust();
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    final tab = bloc.state.tabs.byId('t1')!;
    bloc.add(
      UpdateTab(
        tab.copyWith(
          config: tab.config.copyWith(
            scripts: const RequestScripts(
              preRequest: 'console.log("imported");',
              preRequestEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(
        bloc: bloc,
        sectionIndex: sectionIndex,
        child: RepositoryProvider<ScriptTrustRepository>.value(
          value: trust,
          child: const ScriptsTabView(tabId: 't1'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(
      bloc.state.tabs.byId('t1')!.config.scripts.preRequestEnabled,
      isTrue,
    );
    expect(trust.approved, isEmpty);
    expect(find.text('TRUST SCRIPTS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
  });

  testWidgets(
    'diagnostic location opens post-response source and caret immediately',
    (tester) async {
      final bloc = await _loadedBloc(repository, sendUseCase);
      addTearDown(bloc.close);
      final trust = _Trust();
      final sectionIndex = RequestSectionIndex()
        ..openScript(tabId: 't1', postResponse: true, line: 2, column: 3);
      addTearDown(sectionIndex.dispose);
      final tab = bloc.state.tabs.byId('t1')!;
      bloc.add(
        UpdateTab(
          tab.copyWith(
            config: tab.config.copyWith(
              scripts: const RequestScripts(
                postResponse: 'console.log("first");\nconsole.log("second");',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(
          bloc: bloc,
          sectionIndex: sectionIndex,
          child: RepositoryProvider<ScriptTrustRepository>.value(
            value: trust,
            child: const ScriptsTabView(tabId: 't1'),
          ),
        ),
      );
      await tester.pump();
      final editor = tester.widget<JsonCodeEditor>(
        find.byKey(const ValueKey('script_editor_post')).hitTestable(),
      );
      expect(editor.controller.text, contains('second'));
      expect(editor.controller.selection.extentIndex, 1);
      expect(editor.controller.selection.extentOffset, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(bloc.close);
    },
  );

  testWidgets(
    'editing pre script cannot approve untouched imported post source',
    (tester) async {
      final bloc = await _loadedBloc(repository, sendUseCase);
      addTearDown(bloc.close);
      final trust = _Trust();
      final sectionIndex = RequestSectionIndex();
      addTearDown(sectionIndex.dispose);
      final tab = bloc.state.tabs.byId('t1')!;
      bloc.add(
        UpdateTab(
          tab.copyWith(
            config: tab.config.copyWith(
              scripts: const RequestScripts(
                postResponse: 'console.log("unreviewed imported post");',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(
          bloc: bloc,
          sectionIndex: sectionIndex,
          child: RepositoryProvider<ScriptTrustRepository>.value(
            value: trust,
            child: const ScriptsTabView(tabId: 't1'),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('INSERT'));
      await tester.pump();
      await tester.pump();
      final edited = bloc.state.tabs.byId('t1')!.config.scripts;
      expect(edited.preRequest, contains('gm.jwt'));
      expect(edited.postResponse, contains('unreviewed imported post'));
      expect(trust.approved, isEmpty);
      expect(await trust.isTrusted('t1', edited), isFalse);
      await tester.tap(find.text('TRUST SCRIPTS'));
      await tester.pump();
      await tester.tap(find.text('TRUST EXACT CONTENT'));
      await tester.pump();
      expect(trust.approved, [edited]);
      final editor = tester.widget<JsonCodeEditor>(
        find.byKey(const ValueKey('script_editor_pre')),
      );
      editor.controller.text =
          '${edited.preRequest}\nconsole.log("reviewed edit");';
      await tester.pump();
      await tester.pump();
      final nextEdit = bloc.state.tabs.byId('t1')!.config.scripts;
      expect(await trust.isTrusted('t1', nextEdit), isTrue);
      expect(find.text('TRUST SCRIPTS'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(bloc.close);
    },
  );

  testWidgets('rapid local edits inherit pending empty-bundle approval', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final trust = _DelayedTrust();
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    await tester.pumpWidget(
      host(
        bloc: bloc,
        sectionIndex: sectionIndex,
        child: RepositoryProvider<ScriptTrustRepository>.value(
          value: trust,
          child: const ScriptsTabView(tabId: 't1'),
        ),
      ),
    );
    final editor = tester.widget<JsonCodeEditor>(
      find.byKey(const ValueKey('script_editor_pre')),
    );
    editor.controller.text = 'console.log("first");';
    editor.controller.text = 'console.log("second");';
    await tester.pump();
    await tester.pump();
    expect(editor.controller.text, 'console.log("second");');
    expect(trust.approved, isEmpty);
    trust.writesGate.complete();
    await tester.pump();
    await tester.pump();
    final scripts = bloc.state.tabs.byId('t1')!.config.scripts;
    expect(scripts.preRequest, 'console.log("second");');
    expect(await trust.isTrusted('t1', scripts), isTrue);
    editor.controller.text = 'console.log("third");';
    await tester.pump();
    await tester.pump();
    expect(
      await trust.isTrusted('t1', bloc.state.tabs.byId('t1')!.config.scripts),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
  });

  testWidgets('pending local approval cannot approve a later imported source', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final trust = _DelayedTrust();
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    await tester.pumpWidget(
      host(
        bloc: bloc,
        sectionIndex: sectionIndex,
        child: RepositoryProvider<ScriptTrustRepository>.value(
          value: trust,
          child: const ScriptsTabView(tabId: 't1'),
        ),
      ),
    );
    final editor = tester.widget<JsonCodeEditor>(
      find.byKey(const ValueKey('script_editor_pre')),
    );
    editor.controller.text = 'console.log("first");';
    editor.controller.text = 'console.log("second");';
    await tester.pump();
    await tester.pump();
    final tab = bloc.state.tabs.byId('t1')!;
    bloc.add(
      UpdateTab(
        tab.copyWith(
          config: tab.config.copyWith(
            scripts: tab.config.scripts.copyWith(
              postResponse: 'console.log("unseen import");',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    editor.controller.text = 'console.log("third");';
    await tester.pump();
    await tester.pump();
    trust.writesGate.complete();
    await tester.pump();
    await tester.pump();
    final scripts = bloc.state.tabs.byId('t1')!.config.scripts;
    expect(scripts.preRequest, 'console.log("third");');
    expect(scripts.postResponse, contains('unseen import'));
    expect(await trust.isTrusted('t1', scripts), isFalse);
    expect(trust.approved.every((s) => s.postResponse.isEmpty), isTrue);
    expect(find.text('TRUST SCRIPTS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
  });

  testWidgets('tapping a section writes the shared index', (tester) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
    final sectionIndex = RequestSectionIndex();
    addTearDown(sectionIndex.dispose);
    final bodyController = CodeLineEditingController();
    addTearDown(bodyController.dispose);
    final variablesController = CodeLineEditingController();
    addTearDown(variablesController.dispose);

    await tester.pumpWidget(
      host(
        bloc: bloc,
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

    // Switch request tabs: the other strip is already on AUTH — on the FIRST
    // frame (pump, not pumpAndSettle: settling would let a stalled offstage
    // warp finish and hide exactly the desync this test exists to catch).
    await tester.pumpWidget(stack(showFirst: false));
    await tester.pump();

    expect(
      find
          .descendant(
            of: find.byKey(const ValueKey('host_b')),
            matching: find.byType(AuthTabView),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find
          .descendant(
            of: find.byKey(const ValueKey('host_b')),
            matching: find.byType(ParamsTabView),
          )
          .hitTestable(),
      findsNothing,
    );
  });

  testWidgets('phone RESPONSE tab stays local; sections still sync', (
    tester,
  ) async {
    final bloc = await _loadedBloc(repository, sendUseCase);
    addTearDown(bloc.close);
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
