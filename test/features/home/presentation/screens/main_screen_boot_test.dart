// Full-DI boot harness for the REAL MainScreen widget — supersedes the
// "pumping the real MainScreen is not feasible" note in
// main_screen_actions_test.dart (which still covers the Action-callback
// logic in isolation). The recipe that makes it feasible:
//
//   1. Boot the real DI container per test —
//      `di.init(storageDirectoryOverride: <fresh temp dir>)`, exactly like
//      integration_test/support/app_harness.dart — but wrapped in
//      `tester.runAsync` so Hive's real file IO completes despite the widget
//      test's FakeAsync zone.
//   2. Pump the real `MyApp` from lib/main.dart (full repository/bloc provider
//      tree, go_router, root Shortcuts map), which routes to MainScreen.
//   3. NEVER `pumpAndSettle` — theme ambient tickers may animate forever.
//      All pumping is bounded: `_pumpBounded` alternates a real-event-loop
//      yield (`runAsync` + tiny delay, so Hive IO events land) with fixed
//      `pump` frames (so the fake zone's queued microtasks/bloc emissions
//      flush into the tree).
//
// Two boot-time landmines are defused the same way the E2E harness does:
// the startup update check is disabled on the freshly-seeded SettingsBloc
// (otherwise UpdateGate hits GitHub), and PackageInfo gets mock values
// (UpdateGate's unawaited PackageInfo.fromPlatform() would otherwise throw
// MissingPluginException into the test zone). A fresh profile boots the
// default CLASSIC theme, which is calm by design (identity scaffoldBackground,
// no ambient ticker), so bounded pumps leave no runaway animations behind.
//
// Shortcuts note: under `flutter test`, defaultTargetPlatform is android, so
// the root Shortcuts map is built with Ctrl (not Meta) as the primary
// modifier — keyboard tests below therefore send Ctrl chords.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/features/home/presentation/widgets/empty_tabs_placeholder.dart';
import 'package:getman/features/home/presentation/widgets/request_tab_chip.dart';
import 'package:getman/features/home/presentation/widgets/side_menu.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/main.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Desktop-sized test surface (mirrors integration_test's kE2eWindowSize):
/// inline side menu + full tab strip.
const Size _desktopSize = Size(1500, 950);

/// At or below the 900 px tablet threshold the shell switches to drawer
/// navigation (see lib/core/theme/responsive.dart, kTabletMax).
const Size _drawerSize = Size(860, 900);

/// Bounded stand-in for pumpAndSettle: each round first yields to the REAL
/// event loop (so Hive file-IO futures started by the blocs complete), then
/// pumps a fixed-duration frame (so the fake zone's queued microtasks and the
/// resulting rebuilds flush).
Future<void> _pumpBounded(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Awaits [future] while keeping BOTH event loops moving. A future whose
/// continuations were queued in the widget test's FakeAsync zone (e.g. a Hive
/// write issued by a bloc created inside pumpWidget) can only complete when
/// `pump` flushes that zone's microtasks — awaiting it inside
/// `tester.runAsync` deadlocks (runAsync blocks the test without pumping;
/// this is exactly how the first draft of this harness hung). So: start the
/// future in the test zone, then alternate real-event-loop yields (for the
/// underlying file IO) with pumps (for the fake-zone continuations) until it
/// resolves.
Future<T> _awaitWithPumps<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  // Side-listener only — errors are swallowed here because the caller
  // re-awaits [future] at the end, where a failure still surfaces.
  unawaited(
    future.then<void>((_) => done = true, onError: (Object _) => done = true),
  );
  var rounds = 0;
  while (!done && rounds < 400) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    rounds++;
  }
  if (!done) {
    fail('_awaitWithPumps: future did not resolve within $rounds rounds');
  }
  return future;
}

