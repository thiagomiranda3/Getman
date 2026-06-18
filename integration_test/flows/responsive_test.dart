import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Responsive layout: resize the real window across every breakpoint (and back)
/// and assert the navigation chrome adapts without any layout exception (a
/// RenderFlex overflow during a resize fails the test). Breakpoints:
/// ≤500 compact-phone (tab-switcher chip), ≤700 phone (unified + drawer),
/// ≤900 tablet (drawer), >900 desktop (inline split side-menu).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('adapts nav chrome across breakpoints and back', ($) async {
    await bootGetman($); // desktop (1500x950)

    // Desktop: inline side menu (no hamburger), COLLECTIONS/HISTORY tabs shown.
    expect(
      $(find.byIcon(Icons.menu)),
      findsNothing,
      reason: 'Desktop uses the inline side menu, not a drawer hamburger.',
    );
    expect($(const ValueKey('menutab_tab_COLLECTIONS')), findsWidgets);

    // Tablet: drawer nav → hamburger appears, inline menu tabs gone.
    await resizeWindow($, const Size(860, 900));
    expect($(find.byIcon(Icons.menu)), findsWidgets);

    // Phone: unified request/response tabs + drawer.
    await resizeWindow($, const Size(660, 900));
    expect($(find.byIcon(Icons.menu)), findsWidgets);
    expect($('RESPONSE'), findsWidgets); // unified panel adds a RESPONSE tab

    // Compact phone: tab-switcher chip layout.
    await resizeWindow($, const Size(460, 860));
    expect($(find.byIcon(Icons.menu)), findsWidgets);

    // Back up to phone then desktop — chrome restores cleanly.
    await resizeWindow($, const Size(660, 900));
    expect($(find.byIcon(Icons.menu)), findsWidgets);

    await resizeWindow($, kE2eWindowSize);
    expect($(find.byIcon(Icons.menu)), findsNothing);
    expect($(const ValueKey('menutab_tab_COLLECTIONS')), findsWidgets);
  });

  patrolWidgetTest('drawer side menu opens on a narrow window', ($) async {
    await bootGetman($, windowSize: const Size(660, 900));

    await openDrawer($);
    // The side menu (COLLECTIONS / HISTORY tabs) lives inside the drawer.
    expect($(const ValueKey('menutab_tab_COLLECTIONS')), findsWidgets);
    expect($(const ValueKey('menutab_tab_HISTORY')), findsWidgets);
  });

  patrolWidgetTest('can send a request at phone width (unified panel)', (
    $,
  ) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($, windowSize: const Size(640, 920));

    await enterUrl($, server.url('/phone-send'));
    await tapSend($);
    // The unified panel keeps the status ribbon visible above the tab strip
    // and auto-focuses RESPONSE on arrival.
    await waitForStatus($, 200);

    expect(server.received, hasLength(1));
    expect(server.received.single.uri.path, '/phone-send');
  });

  patrolWidgetTest('resizing while a dialog is open does not break', ($) async {
    await bootGetman($);
    await openSettings($);
    expect($('SETTINGS'), findsWidgets);
    expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);
    expect($(const ValueKey('history_limit_field')), findsWidgets);

    // Shrink to phone — the dialog should become full-screen, not overflow.
    await resizeWindow($, const Size(620, 900));
    expect($('SETTINGS'), findsWidgets);
    // Full-screen dialog keeps the tab strip + GENERAL pane (no overflow).
    expect($(const ValueKey('settingstab_tab_GENERAL')), findsWidgets);

    // Grow back to desktop — still intact.
    await resizeWindow($, kE2eWindowSize);
    expect($('SETTINGS'), findsWidgets);
    await $('CLOSE').tap();
    await $.pumpAndSettle();
  });
}
