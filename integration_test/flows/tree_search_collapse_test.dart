import 'package:flutter/material.dart' show IconButton, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/presentation/widgets/collections_list.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';

/// D2: the collections tree search matches by HTTP method (palette parity)
/// and the collapse-all button folds every expanded folder — but is disabled
/// while a search is active.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> saveRequestAs(PatrolTester $, String name) async {
    await $(const ValueKey('save_request_button')).tap();
    await enterPromptText($, name);
    await $('SAVE').tap();
    await $.pumpAndSettle();
  }

  Future<void> searchTree(PatrolTester $, String query) async {
    await $(const ValueKey('collections_search_field')).enterText(query);
    await $.tester.pump(const Duration(milliseconds: 500)); // debounce
    await $.pumpAndSettle();
  }

  /// Finder for [label] inside the collections tree only — saved names also
  /// title the linked tab chips in the strip, so bare text finders would
  /// match those too.
  Finder inTree(String label) => find.descendant(
    of: find.byType(CollectionsList),
    matching: find.text(label),
  );

  patrolWidgetTest('tree search matches by HTTP method', ($) async {
    await bootGetman($);

    // One GET node and one POST node at the root.
    await enterUrl($, 'http://one.example/get-me');
    await saveRequestAs($, 'Getter');
    await newTab($);
    await enterUrl($, 'http://two.example/post-me');
    await setMethod($, 'POST');
    await saveRequestAs($, 'Poster');

    expect($(inTree('Getter')), findsOneWidget);
    expect($(inTree('Poster')), findsOneWidget);

    // Method query: only the POST node stays.
    await searchTree($, 'post');
    expect($(inTree('Poster')), findsOneWidget);
    expect($(inTree('Getter')), findsNothing);

    // Clearing restores both.
    await searchTree($, '');
    expect($(inTree('Getter')), findsOneWidget);
    expect($(inTree('Poster')), findsOneWidget);
  });

  patrolWidgetTest('collapse-all folds folders and disables during search', (
    $,
  ) async {
    await bootGetman($);

    // A folder with a nested subfolder to expand/collapse.
    await $(const ValueKey('new_folder_button')).tap();
    await enterPromptText($, 'Outer');
    await $('CREATE').tap();
    await $.pumpAndSettle();

    await $(find.byIcon(Icons.more_vert).hitTestable()).tap();
    await $('ADD SUBFOLDER').tap();
    await enterPromptText($, 'Inner');
    await $('ADD').tap();
    await $.pumpAndSettle();

    // Expand the parent to reveal the child row.
    await $(find.byIcon(Icons.keyboard_arrow_right)).first.tap();
    await $.pumpAndSettle();
    expect($(inTree('Inner')), findsOneWidget);

    // Collapse-all hides the child again.
    await $(const ValueKey('collections_collapse_all')).tap();
    await $.pumpAndSettle();
    expect($(inTree('Inner')), findsNothing);

    // While searching, collapse-all is disabled.
    await searchTree($, 'Inner');
    final button = $.tester.widget<IconButton>(
      find.byKey(const ValueKey('collections_collapse_all')),
    );
    expect(button.onPressed, isNull);
  });
}
