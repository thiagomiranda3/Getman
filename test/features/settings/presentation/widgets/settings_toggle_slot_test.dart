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
  // Navigate to APPEARANCE.
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
    testWidgets(
      'REDUCE VISUAL EFFECTS and THEME SOUNDS toggles are removed',
      (tester) async {
        final bloc = _bloc();
        addTearDown(bloc.close);
        await _openAppearanceTab(tester, bloc);

        expect(find.text('REDUCE VISUAL EFFECTS'), findsNothing);
        expect(find.text('THEME SOUNDS'), findsNothing);
        expect(
          find.byKey(const ValueKey('reduce_effects_switch')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('theme_sounds_switch')),
          findsNothing,
        );
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
