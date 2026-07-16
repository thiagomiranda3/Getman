// Widget tests for form-data value-field variable autocomplete.
//
// Verifies that non-file VALUE fields in FormDataEditor offer {{var}}
// autocomplete (via VariableTextField) while the KEY/name field remains a
// plain TextField with no autocomplete overlay.
//
// Uses the same four-bloc harness as bulk_kv_toggle_test.dart because
// TabVariableContextBuilder reads SettingsBloc + EnvironmentsBloc +
// CollectionsBloc + TabsBloc.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
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
import 'package:getman/features/tabs/presentation/widgets/form_data_editor.dart';
import 'package:mocktail/mocktail.dart';

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

class _MockGetCollectionsUseCase extends Mock
    implements GetCollectionsUseCase {}

class _MockSaveCollectionsUseCase extends Mock
    implements SaveCollectionsUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

// A pre-built environment with a single variable so we can assert on it.
final _env = EnvironmentEntity(
  id: 'env1',
  name: 'Test',
  variables: const {'host': 'example.com'},
);

SettingsBloc _settingsBloc() {
  final save = _MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity().copyWith(
      activeEnvironmentId: 'env1',
    ),
  );
}

EnvironmentsBloc _environmentsBloc() {
  final get = _MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => [_env]);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: _MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: _MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: _MockDeleteEnvironmentUseCase(),
    initialEnvironments: [_env],
  );
}

CollectionsBloc _collectionsBloc() {
  final get = _MockGetCollectionsUseCase();
  when(get.call).thenAnswer((_) async => const <CollectionNodeEntity>[]);
  return CollectionsBloc(
    getCollectionsUseCase: get,
    saveCollectionsUseCase: _MockSaveCollectionsUseCase(),
  );
}

Future<TabsBloc> _loadedBloc(
  _MockTabsRepository repository,
  _MockSendRequestUseCase useCase,
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
  late _MockTabsRepository repository;
  late _MockSendRequestUseCase sendRequestUseCase;

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
    sendRequestUseCase = _MockSendRequestUseCase();
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

  Future<void> pumpEditor(
    WidgetTester tester,
    TabsBloc bloc, {
    bool allowFiles = true,
  }) async {
    final settingsBloc = _settingsBloc();
    addTearDown(settingsBloc.close);
    final environmentsBloc = _environmentsBloc();
    addTearDown(environmentsBloc.close);
    final collectionsBloc = _collectionsBloc();
    addTearDown(collectionsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: bloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<EnvironmentsBloc>.value(value: environmentsBloc),
              BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
            ],
            child: FormDataEditor(tabId: 't', allowFiles: allowFiles),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Finds a TextField whose InputDecoration hint text matches [hint].
  Finder fieldByHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
    description: '$hint text field',
  );

  testWidgets(
    'value field shows variable suggestion when typing {{ho and accepts it',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 't',
        config: HttpRequestConfigEntity(
          id: 't',
          formFields: [MultipartFieldEntity(name: 'param')],
        ),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await pumpEditor(tester, bloc);

      // Enter partial variable name into the first VALUE field.
      // tap first so the FocusNode is focused before the text change arrives.
      final valueFields = fieldByHint('VALUE');
      expect(valueFields, findsAtLeastNWidgets(1));
      await tester.tap(valueFields.first);
      await tester.enterText(valueFields.first, '{{ho');
      await tester.pumpAndSettle();

      // The autocomplete overlay must show the 'host' suggestion.
      expect(find.text('host'), findsOneWidget);

      // Tapping the suggestion completes the token.
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();

      // The VALUE controller text is now the completed variable.
      final tf = tester.widget<TextField>(valueFields.first);
      expect(tf.controller?.text, '{{host}}');

      // Flush the 10 s debounced-save timer.
      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'deleting the trailing blank row (with a non-empty row remaining) '
    'still leaves an "add new row" affordance',
    (tester) async {
      // Repro (A2): rows [param=<blank name>, <blank>] where the first row
      // already has a name. Deleting the trailing blank row must not strand
      // the editor with zero blank rows to add a new field into.
      const tab = HttpRequestTabEntity(
        tabId: 't',
        config: HttpRequestConfigEntity(
          id: 't',
          formFields: [MultipartFieldEntity(name: 'param')],
        ),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await pumpEditor(tester, bloc);

      final nameFields = fieldByHint('KEY');
      expect(nameFields, findsNWidgets(2));

      // Delete the trailing (blank) row.
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pump();

      expect(
        fieldByHint('KEY'),
        findsNWidgets(2),
        reason:
            'a blank trailing row must survive so the user can still '
            'add a new field',
      );

      await tester.pump(const Duration(seconds: 11));
    },
  );

  testWidgets(
    'name (KEY) field does not show variable autocomplete overlay',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 't',
        config: HttpRequestConfigEntity(id: 't'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await pumpEditor(tester, bloc);

      // Type a variable prefix into the KEY field.
      final nameFields = fieldByHint('KEY');
      expect(nameFields, findsAtLeastNWidgets(1));
      await tester.enterText(nameFields.first, '{{');
      await tester.pumpAndSettle();

      // No autocomplete overlay — the KEY field is a plain TextField.
      expect(find.text('host'), findsNothing);

      // Flush the debounced-save timer triggered by the name-field onChanged.
      await tester.pump(const Duration(seconds: 11));
    },
  );
}
