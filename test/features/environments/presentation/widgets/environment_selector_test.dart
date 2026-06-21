// Widget tests for EnvironmentSelector: lists No Environment + every env;
// the active row shows a check; selecting a row dispatches
// UpdateActiveEnvironmentId(id); selecting "No Environment" dispatches
// UpdateActiveEnvironmentId(null).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/widgets/environment_selector.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
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

Future<void> _pump(
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
          child: const Center(child: EnvironmentSelector()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the popup menu on the selector button.
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('environment_selector')));
  await tester.pumpAndSettle();
}

void main() {
  late MockEnvironmentsRepository repo;
  late MockSaveSettingsUseCase settingsUc;

  final envs = [
    EnvironmentEntity(id: 'e1', name: 'Production'),
    EnvironmentEntity(id: 'e2', name: 'Staging'),
  ];

  setUpAll(() {
    registerFallbackValue(EnvironmentEntity(id: 'fallback', name: 'fallback'));
    registerFallbackValue(<EnvironmentEntity>[]);
    registerFallbackValue(const SettingsEntity());
    registerFallbackValue(const UpdateActiveEnvironmentId(null));
  });

  setUp(() {
    repo = MockEnvironmentsRepository();
    when(() => repo.putEnvironment(any())).thenAnswer((_) async {});
    when(() => repo.deleteEnvironment(any())).thenAnswer((_) async {});
    when(() => repo.saveEnvironments(any())).thenAnswer((_) async {});

    settingsUc = MockSaveSettingsUseCase();
    when(() => settingsUc(any())).thenAnswer((_) async {});
  });

  testWidgets('popup lists No Environment and all environment names', (
    tester,
  ) async {
    final envsBloc = _makeEnvsBloc(repo, envs);
    final settingsBloc = _makeSettingsBloc(settingsUc);
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pump(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);
    await _openMenu(tester);

    // "No Environment" appears in both the button label and the menu item.
    expect(find.text('No Environment'), findsWidgets);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active env row shows a check icon', (tester) async {
    final envsBloc = _makeEnvsBloc(repo, envs);
    final settingsBloc = _makeSettingsBloc(settingsUc, activeEnvId: 'e1');
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pump(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);
    await _openMenu(tester);

    // One check icon for the active row.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selecting an env dispatches UpdateActiveEnvironmentId with that id',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, envs);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pump(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);
      await _openMenu(tester);

      await tester.tap(find.text('Staging'));
      await tester.pumpAndSettle();

      // Verify the settings bloc received UpdateActiveEnvironmentId('e2').
      await untilCalled(() => settingsUc(any()));
      expect(settingsBloc.state.settings.activeEnvironmentId, 'e2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selecting No Environment dispatches UpdateActiveEnvironmentId(null)',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, envs);
      final settingsBloc = _makeSettingsBloc(settingsUc, activeEnvId: 'e1');
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pump(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);
      await _openMenu(tester);

      // "No Environment" renders both as the closed-selector label and as a
      // menu item; tap the menu item (last in the tree, atop the overlay).
      await tester.tap(find.text('No Environment').last);
      await tester.pumpAndSettle();

      await untilCalled(() => settingsUc(any()));
      expect(settingsBloc.state.settings.activeEnvironmentId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty env list renders only No Environment in popup', (
    tester,
  ) async {
    final envsBloc = _makeEnvsBloc(repo, const []);
    final settingsBloc = _makeSettingsBloc(settingsUc);
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pump(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);
    await _openMenu(tester);

    // "No Environment" appears in both the button label and the menu item.
    expect(find.text('No Environment'), findsWidgets);
    expect(find.text('Production'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
