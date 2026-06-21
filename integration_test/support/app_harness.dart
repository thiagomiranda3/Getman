import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/main.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:patrol_finders/patrol_finders.dart';

/// Default window size the E2E flows boot at — a real desktop size (inline side
/// menu + split-pane request/response, so the `reqtab_*` / `resptab_*` /
/// `menutab_*` anchors exist and the side-menu buttons show). Wide enough that
/// the URL bar keeps its inline actions (Generate-code / Save) instead of
/// collapsing into the overflow menu.
const Size kE2eWindowSize = Size(1500, 950);

/// Channel into the macOS Runner that resizes the real `NSWindow`
/// (see `macos/Runner/MainFlutterWindow.swift`). Test-only.
const MethodChannel _testWindowChannel = MethodChannel('getman/test_window');

/// Watch mode is on whenever a slow-motion delay is requested
/// (`--dart-define=E2E_SLOW_MS=<ms>`). A getter (not a const) so the analyzer
/// doesn't fold the default 0 into dead-code warnings.
bool get _watchMode => const int.fromEnvironment('E2E_SLOW_MS') > 0;

/// Logical width of the current test view.
double _logicalWidth(PatrolTester $) =>
    $.tester.view.physicalSize.width / $.tester.view.devicePixelRatio;

/// Sets the **real** macOS window to [size] (logical points, at the native
/// device pixel ratio) and waits for the new metrics to land. This actually
/// resizes the window, so the app lays out at [size] and responsive breakpoints
/// fire for real — unlike scaling via `devicePixelRatio`. Safe to call mid-flow
/// to exercise responsive behaviour:
/// ```dart
/// await resizeWindow($, const Size(560, 900)); // phone-ish → unified panel
/// ```
/// No-op off macOS (the channel isn't registered).
Future<void> resizeWindow(PatrolTester $, Size size) async {
  try {
    await _testWindowChannel.invokeMethod<void>('setContentSize', {
      'width': size.width,
      'height': size.height,
    });
  } on MissingPluginException {
    return;
  }
  // The native resize lands asynchronously as a view-metrics change; pump until
  // the logical width matches (or give up after ~1s and let the test fail).
  for (var i = 0; i < 60; i++) {
    await $.tester.pump(const Duration(milliseconds: 16));
    if ((_logicalWidth($) - size.width).abs() < 2) break;
  }
  await $.pumpAndSettle();
}

/// Boots the **real** Getman app for an E2E flow and pumps it until settled.
///
/// Isolation: each boot points Hive at a fresh throwaway temp directory (via
/// [di.init]'s `storageDirectoryOverride`), so a test run never reads or wipes
/// the developer's real saved collections/history/settings. Cleanup is
/// registered with [addTearDown], so it runs after the test even on failure:
/// the DI container is reset, all Hive boxes are closed, and the temp dir is
/// deleted.
///
/// The window is resized to [kE2eWindowSize] at native scale so flows run in
/// the desktop layout while staying fully visible (you can watch them — see the
/// README "Watch it run"). Pass [windowSize] to boot at another size.
///
/// Call once at the start of a flow:
/// ```dart
/// patrolWidgetTest('my flow', ($) async {
///   await bootGetman($);
///   // ... drive the app via `$` ...
/// });
/// ```
Future<void> bootGetman(
  PatrolTester $, {
  Size windowSize = kE2eWindowSize,
}) async {
  // The app bundles its Google Fonts; forbid runtime fetching so a test never
  // hits the network for a font (matches main.dart).
  GoogleFonts.config.allowRuntimeFetching = false;

  // Watch mode: render every frame so the on-screen window shows the app
  // animating as it's driven (the suite is visible either way; this just makes
  // animations smooth).
  final binding = WidgetsBinding.instance;
  if (_watchMode && binding is LiveTestWidgetsFlutterBinding) {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  }

  final tempDir = await Directory.systemTemp.createTemp('getman_e2e');
  addTearDown(() async {
    await di.reset();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  final settings = await di.init(storageDirectoryOverride: tempDir.path);
  await disableStartupUpdateCheck();

  await $.pumpWidgetAndSettle(MyApp(initialSettings: settings));
  await resizeWindow($, windowSize);
}

/// Disables the startup auto-update check on the freshly-booted SettingsBloc.
///
/// Otherwise the real GitHub `releases/latest` check finds a newer published
/// version than the test bundle's and opens the UpdateDialog on boot — its
/// modal barrier absorbs every hit-test, so `url_field` (and everything else)
/// is in the tree but **not hit-testable** and all interaction flows time
/// out. A fresh E2E profile seeds from an empty box, so the setting defaults
/// to `true`; flip it on the SettingsBloc (the gate reads it from there)
/// before `pumpWidget` mounts the gate. Also keeps the suite hermetic.
///
/// [bootGetman] calls this for you. Flows that boot the app **manually** (e.g.
/// restart-persistence flows that call `di.init` + pump `MyApp` themselves)
/// must call it after each `di.init`, before pumping `MyApp`.
Future<void> disableStartupUpdateCheck() async {
  final settingsBloc = di.sl<SettingsBloc>()
    ..add(const UpdateCheckForUpdatesOnStartup(enabled: false));
  await settingsBloc.stream.firstWhere(
    (s) => !s.settings.checkForUpdatesOnStartup,
  );
}
