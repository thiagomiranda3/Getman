import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// Flows for the Settings dialog: switching the active theme and toggling dark
/// mode both take effect (no app restart).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('switches the active theme', ($) async {
    await bootGetman($);

    await openSettings($);
    await openSettingsTab($, 'APPEARANCE');
    // Default theme is BRUTALIST.
    expect($('BRUTALIST'), findsWidgets);

    await $(const ValueKey('theme_dropdown')).tap();
    await $('EDITORIAL').tap();

    // The dropdown now reflects the new selection.
    expect($('EDITORIAL'), findsWidgets);
  });

  patrolWidgetTest('toggles dark mode', ($) async {
    await bootGetman($);
    await openSettings($);
    await openSettingsTab($, 'APPEARANCE');

    // The DARK MODE row shows a sun/moon icon that flips with the setting.
    final wasDark = $(find.byIcon(Icons.dark_mode)).exists;
    await $('DARK MODE').tap();
    await $.pumpAndSettle();

    if (wasDark) {
      expect($(find.byIcon(Icons.light_mode)), findsWidgets);
    } else {
      expect($(find.byIcon(Icons.dark_mode)), findsWidgets);
    }
  });
}
