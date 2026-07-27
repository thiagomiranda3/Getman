import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// PR #62: right-clicking a collections tree row opens the same context menu
/// as the trailing ⋮ button — it opens repeatedly, and rename / instant
/// delete (with UNDO) work through it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> saveRequestAs(PatrolTester $, String name) async {
    await $(const ValueKey('save_request_button')).tap();
    await enterPromptText($, name);
    await $('SAVE').tap();
    await $.pumpAndSettle();
  }

  /// Right-clicks the tree row titled [label] with a mouse-kind pointer.
  /// Scoped to the collections tree — the saved name also titles the linked
  /// tab chip, whose own right-click menu (CLOSE / CLOSE OTHERS / …) must
  /// not be hit instead.
  Future<void> rightClickNode(PatrolTester $, String label) async {
    final target = $.tester.getCenter(
      find
          .descendant(
            of: find.byType(CollectionsList),
            matching: find.text(label),
          )
          .hitTestable(),
    );
    final gesture = await $.tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.down(target);
    await $.tester.pump();
    await gesture.up();
    await gesture.removePointer();
    await $.pumpAndSettle();
  }

  patrolWidgetTest('right-click opens the node menu repeatedly', ($) async {
    await bootGetman($);
    await saveRequestAs($, 'CtxNode');

    await rightClickNode($, 'CtxNode');
    expect($('RENAME'), findsOneWidget);
    expect($('DELETE'), findsOneWidget);

    // Dismiss without selecting, then reopen — the menu must come back.
    await sendShortcut($, LogicalKeyboardKey.escape);
    expect($('RENAME'), findsNothing);

    await rightClickNode($, 'CtxNode');
    expect($('RENAME'), findsOneWidget);
    await sendShortcut($, LogicalKeyboardKey.escape);
  });

  patrolWidgetTest('right-click menu renames a node', ($) async {
    await bootGetman($);
    await saveRequestAs($, 'CtxNode');

    await rightClickNode($, 'CtxNode');
    await $('RENAME').tap();
    await enterPromptText($, 'CtxRenamed');
    await $('SAVE').tap();
    await $.pumpAndSettle();

    expect($(find.textContaining('Renamed to')), findsWidgets);
    expect(
      $(
        find.descendant(
          of: find.byType(CollectionsList),
          matching: find.text('CtxRenamed'),
        ),
      ),
      findsOneWidget,
    );
  });

  patrolWidgetTest('right-click menu deletes a node with UNDO', ($) async {
    await bootGetman($);
    await saveRequestAs($, 'CtxDoomed');

    // Instant delete via right-click; the ⋮ row anchor disappearing proves
    // the node is gone (the linked tab chip keeps the name, so don't assert
    // on text absence).
    await rightClickNode($, 'CtxDoomed');
    await $('DELETE').tap();
    await $.pumpAndSettle();
    expect($(find.byIcon(Icons.more_vert)), findsNothing);

    // UNDO restores the node.
    await $('UNDO').tap();
    await $.pumpAndSettle();
    expect($(find.byIcon(Icons.more_vert)), findsOneWidget);
  });
}
