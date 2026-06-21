// Widget tests for EnvironmentsDialog:
// - environment list renders;
// - ADD button opens a name prompt and dispatches AddEnvironment carrying
//   a full EnvironmentEntity (not just a name);
// - deleting the active environment confirms via ConfirmDialog then dispatches
//   UpdateActiveEnvironmentId(null) on SettingsBloc;
// - deleting a non-active env does NOT touch the active id.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/widgets/environments_dialog.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockEnvironmentsRepository extends Mock
    implements EnvironmentsRepository {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

EnvironmentsBloc _makeEnvsBloc(
  MockEnvironmentsRepository repo,
  List<EnvironmentEntity> initial,
) {
  return EnvironmentsBloc(
    getEnvironmentsUseCase: GetEnvironmentsUseCase(repo),
    saveEnvironmentsUseCase: SaveEnvironmentsUseCase(repo),
    putEnvironmentUseCase: PutEnvironmentUseCase(repo),
    deleteEnvironmentUseCase: DeleteEnvironmentUseCase(repo),
    initialEnvironments: initial,
  );
}

SettingsBloc _makeSettingsBloc(
  MockSaveSettingsUseCase uc, {
  String? activeEnvId,
}) {
  return SettingsBloc(
    saveSettingsUseCase: uc,
    initialSettings: SettingsEntity(activeEnvironmentId: activeEnvId),
  );
}

/// Pumps a scaffold with a button that opens EnvironmentsDialog.show().
/// After tapping the button, the dialog is on screen.
Future<void> _pumpAndOpen(
  WidgetTester tester, {
  required EnvironmentsBloc envsBloc,
  required SettingsBloc settingsBloc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: envsBloc),
            BlocProvider.value(value: settingsBloc),
          ],
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => EnvironmentsDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late MockEnvironmentsRepository repo;
  late MockSaveSettingsUseCase settingsUc;

  final env1 = EnvironmentEntity(id: 'e1', name: 'Production');
  final env2 = EnvironmentEntity(id: 'e2', name: 'Staging');

  setUpAll(() {
    registerFallbackValue(EnvironmentEntity(id: 'fallback', name: 'fallback'));
    registerFallbackValue(<EnvironmentEntity>[]);
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    repo = MockEnvironmentsRepository();
    when(() => repo.putEnvironment(any())).thenAnswer((_) async {});
    when(() => repo.deleteEnvironment(any())).thenAnswer((_) async {});
    when(() => repo.saveEnvironments(any())).thenAnswer((_) async {});

    settingsUc = MockSaveSettingsUseCase();
    when(() => settingsUc(any())).thenAnswer((_) async {});
  });

  testWidgets('renders environment names in the list', (tester) async {
    final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
    final settingsBloc = _makeSettingsBloc(settingsUc);
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pumpAndOpen(
      tester,
      envsBloc: envsBloc,
      settingsBloc: settingsBloc,
    );

    // The wide layout auto-selects the first env, so 'Production' appears in
    // both the list tile AND the editor pane's name field.
    expect(find.text('Production'), findsWidgets);
    expect(find.text('Staging'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state shows no-environments placeholder', (tester) async {
    final envsBloc = _makeEnvsBloc(repo, const []);
    final settingsBloc = _makeSettingsBloc(settingsUc);
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pumpAndOpen(
      tester,
      envsBloc: envsBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.textContaining('No environments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ADD button opens name prompt and dispatches AddEnvironment with an entity',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, const []);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      // Tap the + button to open the name prompt.
      await tester.tap(find.byKey(const ValueKey('new_environment_button')));
      await tester.pumpAndSettle();

      // The name prompt dialog should be visible.
      expect(find.text('NEW ENVIRONMENT'), findsOneWidget);

      // Type a name and confirm.
      await tester.enterText(find.byType(TextField).last, 'My API');
      await tester.pumpAndSettle();
      await tester.tap(find.text('CREATE'));
      await tester.pumpAndSettle();

      // Wait for persistence.
      await untilCalled(() => repo.putEnvironment(any()));

      // The new env must be in the bloc state — confirming AddEnvironment
      // carries a full entity (the id was generated in the widget before the
      // event was dispatched, so the bloc state knows it immediately).
      final added = envsBloc.state.environments;
      expect(added, hasLength(1));
      expect(added.first.name, 'My API');
      // id must be a real non-empty string (not blank / placeholder).
      expect(added.first.id, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleting the active env confirms via ConfirmDialog then '
    'clears activeEnvironmentId',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, [env1]);
      // env1 is active.
      final settingsBloc = _makeSettingsBloc(settingsUc, activeEnvId: 'e1');
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      // Tap the delete icon for the single (active) environment.
      await tester.tap(find.byTooltip('Delete environment'));
      await tester.pumpAndSettle();

      // ConfirmDialog should be visible.
      expect(find.text('Delete environment?'), findsOneWidget);

      // Confirm the deletion.
      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      // DeleteEnvironment fired.
      await untilCalled(() => repo.deleteEnvironment(any()));

      // The active env id must have been cleared
      // (UpdateActiveEnvironmentId(null)).
      await untilCalled(() => settingsUc(any()));
      expect(settingsBloc.state.settings.activeEnvironmentId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleting a non-active env does NOT touch the active environment id',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
      // env1 is active; we delete env2 (non-active).
      final settingsBloc = _makeSettingsBloc(settingsUc, activeEnvId: 'e1');
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      // Find the delete icon for Staging (env2, which is NOT active).
      // The wide layout auto-selects the first env (env1), so env2 is the
      // second tile. Use byTooltip with index 1 (second delete icon).
      final deleteIcons = find.byTooltip('Delete environment');
      expect(deleteIcons, findsNWidgets(2));
      await tester.tap(deleteIcons.at(1)); // env2's delete
      await tester.pumpAndSettle();

      await tester.tap(find.text('DELETE'));
      await tester.pumpAndSettle();

      await untilCalled(() => repo.deleteEnvironment(any()));

      // env1 remains active — settings bloc MUST NOT have been asked to change.
      expect(settingsBloc.state.settings.activeEnvironmentId, 'e1');
      expect(tester.takeException(), isNull);
    },
  );
}
