import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Odds and ends not covered elsewhere: reordering tabs by drag and clearing
/// the whole cookie jar from Settings.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('reorders tabs by dragging', ($) async {
    await bootGetman($); // tab 0 = seed (httpbin)
    await newTab($);
    await enterUrl($, 'https://aaa.test/x');
    await newTab($);
    await enterUrl($, 'https://ccc.test/z'); // tab 2, active
    expect(tabCount($), 3);

    // Drag the last tab (ccc) onto the first slot.
    final from = $.tester.getCenter(allTabs().at(2));
    final to = $.tester.getCenter(allTabs().at(0));
    final gesture = await $.tester.startGesture(from);
    await $.tester.pump(const Duration(milliseconds: 80));
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
      await $.tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await $.pumpAndSettle();

    // Tab now at position 0 should be the one that was dragged there (ccc).
    await sendShortcut($, LogicalKeyboardKey.digit1, meta: true);
    expect(activeUrl($), contains('ccc.test'));
  });

  patrolWidgetTest('clears the whole cookie jar from settings', ($) async {
    final server = await MockServer.start(
      responder: (request) {
        request.response
          ..statusCode = 200
          ..headers.add(HttpHeaders.setCookieHeader, 'sid=abc; Path=/')
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
      },
    );
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/set'));
    await waitForStatus($, 200);

    // Clear all cookies from Settings. The COOKIES row is far down the dialog's
    // scroll view, so bring its CLEAR button into view first.
    await openSettings($);
    await openSettingsTab($, 'NETWORK');
    final clearButton = find.text('CLEAR');
    await $.tester.ensureVisible(clearButton);
    await $.pumpAndSettle();
    await $(clearButton).tap();
    expect($('Clear cookies?'), findsWidgets); // confirm dialog
    // The settings-row CLEAR is still mounted behind the dialog, so the
    // confirm button is the LAST 'CLEAR'.
    await $('CLEAR').last.tap();
    await $.pumpAndSettle();
    expect($('Cookie jar cleared'), findsWidgets);

    // The jar is now empty in the manager.
    final manage = find.byKey(const ValueKey('cookies_manage_button'));
    await $.tester.ensureVisible(manage);
    await $.pumpAndSettle();
    await $(manage).tap();
    await $.pumpAndSettle();
    expect($(find.textContaining('sid = abc')), findsNothing);
  });
}