/// Boots the REAL app (fresh temp-dir profile → real DI → real MyApp) sized
/// at [window], and registers full teardown (unmount, DI reset, temp-dir
/// delete, view reset) via addTearDown so it runs even on failure.
Future<void> _bootGetman(
  WidgetTester tester, {
  Size window = _desktopSize,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final tempDir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('getman_main_screen_boot'),
  ))!;
  addTearDown(() async {
    // Unmount first so every bloc/ticker/timer disposes with the tree, then
    // drain any in-flight fake-zone Hive writes before di.reset() calls
    // Hive.close() (which awaits them — see _awaitWithPumps).
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBounded(tester, rounds: 4);
    await _awaitWithPumps(tester, di.reset());
    if (tempDir.existsSync()) {
      await tester.runAsync(() => tempDir.delete(recursive: true));
    }
  });

  final settings = (await tester.runAsync(
    () => di.init(storageDirectoryOverride: tempDir.path),
  ))!;

  // Mirror integration_test/support/app_harness.dart's
  // disableStartupUpdateCheck: a fresh profile defaults
  // checkForUpdatesOnStartup=true and UpdateGate would call GitHub.
  await tester.runAsync(() async {
    final settingsBloc = di.sl<SettingsBloc>();
    if (settingsBloc.state.settings.checkForUpdatesOnStartup) {
      settingsBloc.add(const UpdateCheckForUpdatesOnStartup(enabled: false));
      await settingsBloc.stream.firstWhere(
        (s) => !s.settings.checkForUpdatesOnStartup,
      );
    }
  });

  await tester.pumpWidget(MyApp(initialSettings: settings));
  await _pumpBounded(tester);
}

/// The tab ids currently shown in the strip, in strip order.
List<String> _chipTabIds(WidgetTester tester) => tester
    .widgetList<RequestTabChip>(find.byType(RequestTabChip))
    .map((chip) => chip.tabId)
    .toList();

