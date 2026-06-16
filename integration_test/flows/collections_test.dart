import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// Flows for the collections tree: saving the active request as a node,
/// creating a folder, and deleting a node through its context menu. Tree node
/// labels render verbatim (as typed — no upper-casing).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('saves a request and creates a folder', ($) async {
    await bootGetman($);

    // Save the current request to a new collection node. (The name shows in
    // both the tree and the now-linked tab title, so allow >1 match.)
    await $(const ValueKey('save_request_button')).tap();
    await enterPromptText($, 'Req One');
    await $('SAVE').tap();
    expect($('Req One'), findsWidgets);

    // Create a top-level folder.
    await $(const ValueKey('new_folder_button')).tap();
    await enterPromptText($, 'Folder One');
    await $('CREATE').tap();
    expect($('Folder One'), findsWidgets);
  });

  patrolWidgetTest('deletes a saved request via its menu', ($) async {
    await bootGetman($);

    await $(const ValueKey('save_request_button')).tap();
    await enterPromptText($, 'Temp');
    await $('SAVE').tap();
    expect($('Temp'), findsWidgets);

    // Open the (only) node's context menu and delete it (confirm). The node row
    // is the sole `more_vert` source in the tree, so it being gone afterwards
    // proves the node was removed.
    await $(find.byIcon(Icons.more_vert)).tap();
    await $('DELETE').tap(); // menu item
    await $('DELETE').tap(); // confirm dialog
    await $.pumpAndSettle();

    expect($(find.byIcon(Icons.more_vert)), findsNothing);
  });
}
