import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Flow: a `Set-Cookie` response surfaces in the response COOKIES tab and the
/// cookie jar, and can be deleted from the cookie manager.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('stores a Set-Cookie and deletes it from the manager', (
    $,
  ) async {
    final server = await MockServer.start(
      responder: (request) {
        request.response
          ..statusCode = 200
          ..headers.add(HttpHeaders.setCookieHeader, 'session=abc123; Path=/')
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
      },
    );
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/login'));
    await waitForStatus($, 200);

    // The cookie surfaces in the response COOKIES tab.
    await openResponseTab($, 'COOKIES');
    expect($('session'), findsWidgets);

    // It's in the jar — open the cookie manager from Settings. The COOKIES
    // section is far down the dialog's SingleChildScrollView, so scroll its own
    // ancestor into view (ensureVisible targets the right scrollable; a blind
    // drag can grab the response pane behind the modal).
    await openSettings($);
    await openSettingsTab($, 'NETWORK');
    final manageButton = find.byKey(const ValueKey('cookies_manage_button'));
    await $.tester.ensureVisible(manageButton);
    await $.pumpAndSettle();
    await $(manageButton).tap();
    expect($('session = abc123'), findsOneWidget);

    // Delete it (confirm) — the manager refreshes to empty.
    await $(const ValueKey('delete_cookie_session')).tap();
    await $('DELETE').tap();
    await $.pumpAndSettle();
    expect($('session = abc123'), findsNothing);
  });
}