/// Sends a Ctrl (+ optional Shift) chord — the primary modifier under
/// `flutter test` (defaultTargetPlatform == android → useMeta:false).
Future<void> _pressCtrl(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  setUpAll(() {
    // UpdateGate fires an unawaited PackageInfo.fromPlatform() in initState;
    // without mock values the missing platform channel throws into the zone.
    PackageInfo.setMockInitialValues(
      appName: 'getman',
      packageName: 'com.getman.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('MainScreen full boot', () {
    testWidgets('boots the desktop shell with the seeded first-run tab', (
      tester,
    ) async {
      await _bootGetman(tester);

      // Tab strip is up with the "+" button and exactly the seeded tab.
      expect(find.byKey(const ValueKey('add_tab_button')), findsOneWidget);
      expect(find.byType(RequestTabChip), findsOneWidget);

      // The seeded tab's request editor rendered (URL bar present).
      expect(find.byKey(const ValueKey('url_field')), findsOneWidget);

      // Desktop split shell: side menu is inline, no drawer menu button.
      expect(find.byType(SideMenu), findsOneWidget);
      expect(find.byKey(const ValueKey('new_folder_button')), findsOneWidget);
      expect(find.byTooltip('OPEN MENU'), findsNothing);
    });

    testWidgets('the + button adds a pristine tab and its close button '
        'removes it without a confirm dialog', (tester) async {
      await _bootGetman(tester);
      final seededIds = _chipTabIds(tester);
      expect(seededIds, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('add_tab_button')));
      await _pumpBounded(tester);
      final afterAdd = _chipTabIds(tester);
      expect(afterAdd, hasLength(2));

      // The chip close first awaits the confirmation callback, then plays a
      // size-collapse animation before dispatching RemoveTab — needs a full
      // bounded settle, not just a frame or two.
      final newId = afterAdd.firstWhere((id) => !seededIds.contains(id));
      await tester.tap(find.byKey(ValueKey('tab_close_$newId')));
      await _pumpBounded(tester, rounds: 12);

      // Pristine tab: closed instantly, no UNSAVED CHANGES confirmation.
      expect(find.text('UNSAVED CHANGES'), findsNothing);
      expect(_chipTabIds(tester), seededIds);
    });

    testWidgets('closing the dirty seeded tab asks for confirmation and '
        'CLOSE ANYWAY leads to the empty placeholder', (tester) async {
      await _bootGetman(tester);
      final seededId = _chipTabIds(tester).single;

      // The seeded tab carries a URL, so it differs from a pristine config —
      // TabDirtyChecker flags it dirty and the close must confirm first.
      await tester.tap(find.byKey(ValueKey('tab_close_$seededId')));
      await _pumpBounded(tester);
      expect(find.text('UNSAVED CHANGES'), findsOneWidget);

      // Dialog pop + chip collapse animation + RemoveTab persistence + the
      // AnimatedSwitcher fade to the placeholder — settle generously.
      await tester.tap(find.text('CLOSE ANYWAY'));
      await _pumpBounded(tester, rounds: 12);

      expect(find.byType(RequestTabChip), findsNothing);
      expect(find.byType(EmptyTabsPlaceholder), findsOneWidget);
      expect(find.text('NO OPEN TABS'), findsOneWidget);

      // The placeholder's NEW REQUEST button opens a fresh tab.
      await tester.tap(find.text('NEW REQUEST'));
      await _pumpBounded(tester);
      expect(find.byType(RequestTabChip), findsOneWidget);
      expect(find.byType(EmptyTabsPlaceholder), findsNothing);
    });

    testWidgets('below the tablet breakpoint the shell switches to drawer '
        'navigation', (tester) async {
      await _bootGetman(tester, window: _drawerSize);

      // Drawer shell: menu button in the strip, side menu NOT inline.
      final menuButton = find.byTooltip('OPEN MENU');
      expect(menuButton, findsOneWidget);
      expect(find.byType(SideMenu), findsNothing);

      await tester.tap(menuButton);
      await _pumpBounded(tester, rounds: 4);
      expect(find.byType(SideMenu), findsOneWidget);
      expect(find.byKey(const ValueKey('new_folder_button')), findsOneWidget);
    });

    testWidgets('Ctrl+N opens a new tab and Ctrl+W closes it again '
        '(root Shortcuts → MainScreen Actions)', (tester) async {
      await _bootGetman(tester);
      expect(find.byType(RequestTabChip), findsOneWidget);

      await _pressCtrl(tester, LogicalKeyboardKey.keyN);
      await _pumpBounded(tester, rounds: 4);
      expect(find.byType(RequestTabChip), findsNWidgets(2));

      // The new tab is active and pristine — Ctrl+W closes it instantly.
      await _pressCtrl(tester, LogicalKeyboardKey.keyW);
      await _pumpBounded(tester);
      expect(find.text('UNSAVED CHANGES'), findsNothing);
      expect(find.byType(RequestTabChip), findsOneWidget);

      // With a closed tab on the stack, Ctrl+Shift+T reopens it (the other
      // branch of MainScreen's ReopenClosedTabIntent callback).
      await _pressCtrl(tester, LogicalKeyboardKey.keyT, shift: true);
      await _pumpBounded(tester);
      expect(find.byType(RequestTabChip), findsNWidgets(2));
      expect(find.text('Nothing to reopen'), findsNothing);
    });

    testWidgets('Ctrl+Shift+T with an empty reopen stack shows the '
        "'Nothing to reopen' snackbar", (tester) async {
      await _bootGetman(tester);

      await _pressCtrl(tester, LogicalKeyboardKey.keyT, shift: true);
      await _pumpBounded(tester, rounds: 2);
      expect(find.text('Nothing to reopen'), findsOneWidget);

      // No tab was reopened.
      expect(find.byType(RequestTabChip), findsOneWidget);

      // Let the snackbar expire so no Timer outlives the test. The dismiss
      // timer is only armed once the entrance animation completes ON A FRAME,
      // so a single long pump is not enough — pump a series of frames
      // covering entrance + 2s display + exit + removal rebuild.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Nothing to reopen'), findsNothing);
    });
  });
}
