import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// The redesigned Settings dialog groups controls under four tabs
/// (GENERAL / APPEARANCE / NETWORK / WORKSPACE). Verify the tabs exist and that
/// switching reveals the right controls — on desktop (modal) and at phone width
/// (full-screen page).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('navigates the four settings tabs', ($) async {
    await bootGetman($);
    await openSettings($);

    expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);
    expect($(const ValueKey('settingstab_tab_APPEARANCE')), findsWidgets);
    expect($(const ValueKey('settingstab_tab_NETWORK')), findsWidgets);
    expect($(const ValueKey('settingstab_tab_WORKSPACE')), findsWidgets);

    // GENERAL is the default tab.
    expect($(const ValueKey('history_limit_field')), findsWidgets);

    await openSettingsTab($, 'APPEARANCE');
    expect($(const ValueKey('theme_dropdown')), findsWidgets);

    await openSettingsTab($, 'NETWORK');
    expect($(const ValueKey('receive_timeout_field')), findsWidgets);
    expect($(const ValueKey('cookies_manage_button')), findsWidgets);

    await openSettingsTab($, 'WORKSPACE');
    expect($('CHOOSE FOLDER'), findsWidgets);

    await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
  });

  patrolWidgetTest('switches tabs at phone width (full-screen)', ($) async {
    await bootGetman($, windowSize: const Size(640, 920));
    await openDrawer($);
    await openSettings($);

    // GENERAL is the default pane in the full-screen branch too.
    expect($(const ValueKey('settingstab_tab_NETWORK')), findsWidgets);
    expect($(const ValueKey('history_limit_field')), findsWidgets);

    await openSettingsTab($, 'NETWORK');
    expect($('VERIFY SSL'), findsWidgets);

    await $('CLOSE').tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
  });
}
