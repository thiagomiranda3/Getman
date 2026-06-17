// Widget tests for the row⇄bulk edit toggle on the PARAMS and HEADERS tabs.
//
// Both tab views require a TabsBloc (the canonical value + UpdateTab path),
// plus SettingsBloc + EnvironmentsBloc (read by _VariableContextBuilder even
// when no environment is active). The toggle flips between the row editor
// (KeyValueListEditor) and the bulk editor (BulkKvEditor); both feed the same
// encode/decode closures, so the round-trip is lossless.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/request_editor_tabs.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class MockPutEnvironmentUseCase extends Mock implements PutEnvironmentUseCase {}

class MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

/// A [SettingsBloc] backed by a no-op save, seeded with [settings].
SettingsBloc _settingsBloc(SettingsEntity settings) {
  final saveUseCase = MockSaveSettingsUseCase();
  when(() => saveUseCase(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: saveUseCase,
    initialSettings: settings,
  );
}

/// An [EnvironmentsBloc] with no environments — the toggle test never asserts
/// on resolution, so an empty set is fine.
EnvironmentsBloc _environmentsBloc() {
  final get = MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => const <EnvironmentEntity>[]);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: MockDeleteEnvironmentUseCase(),
  );
}

/// Creates and loads a [TabsBloc] whose state contains [tab].
Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
  MockSendRequestUseCase useCase,
  HttpRequestTabEntity tab,
) async {
  when(() => repository.getPanels()).thenAnswer(
    (_) async => [
      PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [tab],
        activeTabId: tab.tabId,
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
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
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

  Future<void> pumpTab(WidgetTester tester, TabsBloc bloc, Widget child) async {
    // Build the settings + environments blocs eagerly (their mock use-case
    // stubbing must not run inside a BlocProvider `create:` callback during
    // pump — mocktail forbids calling `when` mid-stub).
    final settingsBloc = _settingsBloc(const SettingsEntity());
    addTearDown(settingsBloc.close);
    final environmentsBloc = _environmentsBloc();
    addTearDown(environmentsBloc.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: bloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<EnvironmentsBloc>.value(value: environmentsBloc),
            ],
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpHeadersTab(WidgetTester tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 't',
      config: HttpRequestConfigEntity(id: 't', headers: {'Accept': '*/*'}),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);
    await pumpTab(tester, bloc, const HeadersTabView(tabId: 't'));
  }

  Future<void> pumpParamsTab(WidgetTester tester) async {
    // Params derive from the URL (single source of truth), so seed via query.
    const tab = HttpRequestTabEntity(
      tabId: 't',
      config: HttpRequestConfigEntity(id: 't', url: 'https://x.test/?q=1'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);
    await pumpTab(tester, bloc, const ParamsTabView(tabId: 't'));
  }

  testWidgets('headers tab starts in row mode (no bulk editor)', (
    tester,
  ) async {
    await pumpHeadersTab(tester);
    expect(
      find.byType(KeyValueListEditor<Map<String, String>>),
      findsOneWidget,
    );
    expect(find.byType(BulkKvEditor), findsNothing);
    expect(find.byTooltip('Bulk edit'), findsOneWidget);
  });

  testWidgets('toggling headers to bulk shows the serialized block', (
    tester,
  ) async {
    await pumpHeadersTab(tester);
    await tester.tap(find.byTooltip('Bulk edit'));
    await tester.pumpAndSettle();

    expect(find.byType(BulkKvEditor), findsOneWidget);
    expect(find.byType(KeyValueListEditor<Map<String, String>>), findsNothing);
    // Seeded {'Accept': '*/*'} serialized into the text block.
    expect(find.widgetWithText(TextField, 'Accept: */*'), findsOneWidget);
    // The toggle now offers the reverse action.
    expect(find.byTooltip('Edit as rows'), findsOneWidget);
  });

  testWidgets('editing in bulk mode then back to rows reflects the parse', (
    tester,
  ) async {
    await pumpHeadersTab(tester);
    await tester.tap(find.byTooltip('Bulk edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Accept: */*\nX-Token: abc',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Edit as rows'));
    await tester.pumpAndSettle();

    expect(
      find.byType(KeyValueListEditor<Map<String, String>>),
      findsOneWidget,
    );
    expect(find.text('X-Token'), findsOneWidget);
    expect(find.text('abc'), findsOneWidget);

    // Flush the 10s debounced-save timer the UpdateTab scheduled.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('params tab also offers the bulk toggle', (tester) async {
    await pumpParamsTab(tester);
    expect(find.byTooltip('Bulk edit'), findsOneWidget);
  });
}
