// Tests that settings on/off switches are routed through the toggle slot
// (B6 slot work) and remain reachable by their ValueKey after the
// SwitchListTile → ListTile + toggle-slot conversion.
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

SettingsBloc _bloc({SettingsEntity? initial}) {
  final save = _MockSaveSettings();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: initial ?? const SettingsEntity(),
  );
}

Future<void> _openAppearanceTab(WidgetTester tester, SettingsBloc bloc) async {
  final controller = UpdateController(_FakeUpdateRepository());
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
  // Navigate to APPEARANCE to reach reduce_effects_switch / theme_sounds_switch.
  await tester.tap(find.byKey(const ValueKey('settingstab_tab_APPEARANCE')));
  await tester.pumpAndSettle();
}

Future<void> _openGeneralTab(WidgetTester tester, SettingsBloc bloc) async {
  final controller = UpdateController(_FakeUpdateRepository());
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
  // GENERAL is the default tab — no navigation needed.
}

void main() {
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
  });

  group('B6 toggle-slot wiring — APPEARANCE tab', () {
    testWidgets('reduce_effects_switch is reachable by key', (tester) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _openAppearanceTab(tester, bloc);

      expect(
        find.byKey(const ValueKey('reduce_effects_switch')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping reduce_effects_switch toggles reduceVisualEffects',
      (tester) async {
        // reduceVisualEffects defaults to false — no need to supply initial.
        final bloc = _bloc();
        addTearDown(bloc.close);
        await _openAppearanceTab(tester, bloc);

        expect(bloc.state.settings.reduceVisualEffects, isFalse);

        // Tap the keyed subtree (wraps the Switch produced by the slot).
        await tester.tap(find.byKey(const ValueKey('reduce_effects_switch')));
        await tester.pump();

        expect(bloc.state.settings.reduceVisualEffects, isTrue);
      },
    );

    testWidgets(
      'tapping ListTile row (onTap) also toggles reduce_effects_switch',
      (tester) async {
        final bloc = _bloc();
        addTearDown(bloc.close);
        await _openAppearanceTab(tester, bloc);

        // Tap the title text — exercises the ListTile.onTap path.
        await tester.tap(find.text('REDUCE VISUAL EFFECTS'));
        await tester.pump();

        expect(bloc.state.settings.reduceVisualEffects, isTrue);
      },
    );

    testWidgets('theme_sounds_switch is reachable by key', (tester) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _openAppearanceTab(tester, bloc);

      expect(
        find.byKey(const ValueKey('theme_sounds_switch')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping theme_sounds_switch dispatches UpdateEnableThemeSounds',
      (tester) async {
        // enableThemeSounds defaults to false; supply true to test the flip.
        final bloc = _bloc(
          initial: const SettingsEntity(enableThemeSounds: true),
        );
        addTearDown(bloc.close);
        await _openAppearanceTab(tester, bloc);

        expect(bloc.state.settings.enableThemeSounds, isTrue);

        await tester.tap(find.byKey(const ValueKey('theme_sounds_switch')));
        await tester.pump();

        expect(bloc.state.settings.enableThemeSounds, isFalse);
      },
    );
  });

  group('B6 toggle-slot wiring — GENERAL tab', () {
    testWidgets('save_large_responses_switch is reachable by key', (
      tester,
    ) async {
      final bloc = _bloc();
      addTearDown(bloc.close);
      await _openGeneralTab(tester, bloc);

      expect(
        find.byKey(const ValueKey('save_large_responses_switch')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping save_large_responses_switch toggles the setting',
      (tester) async {
        // saveLargeResponsesInHistory defaults to true; no explicit initial.
        final bloc = _bloc();
        addTearDown(bloc.close);
        await _openGeneralTab(tester, bloc);

        expect(bloc.state.settings.saveLargeResponsesInHistory, isTrue);

        await tester.tap(
          find.byKey(const ValueKey('save_large_responses_switch')),
        );
        await tester.pump();

        expect(bloc.state.settings.saveLargeResponsesInHistory, isFalse);
      },
    );
  });
}
