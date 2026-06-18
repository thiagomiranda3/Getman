import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

/// Settings that have observable network/behaviour effects: the history limit
/// (trims old entries) and the receive timeout (aborts a slow response).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('history limit trims older entries', ($) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);

    // Cap history at 1.
    await openSettings($);
    await $(const ValueKey('history_limit_field')).enterText('1');
    await $.pumpAndSettle();
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    // Two distinct sends → only the newest survives the trim.
    await sendTo($, server.url('/first-entry'));
    await waitForStatus($, 200);
    await sendTo($, server.url('/second-entry'));
    await waitForStatus($, 200);

    await openSideMenuTab($, 'HISTORY');
    expect($(find.textContaining('second-entry')), findsWidgets);
    expect(
      $(find.textContaining('first-entry')),
      findsNothing,
      reason: 'With limit=1 the older /first-entry must be trimmed.',
    );
  });

  patrolWidgetTest('receive timeout aborts a slow response', ($) async {
    // Server holds the body far longer than the timeout we set.
    final server = await MockServer.start(
      delay: const Duration(seconds: 5),
      json: {'ok': true},
    );
    addTearDown(server.close);

    await bootGetman($);

    await openSettings($);
    await openSettingsTab($, 'NETWORK');
    await $(const ValueKey('receive_timeout_field')).enterText('500');
    await $.pumpAndSettle();
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    await sendTo($, server.url('/slow-body'));

    // Pump ~2.5 s — past the 500 ms timeout + the SEND/CANCEL switcher, but well
    // before the 5 s server delay. The timeout must have fired and released the
    // tab; if the setting were ignored the request would still be in flight.
    await pumpFrames($, frames: 60, ms: 45);
    expect($('SEND'), findsWidgets);
    expect($('CANCEL'), findsNothing);
  });
}
