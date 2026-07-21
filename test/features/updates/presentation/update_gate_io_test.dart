// Widget tests for the io UpdateGate: the two silent-failure bugs (C1/C2)
// where a failed check or a null-changelog release never surfaced anything
// to the user because `updat`'s own `.then`/`.catchError` machinery only
// acts on a non-null `getLatestVersion()` result / non-null changelog.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/update_gate_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// Simulates a real check whose fetch fails end-to-end (mirrors
/// `UpdateRepositoryImpl` swallowing a network/parse error and returning
/// null) — this is the case `_getLatestVersion` must turn into a thrown
/// error rather than a silent null.
class _FailingRepo implements UpdateRepository {
  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform p) async => null;
}

class _ReleaseRepo implements UpdateRepository {
  _ReleaseRepo(this.release);
  final ReleaseInfo release;

  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform p) async => release;
}

class _MockSave extends Mock implements SaveSettingsUseCase {}

void main() {
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
    PackageInfo.setMockInitialValues(
      appName: 'getman',
      packageName: 'com.getman.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  SettingsBloc buildSettingsBloc({bool checkForUpdatesOnStartup = true}) {
    final save = _MockSave();
    when(() => save(any())).thenAnswer((_) async {});
    return SettingsBloc(
      saveSettingsUseCase: save,
      initialSettings: SettingsEntity(
        checkForUpdatesOnStartup: checkForUpdatesOnStartup,
      ),
    );
  }

  Widget harness({
    required UpdateController controller,
    required SettingsBloc bloc,
  }) {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: ChangeNotifierProvider<UpdateController>.value(
        value: controller,
        child: BlocProvider.value(
          value: bloc,
          child: const Scaffold(body: UpdateGate()),
        ),
      ),
    );
  }

  testWidgets(
    'C1: a failed manual check surfaces the error snackbar and resets '
    'manualInFlight',
    (tester) async {
      final controller = UpdateController(_FailingRepo());
      // Startup auto-check disabled: `updat` only re-invokes its status
      // callback when the terminal status *differs* from the last one it
      // saw. With a fake repo that fails/resolves with no real I/O delay, an
      // auto-check that also lands on `error` would leave the widget with no
      // observable transition for the manual check to fire against — so we
      // isolate the manual path here (the one the "CHECK FOR UPDATES" button
      // actually drives) instead of relying on the startup check to run.
      final bloc = buildSettingsBloc(checkForUpdatesOnStartup: false);

      await tester.pumpWidget(harness(controller: controller, bloc: bloc));
      await tester.pumpAndSettle();

      controller.checkNow();
      await tester.pumpAndSettle();

      expect(find.text("Couldn't check for updates."), findsOneWidget);
      expect(controller.manualInFlight, isFalse);
    },
  );

  testWidgets(
    'C2: a release with a null changelog body still prompts the update '
    'dialog',
    (tester) async {
      final controller = UpdateController(
        _ReleaseRepo(
          const ReleaseInfo(
            version: '99.0.0',
            changelog: null,
            assetUrl: 'https://example.com/getman.dmg',
          ),
        ),
      );
      final bloc = buildSettingsBloc();

      await tester.pumpWidget(harness(controller: controller, bloc: bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('update_now_button')), findsOneWidget);
    },
  );

  testWidgets(
    'regression guard: a manual check on the latest version still shows '
    'the up-to-date snackbar',
    (tester) async {
      final controller = UpdateController(
        _ReleaseRepo(
          const ReleaseInfo(version: '1.0.0', changelog: null, assetUrl: null),
        ),
      );
      // See the C1 comment above for why the startup auto-check is disabled
      // here too — this test isolates the manual "CHECK FOR UPDATES" path.
      final bloc = buildSettingsBloc(checkForUpdatesOnStartup: false);

      await tester.pumpWidget(harness(controller: controller, bloc: bloc));
      await tester.pumpAndSettle();

      controller.checkNow();
      await tester.pumpAndSettle();

      expect(find.text("You're on the latest version."), findsOneWidget);
      expect(controller.manualInFlight, isFalse);
    },
  );

  group('finishInAppUpdate', () {
    test('launches, then flushes tabs, then quits — in that order', () async {
      final calls = <String>[];
      final result = await finishInAppUpdate(
        launchInstaller: () async => calls.add('launch'),
        flushTabs: () async => calls.add('flush'),
        quit: () => calls.add('quit'),
      );
      expect(result, UpdateFinishResult.quitting);
      expect(calls, ['launch', 'flush', 'quit']);
    });

    test('a failed launch keeps the app alive: no flush, no quit', () async {
      final calls = <String>[];
      final result = await finishInAppUpdate(
        launchInstaller: () async => throw Exception('no such file'),
        flushTabs: () async => calls.add('flush'),
        quit: () => calls.add('quit'),
      );
      expect(result, UpdateFinishResult.launchFailed);
      expect(calls, isEmpty);
    });

    test('a failed tab flush still quits (best-effort flush)', () async {
      var quitCalled = false;
      final result = await finishInAppUpdate(
        launchInstaller: () async {},
        flushTabs: () async => throw Exception('hive is gone'),
        quit: () => quitCalled = true,
      );
      expect(result, UpdateFinishResult.quitting);
      expect(quitCalled, isTrue);
    });
  });
}
