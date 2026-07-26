import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/widgets/settings_dialog.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSaveSettings extends Mock implements SaveSettingsUseCase {}

class _MockCookieStore extends Mock implements CookieStore {}

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

Future<void> _open(
  WidgetTester tester,
  SettingsBloc bloc, {
  SettingsTab initialTab = SettingsTab.general,
  CookieStore? cookieStore,
}) async {
  final controller = _controller();
  addTearDown(controller.dispose);
  final app = ChangeNotifierProvider<UpdateController>.value(
    value: controller,
    child: MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  SettingsDialog.show(context, initialTab: initialTab),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    cookieStore == null
        ? app
        : RepositoryProvider<CookieStore>.value(value: cookieStore, child: app),
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

  group('APPEARANCE pane controls dispatch their Update events', () {
    testWidgets('tapping the DARK MODE row toggles isDarkMode', (tester) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc, initialTab: SettingsTab.appearance);

      expect(bloc.state.settings.isDarkMode, isFalse);
      await tester.tap(find.text('DARK MODE'));
      await tester.pumpAndSettle();

      expect(bloc.state.settings.isDarkMode, isTrue);
    });

    testWidgets('selecting a theme in the dropdown dispatches UpdateThemeId', (
      tester,
    ) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc, initialTab: SettingsTab.appearance);

      await tester.tap(find.byKey(const ValueKey('theme_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DRACULA').last);
      await tester.pumpAndSettle();

      expect(bloc.state.settings.themeId, kDraculaThemeId);
    });

    testWidgets('tapping the COMPACT MODE row toggles isCompactMode', (
      tester,
    ) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc, initialTab: SettingsTab.appearance);

      await tester.tap(find.text('COMPACT MODE'));
      await tester.pumpAndSettle();

      expect(bloc.state.settings.isCompactMode, isTrue);
    });
  });

  group('NETWORK pane controls dispatch their Update events', () {
    testWidgets('turning FOLLOW REDIRECTS off hides the MAX REDIRECTS row', (
      tester,
    ) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc, initialTab: SettingsTab.network);

      expect(find.text('MAX REDIRECTS'), findsOneWidget);

      await tester.tap(find.text('FOLLOW REDIRECTS'));
      await tester.pumpAndSettle();

      expect(bloc.state.settings.followRedirects, isFalse);
      expect(find.text('MAX REDIRECTS'), findsNothing);
    });

    testWidgets('tapping the VERIFY SSL row toggles verifySsl', (tester) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc, initialTab: SettingsTab.network);

      await tester.tap(find.text('VERIFY SSL'));
      await tester.pumpAndSettle();

      expect(bloc.state.settings.verifySsl, isFalse);
    });

    testWidgets('proxy field sets proxyUrl per keystroke; blank clears it', (
      tester,
    ) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc, initialTab: SettingsTab.network);

      final proxyField = find.widgetWithText(TextField, 'e.g. 127.0.0.1:8888');
      await tester.enterText(proxyField, ' 127.0.0.1:8888 ');
      await tester.pump();
      expect(bloc.state.settings.proxyUrl, '127.0.0.1:8888');

      await tester.enterText(proxyField, '   ');
      await tester.pump();
      expect(bloc.state.settings.proxyUrl, isNull);
    });

    testWidgets(
      'CLEAR cookies confirms via ConfirmDialog, clears the store, and shows '
      'a snackbar',
      (tester) async {
        final bloc = _bloc();
        addTearDown(bloc.close);
        final store = _MockCookieStore();
        when(store.clear).thenAnswer((_) async {});
        await _open(
          tester,
          bloc,
          initialTab: SettingsTab.network,
          cookieStore: store,
        );

        // The COOKIES row is the last item in the scrollable NETWORK pane —
        // scroll it into view or the tap lands on nothing.
        final clearButton = find.widgetWithText(TextButton, 'CLEAR');
        await tester.ensureVisible(clearButton);
        await tester.pumpAndSettle();
        await tester.tap(clearButton);
        await tester.pumpAndSettle();

        expect(find.text('Clear cookies?'), findsOneWidget);
        verifyNever(store.clear);

        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('CLEAR'),
          ),
        );
        await tester.pumpAndSettle();

        verify(store.clear).called(1);
        expect(find.text('Cookie jar cleared'), findsOneWidget);
      },
    );

    testWidgets('cancelling the clear-cookies confirm leaves the store alone', (
      tester,
    ) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      final store = _MockCookieStore();
      when(store.clear).thenAnswer((_) async {});
      await _open(
        tester,
        bloc,
        initialTab: SettingsTab.network,
        cookieStore: store,
      );

      final clearButton = find.widgetWithText(TextButton, 'CLEAR');
      await tester.ensureVisible(clearButton);
      await tester.pumpAndSettle();
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      verifyNever(store.clear);
      expect(find.text('Cookie jar cleared'), findsNothing);
    });
  });

  testWidgets('show(initialTab:) deep-links straight to the requested pane', (
    tester,
  ) async {
    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc, initialTab: SettingsTab.workspace);

    expect(find.text('CHOOSE FOLDER'), findsOneWidget);
    expect(find.text('COMMIT IDENTITY'), findsOneWidget);
    expect(find.byKey(const ValueKey('history_limit_field')), findsNothing);
  });

  testWidgets('narrow viewports render the dialog as a full-screen page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = _bloc();
    addTearDown(bloc.close);
    await _open(tester, bloc);

    // Fullscreen chrome: back arrow instead of a floating AlertDialog.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('BACK'), findsOneWidget);
    // The panes still work.
    expect(
      find.byKey(const ValueKey('settingstab_tab_GENERAL')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('history_limit_field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a settings emission from elsewhere echoes into unfocused number fields',
    (tester) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _open(tester, bloc);

      // Dispatch straight on the bloc (as another widget/service would). The
      // bloc was created inside this test's FakeAsync zone, so plain pumps
      // flush its emission through to the dialog's BlocConsumer — do NOT wrap
      // this in runAsync (awaiting the fake-zone stream there deadlocks).
      bloc.add(const UpdateHistoryLimit(7));
      await tester.pumpAndSettle();
      expect(bloc.state.settings.historyLimit, 7);

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('history_limit_field')),
      );
      expect(field.controller!.text, '7');
    },
  );
}
