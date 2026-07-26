import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// Deep tab-strip coverage: the right-click context menu (DUPLICATE / CLOSE
/// OTHERS / CLOSE TO THE RIGHT / COPY URL) and the dirty-star (`*`) indicator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('duplicate via context menu adds a tab', ($) async {
    await bootGetman($);
    expect(tabCount($), 1);

    await openTabMenu($, 0);
    await $('DUPLICATE').tap();
    await $.pumpAndSettle();

    expect(tabCount($), 2);
    expect($('Tab duplicated'), findsWidgets);
  });

  patrolWidgetTest('close others keeps only the targeted tab', ($) async {
    await bootGetman($);
    await newTab($);
    await newTab($);
    expect(tabCount($), 3);

    // The first-run seed tab (httpbin URL, unlinked) counts as unsaved work,
    // so the bulk close is gated behind the UNSAVED CHANGES confirm (D6).
    await openTabMenu($, 1);
    await $('CLOSE OTHERS').tap();
    await $.pumpAndSettle();
    expect($('UNSAVED CHANGES'), findsOneWidget);
    await $('CLOSE ANYWAY').tap();
    await $.pumpAndSettle();

    expect(tabCount($), 1);
  });

  patrolWidgetTest('close others with no unsaved work skips the confirm', (
    $,
  ) async {
    await bootGetman($);
    await enterUrl($, ''); // blank the seed URL so every tab is pristine
    await newTab($);
    await newTab($);
    expect(tabCount($), 3);

    await openTabMenu($, 1);
    await $('CLOSE OTHERS').tap();
    await $.pumpAndSettle();

    expect($('UNSAVED CHANGES'), findsNothing);
    expect(tabCount($), 1);
  });

  patrolWidgetTest('close to the right drops trailing tabs', ($) async {
    await bootGetman($);
    await newTab($);
    await newTab($);
    expect(tabCount($), 3);

    await openTabMenu($, 0);
    await $('CLOSE TO THE RIGHT').tap();
    await $.pumpAndSettle();

    expect(tabCount($), 1);
  });

  patrolWidgetTest('copy URL reports via snackbar', ($) async {
    await bootGetman($);

    await openTabMenu($, 0);
    await $('COPY URL').tap();
    await $.pumpAndSettle();

    expect($('URL copied'), findsWidgets);
  });

  patrolWidgetTest('dirty star appears only after editing a saved tab', (
    $,
  ) async {
    await bootGetman($);

    // Save the request → tab links to the node and is clean (no `*`).
    await $(const ValueKey('save_request_button')).tap();
    await enterPromptText($, 'Clean Req');
    await $('SAVE').tap();
    await $.pumpAndSettle();
    expect(
      $('*'),
      findsNothing,
      reason: 'A just-saved tab must equal its node config (not dirty).',
    );

    // Edit the URL → now diverges from the saved node → dirty star shows.
    await enterUrl($, 'https://httpbin.org/anything/changed');
    await $.pumpAndSettle();
    expect($('*'), findsWidgets);
  });
}
