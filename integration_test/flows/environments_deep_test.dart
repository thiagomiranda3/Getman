import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';

bool _valueObscured(PatrolTester $, String key) {
  final editable = $.tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.obscureText;
}

Future<void> _openManageEnvironments(PatrolTester $) async {
  await openEnvironmentSelector($);
  await $('Manage environments…').tap();
  await $.pumpAndSettle();
}

Future<void> _createEnvironment(PatrolTester $, String name) async {
  await $(const ValueKey('new_environment_button')).tap();
  await enterPromptText($, name);
  await $('CREATE').tap();
  await $.pumpAndSettle();
}

/// Deep environments coverage: secret variables (lock + reveal), deleting the
/// active environment (falls back to "No Environment"), dynamic variables
/// resolved at send time, and the Cmd+E quick switcher.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('a variable can be marked secret and revealed', ($) async {
    await bootGetman($);
    await _openManageEnvironments($);
    await _createEnvironment($, 'Secrets');

    await $(const ValueKey('env_var_key_0')).enterText('token');
    await $(const ValueKey('env_var_val_0')).enterText('sk-live-123');
    await $.pumpAndSettle();

    // Mark the first row secret (lock toggle). Its value field then obscures.
    await $(find.byIcon(Icons.lock_open_outlined)).first.tap();
    await $.pumpAndSettle();
    expect(_valueObscured($, 'env_var_val_0'), isTrue);

    // Reveal it again.
    await $(find.byIcon(Icons.visibility)).first.tap();
    await $.pumpAndSettle();
    expect(_valueObscured($, 'env_var_val_0'), isFalse);
  });

  patrolWidgetTest('deleting the active environment falls back to none', (
    $,
  ) async {
    await bootGetman($);
    await _openManageEnvironments($);
    await _createEnvironment($, 'Throwaway');
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    // Activate it.
    await openEnvironmentSelector($);
    await $('Throwaway').tap();
    await $.pumpAndSettle();

    // Delete it from the list (confirm).
    await _openManageEnvironments($);
    await $(find.byIcon(Icons.delete_outline)).tap();
    await $('DELETE').tap();
    await $.pumpAndSettle();
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    // The selector must have reverted to "No Environment".
    await openEnvironmentSelector($);
    expect($('No Environment'), findsWidgets);
  });

  patrolWidgetTest('dynamic variables resolve at send time (no env needed)', (
    $,
  ) async {
    final server = await MockServer.start(json: {'ok': true});
    addTearDown(server.close);

    await bootGetman($);
    await sendTo($, server.url(r'/echo?id={{$guid}}&n={{$randomInt}}'));
    await waitForStatus($, 200);

    final q = server.received.single.uri.queryParameters;
    expect(
      q['id'],
      matches(RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$')),
      reason: '{{\$guid}} must resolve to a UUID, got: ${q['id']}',
    );
    expect(
      int.tryParse(q['n'] ?? ''),
      isNotNull,
      reason: '{{\$randomInt}} must resolve to an integer, got: ${q['n']}',
    );
  });

  patrolWidgetTest('Cmd+E quick switcher activates an environment', ($) async {
    await bootGetman($);
    await _openManageEnvironments($);
    await _createEnvironment($, 'Staging');
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    await sendShortcut($, LogicalKeyboardKey.keyE, meta: true);
    expect($('SWITCH ENVIRONMENT'), findsWidgets);

    // Row 0 = No Environment, row 1 = the only saved env (Staging).
    await $(const ValueKey('quick_env_row_1')).tap();
    await $.pumpAndSettle();

    await openEnvironmentSelector($);
    expect($('Staging'), findsWidgets);
  });

  patrolWidgetTest('switching active env changes the resolved base URL', (
    $,
  ) async {
    final dev = await MockServer.start(json: {'env': 'dev'});
    final prod = await MockServer.start(json: {'env': 'prod'});
    addTearDown(dev.close);
    addTearDown(prod.close);

    await bootGetman($);
    await _openManageEnvironments($);

    await _createEnvironment($, 'Dev');
    await $(const ValueKey('env_var_key_0')).enterText('base');
    await $(const ValueKey('env_var_val_0')).enterText(dev.baseUrl);
    await $.pumpAndSettle();

    await _createEnvironment($, 'Prod');
    await $(const ValueKey('env_var_key_0')).enterText('base');
    await $(const ValueKey('env_var_val_0')).enterText(prod.baseUrl);
    await $.pumpAndSettle();
    await $('CLOSE').tap();
    await $.pumpAndSettle();

    // Active = Dev → request hits the dev server.
    await openEnvironmentSelector($);
    await $('Dev').tap();
    await $.pumpAndSettle();
    await sendTo($, '{{base}}/ping');
    await waitForStatus($, 200);
    expect(dev.received, hasLength(1));

    // Switch to Prod → next request hits the prod server.
    await openEnvironmentSelector($);
    await $('Prod').tap();
    await $.pumpAndSettle();
    await sendTo($, '{{base}}/ping');
    // The dev response (also a 200) stays on screen during the re-send (a
    // re-send keeps the prior response until the new one lands — no flicker),
    // so waiting on the 200 status chip would match the *stale* dev response
    // and race the network call. Pump until the prod server actually receives.
    for (var i = 0; i < 100 && prod.received.isEmpty; i++) {
      await $.tester.pump(const Duration(milliseconds: 50));
    }
    expect(prod.received, hasLength(1));
    // And the switch really moved the base URL: dev got only the first request.
    expect(dev.received, hasLength(1));
  });
}
