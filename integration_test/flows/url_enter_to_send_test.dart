import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// PR #62: submitting the URL field (Enter) sends the request, and the field
/// re-focuses afterwards so a second Enter re-sends without re-clicking.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('Enter in the URL field sends the request', ($) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);
    await enterUrl($, server.url('/enter-send'));

    // patrol's enterText unfocuses the field and tears down the test IME
    // connection when it finishes — re-register the test input, then tap the
    // field so EditableText re-attaches a client the "done" action can reach.
    $.tester.testTextInput.register();
    addTearDown($.tester.testTextInput.unregister);
    await $(find.byKey(const ValueKey('url_field')).hitTestable()).tap();
    await $.tester.pump();

    // The IME "done" action is what a physical Enter produces on desktop.
    await $.tester.testTextInput.receiveAction(TextInputAction.done);
    await $.tester.pump();
    await waitForStatus($, 200);
    expect(server.received, isNotEmpty);

    // The field re-focuses after submit, so a plain Enter can re-send.
    final urlField = $.tester.widget<TextField>(
      find.byKey(const ValueKey('url_field')).hitTestable(),
    );
    expect(
      urlField.focusNode!.hasFocus,
      isTrue,
      reason: 'URL field must re-focus after submit so Enter re-sends',
    );

    // Second round-trip: tap re-attaches the test IME client (the "done"
    // action tore the connection down), then submit again. The status chip
    // already shows 200, so prove the re-send via the server's request count.
    final firstCount = server.received.length;
    await $(find.byKey(const ValueKey('url_field')).hitTestable()).tap();
    await $.tester.pump();
    await $.tester.testTextInput.receiveAction(TextInputAction.done);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (server.received.length <= firstCount &&
        DateTime.now().isBefore(deadline)) {
      await $.tester.pump(const Duration(milliseconds: 100));
    }
    expect(server.received.length, greaterThan(firstCount));
  });
}
