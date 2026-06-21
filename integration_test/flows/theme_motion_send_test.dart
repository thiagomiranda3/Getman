import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Motion-during-send across the "loud" themes. Recent work added per-theme
/// reactive motion that mounts WHILE a request is in flight — the in-flight
/// panel frame (marching bar / circuit trace / breathe / HUD scan), the
/// content-swap transition, and the SEND-affordance. This flow drives a real
/// send under each loud theme and asserts the app survives the in-flight motion
/// (no crash / no overflow — patrolWidgetTest fails on any unhandled exception)
/// AND the response renders (the 200 STATUS chip). It is the E2E guard for the
/// in-flight-frame dispose fix + the per-status reaction work.
///
/// Themes animate forever, so this never uses pumpAndSettle (the helpers use
/// bounded pumps). The URL is entered on the boot-default (calm CLASSIC) theme
/// first, because enterText settles and would hang under an animated theme.
const _loudThemes = ['ARCANE QUEST', 'LIQUID GLASS', 'AURIS', 'DRACULA'];

void _expectAppAlive(PatrolTester $) {
  expect(
    $(find.byKey(const ValueKey('url_field')).hitTestable()),
    findsOneWidget,
    reason: 'App must still render the request UI after a themed send.',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final theme in _loudThemes) {
    patrolWidgetTest('$theme: send under in-flight motion renders 200', (
      $,
    ) async {
      final server = await MockServer.start(json: {'theme': theme});
      addTearDown(server.close);

      await bootGetman($);
      // Enter the URL on the calm default theme (enterText settles), THEN
      // switch to the animated loud theme and send.
      await enterUrl($, server.url('/motion'));
      await setTheme($, theme);

      await tapSend($);
      await waitForStatus($, 200);
      _expectAppAlive($);
      expect(server.received, hasLength(1));
    });
  }

  patrolWidgetTest(
    'reduce-effects loud theme still sends + renders (static degradation)',
    ($) async {
      final server = await MockServer.start(json: {'reduced': true});
      addTearDown(server.close);

      await bootGetman($);
      await enterUrl($, server.url('/reduced'));
      await setTheme($, 'ARCANE QUEST');

      // Turn REDUCE VISUAL EFFECTS on — the in-flight frame must degrade to
      // identity, and a send must still complete and render.
      await openSettings($);
      await openSettingsTab($, 'APPEARANCE');
      await $(
        const ValueKey('reduce_effects_switch'),
      ).tap(settlePolicy: SettlePolicy.noSettle);
      await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
      await pumpFrames($);

      await tapSend($);
      await waitForStatus($, 200);
      _expectAppAlive($);
    },
  );
}
