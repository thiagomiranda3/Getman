import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show TextButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// D3: history management — day group headers, the hover-only per-entry
/// delete with UNDO, clear-all behind a confirm with UNDO, and the first-run
/// empty state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('empty state shows and CLEAR ALL is disabled', ($) async {
    await bootGetman($);

    await openSideMenuTab($, 'HISTORY');
    expect($('NO REQUESTS SENT YET'), findsOneWidget);

    final clearAll = $.tester.widget<TextButton>(
      find.byKey(const ValueKey('history_clear_all')),
    );
    expect(clearAll.onPressed, isNull);
  });

  patrolWidgetTest('hover reveals delete; UNDO restores the entry', (
    $,
  ) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/keep-me'));
    await waitForStatus($, 200);
    await enterUrl($, server.url('/delete-me'));
    await tapSend($);
    await waitForStatus($, 200);

    // A fresh empty tab so the only on-screen URL matches are history rows
    // (the active tab's URL field is an EditableText that text finders hit).
    await newTab($);
    await openSideMenuTab($, 'HISTORY');
    expect($(const ValueKey('history_group_TODAY')), findsOneWidget);
    expect($(find.textContaining('/delete-me')), findsWidgets);

    // The ✕ is hover-only: park a mouse pointer over the row first.
    final gesture = await $.tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      $.tester.getCenter(find.textContaining('/delete-me').hitTestable()),
    );
    await $.tester.pump();

    await $(find.byTooltip('Delete entry').hitTestable()).tap();
    await $.pumpAndSettle();
    expect($(find.textContaining('/delete-me')), findsNothing);
    expect($('History entry deleted'), findsOneWidget);

    await $('UNDO').tap();
    await $.pumpAndSettle();
    expect($(find.textContaining('/delete-me')), findsWidgets);
    expect($(find.textContaining('/keep-me')), findsWidgets);
  });

  patrolWidgetTest('CLEAR ALL confirms, empties, and UNDO restores', (
    $,
  ) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url('/wipe-one'));
    await waitForStatus($, 200);
    await enterUrl($, server.url('/wipe-two'));
    await tapSend($);
    await waitForStatus($, 200);

    // Fresh empty tab: keep the URL field from matching history-row finders.
    await newTab($);
    await openSideMenuTab($, 'HISTORY');
    await $(const ValueKey('history_clear_all')).tap();
    await $.pumpAndSettle();
    expect($('CLEAR ALL HISTORY'), findsOneWidget);

    await $('CLEAR').tap();
    await $.pumpAndSettle();
    expect($(find.textContaining('/wipe-one')), findsNothing);
    expect($('NO REQUESTS SENT YET'), findsOneWidget);
    expect($('History cleared'), findsOneWidget);

    await $('UNDO').tap();
    await $.pumpAndSettle();
    expect($(find.textContaining('/wipe-one')), findsWidgets);
    expect($(find.textContaining('/wipe-two')), findsWidgets);
    expect($(const ValueKey('history_group_TODAY')), findsOneWidget);
  });
}
