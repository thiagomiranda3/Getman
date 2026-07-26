// Widget tests for EnvironmentsDialog:
// - environment list renders;
// - ADD button opens a name prompt and dispatches AddEnvironment carrying
//   a full EnvironmentEntity (not just a name);
// - deleting the active environment confirms via ConfirmDialog then dispatches
//   UpdateActiveEnvironmentId(null) on SettingsBloc;
// - deleting a non-active env does NOT touch the active id;
// - deleting any environment offers a real, TAPPABLE UNDO snackbar (while
//   the dialog stays open) that restores the full entity (incl. secretKeys)
//   and re-activates it when it was active -- these tap `find.text('UNDO')`
//   with a plain tester.tap (no warnIfMissed/retargeting), which is the
//   regression coverage for the dialog-barrier-swallows-the-tap defect;
// - closing the dialog with a snackbar still pending does not crash;
// - wide layout: tapping a tile selects it in the editor pane, and an
//   externally-deleted selection reconciles instead of dangling;
// - Postman import/export flows run against a file picker mocked at the
//   method-channel level (import feeds bytes back; export asserts the
//   suggested file name and treats the pick as cancelled);
// - narrow (fullscreen) layout: list page first, tap-to-detail, back-to-list
//   (toolbar arrow AND system back via PopScope), close from the list page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/postman/postman_environment_mapper.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/widgets/environments_dialog.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockEnvironmentsRepository extends Mock
    implements EnvironmentsRepository {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

/// file_picker's default platform implementation talks over this channel;
/// mocking it lets the dialog's real import/export flows run end-to-end
/// without any implementation imports.
const _pickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// Answers `pickFiles` (method name = FileType name, `custom` here) with
/// [importBytes] (or a cancellation when null) and `saveFile` (`save`) with a
/// cancellation, recording every save's suggested file name in [savedNames].
void _mockPicker(
  WidgetTester tester, {
  List<int>? importBytes,
  List<String?>? savedNames,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _pickerChannel,
    (call) async {
      if (call.method == 'save') {
        final args = call.arguments as Map<dynamic, dynamic>;
        savedNames?.add(args['fileName'] as String?);
        return null; // user cancels the destination dialog
      }
      if (importBytes == null) return null; // user cancelled the pick
      return <Map<dynamic, dynamic>>[
        {
          'name': 'picked.postman_environment.json',
          'path': null,
          'bytes': Uint8List.fromList(importBytes),
          'size': importBytes.length,
        },
      ];
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _pickerChannel,
      null,
    ),
  );
}

/// Shrinks the surface below the 700 px phone breakpoint so the dialog takes
/// its narrow (fullscreen two-page) path.
void _useNarrowSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  testWidgets('deleting an environment offers UNDO which restores the full '
      'entity', (tester) async {
    final secretEnv = EnvironmentEntity(
      id: 'e3',
      name: 'Prod-Secrets',
      variables: const {'token': 'shh', 'host': 'api.dev'},
      secretKeys: const {'token'},
    );
    final envsBloc = _makeEnvsBloc(repo, [secretEnv]);
    final settingsBloc = _makeSettingsBloc(settingsUc);
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pumpAndOpen(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);

    // Delete (confirm stays for environments — A1).
    await tester.tap(find.byTooltip('Delete environment'));
    await tester.pumpAndSettle();
    expect(find.text('Delete environment?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
    await tester.pumpAndSettle();

    // Environment is deleted; UNDO snackbar appears with an action to
    // restore the entity. The dialog stays open (modal) throughout — the
    // snackbar must be hosted so this tap actually lands (regression for the
    // dialog-barrier-swallows-the-tap defect).
    expect(envsBloc.state.environments, isEmpty);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    expect(envsBloc.state.environments.single, secretEnv);
    expect(envsBloc.state.environments.single.secretKeys, {'token'});
  });

  testWidgets('UNDO after deleting the ACTIVE environment restores the '
      'active id too', (tester) async {
    final envsBloc = _makeEnvsBloc(repo, [env1]);
    final settingsBloc = _makeSettingsBloc(settingsUc, activeEnvId: 'e1');
    addTearDown(envsBloc.close);
    addTearDown(settingsBloc.close);

    await _pumpAndOpen(tester, envsBloc: envsBloc, settingsBloc: settingsBloc);

    // Tap delete and confirm.
    await tester.tap(find.byTooltip('Delete environment'));
    await tester.pumpAndSettle();
    expect(find.text('Delete environment?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
    await tester.pumpAndSettle();

    // Active environment id is cleared after deletion.
    expect(settingsBloc.state.settings.activeEnvironmentId, isNull);
    expect(envsBloc.state.environments, isEmpty);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    expect(envsBloc.state.environments.single.id, 'e1');
    expect(settingsBloc.state.settings.activeEnvironmentId, 'e1');
  });

  testWidgets(
    'delete shows the UNDO snackbar hosted INSIDE the still-open dialog '
    '(not behind its modal barrier)',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, [env1]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      await tester.tap(find.byTooltip('Delete environment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
      await tester.pumpAndSettle();

      // The dialog is still open (its title/CLOSE action are present) AND
      // the snackbar is visible — both must be true simultaneously for the
      // snackbar to be reachable at all.
      expect(find.text('ENVIRONMENTS'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'CLOSE'), findsOneWidget);
      expect(find.text('UNDO'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'closing the dialog right after a delete does not crash while the UNDO '
    'snackbar is still pending',
    (tester) async {
      final envsBloc = _makeEnvsBloc(repo, [env1]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      await tester.tap(find.byTooltip('Delete environment'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
      await tester.pumpAndSettle();

      expect(find.text('UNDO'), findsOneWidget);

      // Close the dialog (its own ScaffoldMessenger + pending snackbar
      // timer get disposed with it) well before the 5s snackbar duration
      // elapses.
      await tester.tap(find.widgetWithText(TextButton, 'CLOSE'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  group('wide layout selection', () {
    testWidgets('tapping a list tile shows it in the editor pane', (
      tester,
    ) async {
      final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      // Auto-selected first env → editor shows Production.
      final nameField = find.byKey(const ValueKey('env_name_field'));
      expect(
        tester.widget<TextField>(nameField).controller!.text,
        'Production',
      );

      await tester.tap(find.text('Staging'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(nameField).controller!.text, 'Staging');
    });

    testWidgets(
      'an externally-deleted selection reconciles to the first remaining env',
      (tester) async {
        final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
        final settingsBloc = _makeSettingsBloc(settingsUc);
        addTearDown(envsBloc.close);
        addTearDown(settingsBloc.close);

        await _pumpAndOpen(
          tester,
          envsBloc: envsBloc,
          settingsBloc: settingsBloc,
        );

        await tester.tap(find.text('Staging'));
        await tester.pumpAndSettle();
        final nameField = find.byKey(const ValueKey('env_name_field'));
        expect(tester.widget<TextField>(nameField).controller!.text, 'Staging');

        // Delete the selected env from outside the dialog (as the bloc's
        // other listeners could). The bloc was created inside this test's
        // FakeAsync zone, so plain pumps flush the emission through to the
        // dialog's BlocBuilder — do NOT wrap this in runAsync (awaiting the
        // fake-zone stream there deadlocks).
        envsBloc.add(const DeleteEnvironment('e2'));
        await tester.pumpAndSettle();
        expect(envsBloc.state.environments.map((e) => e.id), ['e1']);

        // Selection fell back to the first remaining environment.
        expect(
          tester.widget<TextField>(nameField).controller!.text,
          'Production',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Postman import/export', () {
    testWidgets(
      'import picks a Postman file, adds and selects the environment, and '
      'reports the count in a snackbar',
      (tester) async {
        final envsBloc = _makeEnvsBloc(repo, const []);
        final settingsBloc = _makeSettingsBloc(settingsUc);
        addTearDown(envsBloc.close);
        addTearDown(settingsBloc.close);

        final imported = EnvironmentEntity(
          id: 'src',
          name: 'Imported Env',
          variables: const {'base': 'https://api.dev'},
        );
        _mockPicker(
          tester,
          importBytes: utf8.encode(PostmanEnvironmentMapper.toJson(imported)),
        );

        await _pumpAndOpen(
          tester,
          envsBloc: envsBloc,
          settingsBloc: settingsBloc,
        );

        await tester.tap(find.byTooltip('IMPORT FROM POSTMAN'));
        await tester.pumpAndSettle();

        final envs = envsBloc.state.environments;
        expect(envs, hasLength(1));
        expect(envs.single.name, 'Imported Env');
        expect(envs.single.variables, {'base': 'https://api.dev'});
        // Imports always get a fresh id so they never collide.
        expect(envs.single.id, isNot('src'));
        // The imported environment becomes the selection in the editor pane.
        final nameField = find.byKey(const ValueKey('env_name_field'));
        expect(
          tester.widget<TextField>(nameField).controller!.text,
          'Imported Env',
        );
        expect(find.text('Imported 1 environment(s).'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a cancelled import changes nothing', (tester) async {
      final envsBloc = _makeEnvsBloc(repo, [env1]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      _mockPicker(tester); // pickFiles answers null → cancelled
      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      await tester.tap(find.byTooltip('IMPORT FROM POSTMAN'));
      await tester.pumpAndSettle();

      expect(envsBloc.state.environments, [env1]);
      expect(find.textContaining('Imported'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'per-environment export suggests a slugged Postman file name',
      (tester) async {
        final envsBloc = _makeEnvsBloc(repo, [env1]);
        final settingsBloc = _makeSettingsBloc(settingsUc);
        addTearDown(envsBloc.close);
        addTearDown(settingsBloc.close);

        final savedNames = <String?>[];
        _mockPicker(tester, savedNames: savedNames);
        await _pumpAndOpen(
          tester,
          envsBloc: envsBloc,
          settingsBloc: settingsBloc,
        );

        await tester.tap(find.byTooltip('Export environment'));
        await tester.pumpAndSettle();

        expect(savedNames, ['production.postman_environment.json']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'EXPORT ALL suggests the multi-environment Postman file name',
      (tester) async {
        final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
        final settingsBloc = _makeSettingsBloc(settingsUc);
        addTearDown(envsBloc.close);
        addTearDown(settingsBloc.close);

        final savedNames = <String?>[];
        _mockPicker(tester, savedNames: savedNames);
        await _pumpAndOpen(
          tester,
          envsBloc: envsBloc,
          settingsBloc: settingsBloc,
        );

        await tester.tap(find.byTooltip('EXPORT ALL ENVIRONMENTS'));
        await tester.pumpAndSettle();

        expect(savedNames, ['environments.postman_environments.json']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('EXPORT ALL is disabled when there are no environments', (
      tester,
    ) async {
      final envsBloc = _makeEnvsBloc(repo, const []);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('EXPORT ALL ENVIRONMENTS'),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('narrow (fullscreen) layout', () {
    testWidgets('opens on the list page without auto-selecting a detail', (
      tester,
    ) async {
      _useNarrowSurface(tester);
      final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      expect(find.text('ENVIRONMENTS'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(find.byKey(const ValueKey('env_name_field')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an env opens its detail page; toolbar back returns '
        'to the list', (tester) async {
      _useNarrowSurface(tester);
      final envsBloc = _makeEnvsBloc(repo, [env1, env2]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      await tester.tap(find.text('Staging'));
      await tester.pumpAndSettle();

      expect(find.text('STAGING'), findsOneWidget); // uppercased page title
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      final nameField = find.byKey(const ValueKey('env_name_field'));
      expect(tester.widget<TextField>(nameField).controller!.text, 'Staging');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('ENVIRONMENTS'), findsOneWidget);
      expect(find.byKey(const ValueKey('env_name_field')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('system back on the detail page pops to the list, not out of '
        'the dialog', (tester) async {
      _useNarrowSurface(tester);
      final envsBloc = _makeEnvsBloc(repo, [env1]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTION'), findsOneWidget);

      // System back → PopScope(canPop: false) intercepts and shows the list.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('ENVIRONMENTS'), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the close button dismisses the dialog from the list page', (
      tester,
    ) async {
      _useNarrowSurface(tester);
      final envsBloc = _makeEnvsBloc(repo, [env1]);
      final settingsBloc = _makeSettingsBloc(settingsUc);
      addTearDown(envsBloc.close);
      addTearDown(settingsBloc.close);

      await _pumpAndOpen(
        tester,
        envsBloc: envsBloc,
        settingsBloc: settingsBloc,
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('ENVIRONMENTS'), findsNothing);
      expect(find.text('open'), findsOneWidget); // back on the base page
      expect(tester.takeException(), isNull);
    });
  });
}
