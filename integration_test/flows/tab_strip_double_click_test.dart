import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// PR #62: double-click on the tab strip's EMPTY area opens a new tab
/// (Postman parity), while double-clicks that land on a chip do not.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Two quick primary-button downs at [target] — the raw-Listener detector
  /// counts pointer downs itself, so two back-to-back gestures with no pump
  /// in between land within the double-tap window.
  Future<void> doubleClickAt(PatrolTester $, Offset target) async {
    final g1 = await $.tester.startGesture(target);
    await g1.up();
    final g2 = await $.tester.startGesture(target);
    await g2.up();
    await $.pumpAndSettle();
  }

  patrolWidgetTest('double-click on empty strip area opens a new tab', (
    $,
  ) async {
    await bootGetman($);
    expect(tabCount($), 1);

    // A point halfway between the (only) chip's right edge and the "+"
    // button is inside the strip's scrollable but on no chip.
    final chipRight = $.tester.getBottomRight(allTabs().first);
    final chipCenter = $.tester.getCenter(allTabs().first);
    final addBtn = $.tester.getTopLeft(
      find.byKey(const ValueKey('add_tab_button')),
    );
    final target = Offset((chipRight.dx + addBtn.dx) / 2, chipCenter.dy);

    await doubleClickAt($, target);
    expect(tabCount($), 2);
  });

  patrolWidgetTest('double-click on a tab chip does NOT open a new tab', (
    $,
  ) async {
    await bootGetman($);
    expect(tabCount($), 1);

    await doubleClickAt($, $.tester.getCenter(allTabs().first));
    expect(tabCount($), 1);
  });
}
