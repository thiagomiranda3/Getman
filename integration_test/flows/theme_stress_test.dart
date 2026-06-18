import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Theme display order starting from a value OTHER than the default
/// (BRUTALIST) so the first selection is never the already-selected theme
/// (re-selecting the current value makes the dropdown label ambiguous).
const _themeOrder = [
  'EDITORIAL',
  'ARCANE QUEST',
  'DRACULA',
  'LIQUID GLASS',
  'BRUTALIST',
];

void _expectAppAlive(PatrolTester $) {
  expect(
    $(find.byKey(const ValueKey('url_field')).hitTestable()),
    findsOneWidget,
    reason: 'App must still render the request UI after a theme/mode change.',
  );
}

/// Stress the theming + visual-mode toggles: every theme in light + dark,
/// rapid back-and-forth switching, the LIQUID GLASS reduce-effects toggle
/// (regression guard for the toggle-twice controller-recreate crash), and
/// compact mode. RPG/glass animate forever, so this never uses pumpAndSettle
/// (the helpers use bounded pumps). Any unhandled exception fails the test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('every theme renders in light and dark', ($) async {
    await bootGetman($); // starts on BRUTALIST, light

    for (final name in _themeOrder) {
      await setTheme($, name);
      _expectAppAlive($);
    }

    await toggleSettingRow($, 'DARK MODE'); // now dark
    for (final name in _themeOrder) {
      await setTheme($, name);
      _expectAppAlive($);
    }
  });

  patrolWidgetTest('LIQUID GLASS reduce-effects toggled repeatedly is stable', (
    $,
  ) async {
    await bootGetman($);
    await setTheme($, 'LIQUID GLASS');

    // Toggle REDUCE VISUAL EFFECTS several times in one settings session — this
    // is the path that previously crashed (SingleTicker controller recreate).
    await openSettings($);
    await openSettingsTab($, 'APPEARANCE');
    for (var i = 0; i < 4; i++) {
      await $(
        const ValueKey('reduce_effects_switch'),
      ).tap(settlePolicy: SettlePolicy.noSettle);
      await pumpFrames($);
    }
    await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);

    _expectAppAlive($);
  });

  patrolWidgetTest('rapid glass<->flat theme switching is stable', ($) async {
    final server = await MockServer.start(json: {'glass': true});
    addTearDown(server.close);

    await bootGetman($);
    // Enter the URL on the static default theme (enterText pumpAndSettles,
    // which would hang under an animated theme), then switch to glass + send.
    await enterUrl($, server.url('/glassy'));

    await setTheme($, 'LIQUID GLASS');
    await setTheme($, 'BRUTALIST');
    await setTheme($, 'LIQUID GLASS');
    await setTheme($, 'DRACULA');
    await setTheme($, 'LIQUID GLASS');
    _expectAppAlive($);

    // A request still sends + renders under the glass theme.
    await tapSend($);
    await waitForStatus($, 200);
  });

  patrolWidgetTest('compact + dark + theme renders and sends', ($) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);
    await setTheme($, 'EDITORIAL');
    await toggleSettingRow($, 'DARK MODE');
    await toggleSettingRow($, 'COMPACT MODE');
    _expectAppAlive($);

    await enterUrl($, server.url('/compact'));
    await tapSend($);
    await waitForStatus($, 200);
    expect(server.received, hasLength(1));
  });
}
