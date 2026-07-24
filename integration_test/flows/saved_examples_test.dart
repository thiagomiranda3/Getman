import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Saves the request to a node (links the tab), sends to [server], then
/// captures the response as an example named [exampleName].
Future<void> _captureExample(
  PatrolTester $,
  MockServer server,
  String exampleName,
) async {
  await $(const ValueKey('save_request_button')).tap();
  await enterPromptText($, 'Example Req');
  await $('SAVE').tap();
  await $.pumpAndSettle();

  await sendTo($, server.url('/ex'));
  await waitForStatus($, 200);

  // save_as_example_button only shows once the tab is linked (collectionNodeId)
  // AND a response exists — exactly after the save + send above.
  await $(const ValueKey('save_as_example_button')).tap();
  await $.pumpAndSettle();
  expect($('SAVE AS EXAMPLE'), findsWidgets);
  await enterPromptText($, exampleName);
  await $('SAVE').tap();
  await $.pumpAndSettle();
}

/// M10 saved examples: capture from the response pane, see the inline sub-row,
/// open it as an unlinked tab, rename and delete it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('captures, lists, and opens an example as a tab', ($) async {
    final server = await MockServer.start(json: {'hello': 'example'});
    addTearDown(server.close);

    await bootGetman($);
    await _captureExample($, server, 'Snapshot One');
    expect($('Saved example "Snapshot One"'), findsWidgets);

    // Expand the node to reveal the example sub-row.
    await $(find.byIcon(Icons.keyboard_arrow_right)).first.tap();
    await $.pumpAndSettle();
    expect($('Snapshot One'), findsWidgets);

    // Opening it adds a new (unlinked) tab.
    expect(tabCount($), 1);
    await $('Snapshot One').tap();
    await $.pumpAndSettle();
    expect(tabCount($), 2);
  });

  patrolWidgetTest('renames and deletes an example', ($) async {
    final server = await MockServer.start(json: {'hello': 'example'});
    addTearDown(server.close);

    await bootGetman($);
    await _captureExample($, server, 'First Capture');

    await $(find.byIcon(Icons.keyboard_arrow_right)).first.tap();
    await $.pumpAndSettle();
    expect($('First Capture'), findsWidgets);

    // The example row's menu is the LAST more-vert (the node's is first).
    await $(find.byIcon(Icons.more_vert)).last.tap();
    await $.pumpAndSettle();
    await $('RENAME').tap();
    expect($('RENAME EXAMPLE'), findsWidgets);
    await enterPromptText($, 'Renamed Capture');
    await $('SAVE').tap();
    await $.pumpAndSettle();
    expect($('Renamed Capture'), findsWidgets);

    // Delete it — instant delete with UNDO snackbar (A1).
    await $(find.byIcon(Icons.more_vert)).last.tap();
    await $.pumpAndSettle();
    await $('DELETE').tap();
    await $.pumpAndSettle();
    expect($('Renamed Capture'), findsNothing);
    expect($('UNDO'), findsWidgets);
  });
}
