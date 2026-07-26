import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// E1: Cmd+/ opens the KEYBOARD SHORTCUTS cheat-sheet dialog, the same chord
/// toggles it closed again, and the CLOSE button dismisses it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('Cmd+/ toggles the shortcuts cheat-sheet', ($) async {
    await bootGetman($);

    await sendShortcut($, LogicalKeyboardKey.slash, meta: true);
    expect($('KEYBOARD SHORTCUTS'), findsOneWidget);
    // Catalog sections render.
    expect($('PANELS'), findsWidgets);
    expect($('HELP'), findsWidgets);
    expect($('Show the shortcuts cheat-sheet'), findsOneWidget);

    // Same chord closes it (toggle).
    await sendShortcut($, LogicalKeyboardKey.slash, meta: true);
    expect($('KEYBOARD SHORTCUTS'), findsNothing);
  });

  patrolWidgetTest('CLOSE button dismisses the cheat-sheet', ($) async {
    await bootGetman($);

    await sendShortcut($, LogicalKeyboardKey.slash, meta: true);
    expect($('KEYBOARD SHORTCUTS'), findsOneWidget);

    await $('CLOSE').tap();
    await $.pumpAndSettle();
    expect($('KEYBOARD SHORTCUTS'), findsNothing);
  });
}
