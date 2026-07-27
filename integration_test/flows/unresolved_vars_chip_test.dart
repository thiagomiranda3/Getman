import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// E3: the pre-send unresolved-variable warning chip in the URL bar — appears
/// when the config references variables no active layer resolves, lists them
/// in its popup, links to the environment editor, and clears when the
/// variables go away. Purely advisory (SEND stays enabled).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const chip = ValueKey('unresolved_vars_chip');

  patrolWidgetTest('chip appears for unresolved vars and clears again', (
    $,
  ) async {
    await bootGetman($);
    expect($(chip), findsNothing);

    await enterUrl($, 'http://{{missing_host}}/path');
    // Recompute is debounced 300 ms after config keystrokes.
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.pumpAndSettle();
    expect($(chip), findsOneWidget);
    expect($('1'), findsWidgets); // unresolved count badge

    await enterUrl($, 'http://plain.example/path');
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.pumpAndSettle();
    expect($(chip), findsNothing);
  });

  patrolWidgetTest('chip popup lists names and opens the env editor', (
    $,
  ) async {
    await bootGetman($);

    await enterUrl($, 'http://{{missing_host}}/{{missing_path}}');
    await $.tester.pump(const Duration(milliseconds: 400));
    await $.pumpAndSettle();
    expect($(chip), findsOneWidget);

    await $(chip).tap();
    await $.pumpAndSettle();
    // Popup items are disabled entries rendered as {{name}} — they exist as
    // menu rows (the URL field's own text also matches, hence findsWidgets).
    expect($(find.textContaining('missing_host')), findsWidgets);
    expect($(find.textContaining('missing_path')), findsWidgets);

    await $('Open environment editor…').tap();
    await $.pumpAndSettle();
    expect($('ENVIRONMENTS'), findsWidgets);
  });
}
