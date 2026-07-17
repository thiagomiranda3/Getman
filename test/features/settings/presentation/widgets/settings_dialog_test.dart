import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/widgets/settings_dialog.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSaveSettings extends Mock implements SaveSettingsUseCase {}

class _FakeUpdateRepository implements UpdateRepository {
  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform) async =>
      null;
}

SettingsBloc _bloc() {
  final save = _MockSaveSettings();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

/// Like [_bloc] but also returns the save-use-case mock so tests can assert
/// on how many `Update*` events actually reached persistence.
(SettingsBloc, _MockSaveSettings) _blocWithMock() {
  final save = _MockSaveSettings();
  when(() => save(any())).thenAnswer((_) async {});
  final bloc = SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
  return (bloc, save);
}

UpdateController _controller() => UpdateController(_FakeUpdateRepository());

Future<void> _open(WidgetTester tester, SettingsBloc bloc) async {
  final controller = _controller();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<UpdateController>.value(
      value: controller,
      child: MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: BlocProvider.value(
          value: bloc,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
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
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
  });

  testWidgets('shows five tabs; GENERAL is the default pane', (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc);

    expect(
      find.byKey(const ValueKey('settingstab_tab_GENERAL')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingstab_tab_APPEARANCE')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingstab_tab_NETWORK')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingstab_tab_WORKSPACE')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingstab_tab_SHORTCUTS')),
      findsOneWidget,
    );

    // GENERAL active → history limit visible; APPEARANCE's theme dropdown not.
    expect(find.byKey(const ValueKey('history_limit_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_dropdown')), findsNothing);
  });

  testWidgets("switching tabs reveals each pane's controls", (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_APPEARANCE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme_dropdown')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_NETWORK')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receive_timeout_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('cookies_manage_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_WORKSPACE')));
    await tester.pumpAndSettle();
    expect(find.text('CHOOSE FOLDER'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settingstab_tab_SHORTCUTS')));
    await tester.pumpAndSettle();
    // Section headers + a representative shortcut row (platform-independent).
    expect(find.text('REQUEST'), findsOneWidget);
    expect(find.text('PANELS'), findsOneWidget);
    expect(find.text('Send request'), findsOneWidget);
    expect(find.text('Jump to panel 1–9'), findsOneWidget);
  });

  testWidgets('GENERAL tab shows the update settings section', (tester) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc);

    expect(find.byKey(const ValueKey('check_updates_switch')), findsOneWidget);
  });

  group('numeric settings fields commit on blur/submit, not per keystroke', () {
    testWidgets(
      'typing a partial value does not dispatch until blur',
      (tester) async {
        final (bloc, save) = _blocWithMock();
        addTearDown(bloc.close);
        await _open(tester, bloc);

        // "50" typed one keystroke at a time — the "5" midpoint must never
        // reach the bloc (it would irreversibly trim the history box to 5
        // if a send completed in that window).
        await tester.enterText(
          find.byKey(const ValueKey('history_limit_field')),
          '5',
        );
        await tester.pump();
        verifyNever(() => save(any()));
        expect(
          bloc.state.settings.historyLimit,
          const SettingsEntity().historyLimit,
        );

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        verify(() => save(any())).called(1);
        expect(bloc.state.settings.historyLimit, 5);
      },
    );

    testWidgets(
      'an out-of-range value is clamped on blur, the field echoes the '
      'effective value, and exactly one Update event is dispatched',
      (tester) async {
        final (bloc, save) = _blocWithMock();
        addTearDown(bloc.close);
        await _open(tester, bloc);

        await tester.enterText(
          find.byKey(const ValueKey('response_history_limit_field')),
          '999',
        );
        await tester.pump();

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        expect(bloc.state.settings.responseHistoryLimit, 50);
        verify(() => save(any())).called(1);
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('response_history_limit_field')),
        );
        expect(field.controller!.text, '50');
      },
    );

    testWidgets(
      'clearing a numeric field reverts to the current effective value on '
      'blur, dispatching nothing',
      (tester) async {
        final (bloc, save) = _blocWithMock();
        addTearDown(bloc.close);
        await _open(tester, bloc);

        await tester.enterText(
          find.byKey(const ValueKey('history_limit_field')),
          '',
        );
        await tester.pump();

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        verifyNever(() => save(any()));
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('history_limit_field')),
        );
        expect(
          field.controller!.text,
          const SettingsEntity().historyLimit.toString(),
        );
      },
    );

    testWidgets(
      'submitting via Enter commits without waiting for a separate blur',
      (tester) async {
        final (bloc, save) = _blocWithMock();
        addTearDown(bloc.close);
        await _open(tester, bloc);

        await tester.enterText(
          find.byKey(const ValueKey('history_limit_field')),
          '42',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        verify(() => save(any())).called(1);
        expect(bloc.state.settings.historyLimit, 42);
      },
    );

    testWidgets(
      'closing the dialog with a field still focused commits the pending '
      'value instead of dropping it',
      (tester) async {
        final (bloc, save) = _blocWithMock();
        addTearDown(bloc.close);
        await _open(tester, bloc);

        // enterText focuses the field; no blur ever happens before the pop.
        await tester.enterText(
          find.byKey(const ValueKey('history_limit_field')),
          '42',
        );
        await tester.pump();
        verifyNever(() => save(any()));

        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();

        verify(() => save(any())).called(1);
        expect(bloc.state.settings.historyLimit, 42);
      },
    );
  });
}
