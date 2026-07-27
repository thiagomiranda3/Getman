import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// D1: the desktop open-tabs dropdown in the tab strip — list every open tab,
/// live search filtering, activating a tab from a row, and Esc-to-close.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The dropdown's tab rows (keyed `open_tabs_row_<tabId>`). Text finders
  /// can't tell rows from the active tab's URL field, so count rows by key.
  Finder tabRows() => find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('open_tabs_row_');
  });

  patrolWidgetTest('lists open tabs, filters, and activates a row', ($) async {
    await bootGetman($);

    // Three tabs with distinct URLs (the seed tab keeps its httpbin URL).
    await enterUrl($, 'http://alpha.example/one');
    await newTab($);
    await enterUrl($, 'http://beta.example/two');
    await newTab($);
    await enterUrl($, 'http://gamma.example/three');
    expect(tabCount($), 3);

    await $(const ValueKey('open_tabs_button')).tap();
    expect($(const ValueKey('open_tabs_search_field')), findsOneWidget);
    expect($(tabRows()), findsNWidgets(3));

    // Filtering: no debounce, per-keystroke.
    await $(const ValueKey('open_tabs_search_field')).enterText('beta');
    await $.pumpAndSettle();
    expect($(tabRows()), findsOneWidget);

    // A non-matching query shows the empty message.
    await $(const ValueKey('open_tabs_search_field')).enterText('zzz-nope');
    await $.pumpAndSettle();
    expect($(tabRows()), findsNothing);
    expect($('NO MATCHING TABS'), findsOneWidget);

    // Back to a single match; clicking the row activates that tab and closes
    // the dropdown.
    await $(const ValueKey('open_tabs_search_field')).enterText('beta');
    await $.pumpAndSettle();
    await $(tabRows()).tap();
    await $.pumpAndSettle();
    expect($(const ValueKey('open_tabs_search_field')), findsNothing);
    expect(activeUrl($), 'http://beta.example/two');
  });

  patrolWidgetTest('Esc closes the open-tabs dropdown', ($) async {
    await bootGetman($);

    await $(const ValueKey('open_tabs_button')).tap();
    expect($(const ValueKey('open_tabs_search_field')), findsOneWidget);

    await sendShortcut($, LogicalKeyboardKey.escape);
    expect($(const ValueKey('open_tabs_search_field')), findsNothing);
  });
}
