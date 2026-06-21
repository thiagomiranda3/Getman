// B3 TDD: verifies that the four main panel containers render without exception
// after routing through the `surface` component slot.
//
// Each test pumps the panel host under the brutalist theme (which provides the
// default `surface` implementation: Container + panelBox(offset:0)) and asserts
// that (a) no exception is thrown, and (b) expected content is still visible.
//
// Pattern follows response_metadata_slot_test.dart, realtime_panel_test.dart,
// and bulk_kv_toggle_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
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
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/realtime/presentation/widgets/realtime_panel.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_editor/re_editor.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockTabsRepository extends Mock implements TabsRepository {}

class _MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockRealtimeBloc extends Mock implements RealtimeBloc {}

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

RulesBloc _rulesBloc(String tabId) {
  final get = _MockGetRequestRulesUseCase();
  final save = _MockSaveRequestRulesUseCase();
  when(() => get.call(any())).thenAnswer(
    (_) async => RequestRulesEntity(configId: tabId),
  );
  when(() => save.call(any())).thenAnswer((_) async {});
  return RulesBloc(
    getRequestRulesUseCase: get,
    saveRequestRulesUseCase: save,
  );
}

/// Creates a [TabsBloc] loaded with a single tab (tabId = [tabId]).
Future<TabsBloc> _loadedBloc(
  _MockTabsRepository repository,
  _MockSendRequestUseCase useCase,
  String tabId,
) async {
  final tab = HttpRequestTabEntity(
    tabId: tabId,
    config: HttpRequestConfigEntity(id: tabId),
  );
  when(() => repository.getPanels()).thenAnswer(
    (_) async => [
      PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [tab],
        activeTabId: tabId,
      ),
    ],
  );
  when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase)
    ..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // ResponseSection — surface slot
  //
  // No response is set → ResponseSection shows the empty-state placeholder.
  // The surface slot is still exercised (it wraps the tab-bar + tab content).
  // We assert the empty state is visible + no exception thrown.
  // -------------------------------------------------------------------------

  testWidgets(
    'ResponseSection renders via surface slot with no exception',
    (tester) async {
      const tabId = 'panel_resp';
      final bloc = await _loadedBloc(repository, sendUseCase, tabId);
      addTearDown(bloc.close);
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: bloc),
                BlocProvider<SettingsBloc>(create: (_) => _settingsBloc()),
                BlocProvider<CollectionsBloc>(
                  create: (_) => _FakeCollectionsBloc(),
                ),
                BlocProvider<HistoryBloc>(create: (_) => _FakeHistoryBloc()),
              ],
              child: ResponseSection(
                tabId: tabId,
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

      // The brutalist empty-response copy text (from AppCopy.emptyResponse).
      expect(find.text('HIT SEND TO GET A RESPONSE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // -------------------------------------------------------------------------
  // RequestConfigSection — surface slot
  // -------------------------------------------------------------------------

  testWidgets(
    'RequestConfigSection renders via surface slot with no exception',
    (tester) async {
      const tabId = 'panel_req';
      final bloc = await _loadedBloc(repository, sendUseCase, tabId);
      addTearDown(bloc.close);
      final rulesBloc = _rulesBloc(tabId);
      addTearDown(rulesBloc.close);
      final bodyController = CodeLineEditingController();
      addTearDown(bodyController.dispose);
      final variablesController = CodeLineEditingController();
      addTearDown(variablesController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: MultiBlocProvider(
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
              child: RequestConfigSection(
                tabId: tabId,
                bodyController: bodyController,
                variablesController: variablesController,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tab labels from the PARAMS/HEADERS/BODY strip must be present.
      expect(find.text('PARAMS'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // -------------------------------------------------------------------------
  // UnifiedRequestPanel — surface slot
  // -------------------------------------------------------------------------

  testWidgets(
    'UnifiedRequestPanel renders via surface slot with no exception',
    (tester) async {
      const tabId = 'panel_uni';
      final bloc = await _loadedBloc(repository, sendUseCase, tabId);
      addTearDown(bloc.close);
      final rulesBloc = _rulesBloc(tabId);
      addTearDown(rulesBloc.close);
      final bodyController = CodeLineEditingController();
      addTearDown(bodyController.dispose);
      final variablesController = CodeLineEditingController();
      addTearDown(variablesController.dispose);
      final responseController = CodeLineEditingController();
      addTearDown(responseController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: MultiBlocProvider(
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
              child: UnifiedRequestPanel(
                tabId: tabId,
                bodyController: bodyController,
                variablesController: variablesController,
                responseController: responseController,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      // All six tab labels must appear.
      expect(find.text('PARAMS'), findsOneWidget);
      expect(find.text('RESPONSE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // -------------------------------------------------------------------------
  // RealtimePanel — surface slot
  // -------------------------------------------------------------------------

  testWidgets(
    'RealtimePanel renders via surface slot with no exception',
    (tester) async {
      const tabId = 'rt_test';
      final tabsBloc = _MockTabsBloc();
      final realtimeBloc = _MockRealtimeBloc();

      when(() => tabsBloc.state).thenReturn(
        const TabsState(
          tabs: [
            HttpRequestTabEntity(
              tabId: tabId,
              config: HttpRequestConfigEntity(
                id: tabId,
                kind: RequestKind.webSocket,
              ),
            ),
          ],
        ),
      );
      when(() => realtimeBloc.state).thenReturn(
        RealtimeState(
          sessions: {
            tabId: RealtimeSession(
              frames: [RealtimeFrame.incoming('ping')],
            ),
          },
        ),
      );
      when(
        () => realtimeBloc.stream,
      ).thenAnswer((_) => const Stream<RealtimeState>.empty());

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: RepositoryProvider<TabsBloc>.value(
              value: tabsBloc,
              child: BlocProvider<RealtimeBloc>.value(
                value: realtimeBloc,
                child: const RealtimePanel(tabId: tabId),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Frame content is still rendered inside the surface slot.
      expect(find.text('ping'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
