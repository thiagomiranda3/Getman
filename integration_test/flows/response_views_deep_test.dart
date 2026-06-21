import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Deep response-pane coverage: empty placeholder, copy-to-clipboard feedback,
/// empty cookies view, and the compare/diff view.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('shows the empty-response placeholder before any send', (
    $,
  ) async {
    await bootGetman($);
    // Classic (default) empty-response copy.
    expect($('No response yet.'), findsWidgets);
  });

  patrolWidgetTest('copy response reports via snackbar', ($) async {
    final server = await MockServer.start(json: {'copy': 'me'});
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/copyable'));
    await waitForStatus($, 200);

    await $(find.byTooltip('Copy response')).tap();
    await $.pumpAndSettle();
    expect($('Response copied'), findsWidgets);
  });

  patrolWidgetTest('cookies tab is empty when no Set-Cookie', ($) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/no-cookies'));
    await waitForStatus($, 200);

    await openResponseTab($, 'COOKIES');
    expect($('NO COOKIES'), findsWidgets);
  });

  patrolWidgetTest('compares the current response against a saved example', (
    $,
  ) async {
    var n = 0;
    final server = await MockServer.start(
      responder: (request) {
        n++;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"value": $n}');
      },
    );
    addTearDown(server.close);

    await bootGetman($);

    // Link the tab to a node so we can capture an example.
    await $(const ValueKey('save_request_button')).tap();
    await enterPromptText($, 'CmpReq');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    // First response: {"value": 1} → capture as an example.
    await sendTo($, server.url('/cmp'));
    await waitForStatus($, 200);
    await $(const ValueKey('save_as_example_button')).tap();
    await $.pumpAndSettle();
    await enterPromptText($, 'BaseLine');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    // Second response: {"value": 2}.
    await tapSend($);
    for (var i = 0; i < 60 && server.received.length < 2; i++) {
      await $.tester.pump(const Duration(milliseconds: 50));
    }
    expect(server.received.length, 2);
    await pumpFrames($);

    // Compare current (value 2) against the BaseLine example (value 1).
    await $(const ValueKey('compare_response_button')).tap();
    await $.pumpAndSettle();
    await $('BaseLine').tap();
    await $.pumpAndSettle();

    // The diff view shows changed-line gutters.
    expect(
      $(const ValueKey('diff_gutter_added')),
      findsWidgets,
      reason: 'A changed body line should produce an added gutter marker.',
    );
  });
}
