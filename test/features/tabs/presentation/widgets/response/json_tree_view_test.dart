import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_view.dart';

Widget _host(Object? data) => MaterialApp(
  theme: brutalistTheme(Brightness.light),
  home: Scaffold(body: JsonTreeView(data: data)),
);

/// A row-text lookup scoped to the tree's row list. Plain `find.text()` also
/// matches `EditableText` (see flutter_test's `_MatchTextFinder`: "the
/// pattern is always compared to the current value of the
/// EditableText.controller"), so whenever the currently-typed filter query
/// happens to equal a row's label, an unscoped `find.text()` would find both
/// the filter field itself and the row — this scopes to just the rows.
Finder _row(String text) =>
    find.descendant(of: find.byType(ListView), matching: find.text(text));

void main() {
  group('JsonTreeView', () {
    testWidgets('renders top-level keys with nested objects expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host({
          'name': 'Ada',
          'addr': {'zip': '900'},
        }),
      );

      expect(find.text('name'), findsOneWidget);
      expect(find.text('addr'), findsOneWidget);
      // Top-level containers expand by default, so the nested key shows.
      expect(find.text('zip'), findsOneWidget);
    });

    testWidgets('tapping a container row collapses its children', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host({
          'addr': {'zip': '900'},
        }),
      );
      expect(find.text('zip'), findsOneWidget);

      await tester.tap(find.text('addr'));
      await tester.pumpAndSettle();

      expect(find.text('zip'), findsNothing);
    });

    testWidgets('renders array indices', (tester) async {
      await tester.pumpWidget(
        _host({
          'items': ['a', 'b'],
        }),
      );
      expect(find.text('[0]'), findsOneWidget);
      expect(find.text('[1]'), findsOneWidget);
    });

    testWidgets('copy path puts the JSONPath on the clipboard', (tester) async {
      final clips = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clips.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        _host({
          'user': {'id': 7},
        }),
      );

      await tester.tap(find.byKey(const ValueKey(r'tree_menu_$.user.id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy path'));
      await tester.pumpAndSettle();

      expect(clips, contains(r'$.user.id'));
    });

    testWidgets('extract action reports the node JSONPath', (tester) async {
      final extracted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: JsonTreeView(
              data: const {
                'user': {'id': 7},
              },
              onExtract: extracted.add,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey(r'tree_menu_$.user.id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extract to {{var}}'));
      await tester.pumpAndSettle();

      expect(extracted, [r'$.user.id']);
    });

    testWidgets('no extract action when onExtract is null', (tester) async {
      await tester.pumpWidget(_host(const {'a': 1}));
      await tester.tap(find.byKey(const ValueKey(r'tree_menu_$.a')));
      await tester.pumpAndSettle();
      expect(find.text('Extract to {{var}}'), findsNothing);
    });
  });

  group('flattenVisibleJsonTree (pure)', () {
    test('collapsed root shows only first-level rows', () {
      final data = {
        'a': 1,
        'b': {'c': 2},
      };
      final nodes = flattenVisibleJsonTree(data: data, expanded: <String>{});
      expect(nodes.map((n) => n.path).toList(), [r'$.a', r'$.b']);
    });

    test('expanded paths reveal their children in order', () {
      final data = {
        'a': 1,
        'b': {'c': 2},
      };
      final nodes = flattenVisibleJsonTree(
        data: data,
        expanded: {r'$.b'},
      );
      expect(nodes.map((n) => n.path).toList(), [r'$.a', r'$.b', r'$.b.c']);
    });

    test('top-level list indexes by position', () {
      final nodes = flattenVisibleJsonTree(
        data: [10, 20],
        expanded: <String>{},
      );
      expect(nodes.map((n) => n.path).toList(), [r'$[0]', r'$[1]']);
      expect(nodes.map((n) => n.label).toList(), ['[0]', '[1]']);
    });
  });

  group('JsonTreeView filter + expand/collapse-all (C2)', () {
    testWidgets('filter narrows rows to matches with their ancestors and '
        'shows the match count', (tester) async {
      await tester.pumpWidget(
        _host({
          'user': {'name': 'Ada', 'zip': '900'},
          'other': {'flag': true},
        }),
      );
      expect(find.text('flag'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('tree_filter_field')),
        'zip',
      );
      await tester.pumpAndSettle();

      // _row(): the typed query itself echoes as "zip" in the filter
      // field's own EditableText, which find.text() also matches — so an
      // unscoped lookup would find 2 (see _row's doc comment above).
      expect(_row('zip'), findsOneWidget);
      expect(find.text('user'), findsOneWidget, reason: 'ancestor stays');
      expect(find.text('other'), findsNothing);
      expect(find.text('flag'), findsNothing);
      expect(find.text('1 MATCH'), findsOneWidget);
    });

    testWidgets('clearing the filter restores all rows', (tester) async {
      await tester.pumpWidget(
        _host({
          'user': {'zip': '900'},
          'other': {'flag': true},
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('tree_filter_field')),
        'zip',
      );
      await tester.pumpAndSettle();
      expect(find.text('other'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('tree_filter_field')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('other'), findsOneWidget);
      expect(find.text('flag'), findsOneWidget);
    });

    testWidgets(
      'tapping a filter-ancestor-only row does not leak into the persisted '
      'expansion set',
      (tester) async {
        await tester.pumpWidget(
          _host({
            'a': {
              'b': {'c': 1},
            },
          }),
        );
        // Pre-filter: seeded expansion opens 'a' only.
        expect(find.text('b'), findsOneWidget);
        expect(find.text('c'), findsNothing);

        await tester.enterText(
          find.byKey(const ValueKey('tree_filter_field')),
          'c',
        );
        await tester.pumpAndSettle();
        // 'b' is auto-expanded only because the filter revealed it as an
        // ancestor of the 'c' match — it was never manually toggled. (Query
        // is 'c', so 'c' lookups are scoped via _row(); see its doc comment.)
        expect(_row('c'), findsOneWidget);

        await tester.tap(find.text('b'));
        await tester.pumpAndSettle();
        expect(
          _row('c'),
          findsNothing,
          reason: 'collapsed in the filtered view',
        );

        await tester.enterText(
          find.byKey(const ValueKey('tree_filter_field')),
          '',
        );
        await tester.pumpAndSettle();

        // Clearing the filter must restore exactly the pre-filter state:
        // 'a' expanded (seed), 'b' visible but collapsed (never manually
        // expanded), so 'c' stays hidden. Before the fix, tapping 'b' while
        // it was filter-expanded added it to the persisted `_expanded` set,
        // so 'c' would incorrectly reappear here.
        expect(find.text('b'), findsOneWidget);
        expect(find.text('c'), findsNothing);
      },
    );

    testWidgets(
      'tapping a filter-ancestor row toggles back open within the same '
      'filter session',
      (tester) async {
        await tester.pumpWidget(
          _host({
            'a': {
              'b': {'c': 1},
            },
          }),
        );
        await tester.enterText(
          find.byKey(const ValueKey('tree_filter_field')),
          'c',
        );
        await tester.pumpAndSettle();
        expect(_row('c'), findsOneWidget);

        await tester.tap(find.text('b')); // collapse
        await tester.pumpAndSettle();
        expect(_row('c'), findsNothing);

        await tester.tap(find.text('b')); // re-expand, filter still active
        await tester.pumpAndSettle();
        expect(_row('c'), findsOneWidget);
      },
    );

    testWidgets(
      'switching the filter query clears stale collapse overrides so the '
      "new query's auto-expansion is not suppressed",
      (tester) async {
        await tester.pumpWidget(
          _host({
            'root': {
              'container': {'itemA': 1, 'itemB': 2},
            },
          }),
        );

        await tester.enterText(
          find.byKey(const ValueKey('tree_filter_field')),
          'itemA',
        );
        await tester.pumpAndSettle();
        expect(_row('itemA'), findsOneWidget);

        // 'container' is open only as a filter ancestor of 'itemA'; collapse
        // it — this must record a session-visual override, not a persisted
        // one.
        await tester.tap(find.text('container'));
        await tester.pumpAndSettle();
        expect(_row('itemA'), findsNothing);

        // Switching to a different, non-empty query is a new filter — the
        // stale 'container' override recorded under the 'itemA' query must
        // not suppress auto-expansion for 'itemB'.
        await tester.enterText(
          find.byKey(const ValueKey('tree_filter_field')),
          'itemB',
        );
        await tester.pumpAndSettle();
        expect(_row('itemB'), findsOneWidget);
      },
    );

    testWidgets('collapse-all hides children; expand-all reveals deep rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host({
          'a': {
            'b': {'c': 1},
          },
        }),
      );
      // Seeded expansion opens top-level 'a' only; 'c' needs 'b' expanded.
      expect(find.text('b'), findsOneWidget);
      expect(find.text('c'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tree_expand_all')));
      await tester.pumpAndSettle();
      expect(find.text('c'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tree_collapse_all')));
      await tester.pumpAndSettle();
      expect(find.text('b'), findsNothing);
      expect(find.text('c'), findsNothing);
      expect(find.text('a'), findsOneWidget);
    });

    testWidgets('expand-all on an over-2000-node tree stops at depth 3 and '
        'shows a note', (tester) async {
      await tester.pumpWidget(
        _host({
          'deep': {
            'l1': {
              'l2': {
                'l3': {'l4': 'leaf'},
              },
            },
          },
          'bulk': {for (var i = 0; i < 2100; i++) 'k$i': i},
        }),
      );

      await tester.tap(find.byKey(const ValueKey('tree_expand_all')));
      await tester.pump(); // snackbar
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Large tree — expanded to depth 3'), findsOneWidget);
      // Rows down to depth 3 are visible; depth 4 is not.
      expect(find.text('l3'), findsOneWidget);
      expect(find.text('l4'), findsNothing);
    });

    testWidgets('over-cap filter shows the refine hint', (tester) async {
      await tester.pumpWidget(
        _host({for (var i = 0; i < 600; i++) 'match_key_$i': i}),
      );
      await tester.enterText(
        find.byKey(const ValueKey('tree_filter_field')),
        'match_key',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('tree_filter_truncated')),
        findsOneWidget,
      );
      expect(find.text('Refine filter to see more'), findsOneWidget);
    });

    testWidgets('filterFocusNode focuses the filter field', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: JsonTreeView(data: const {'a': 1}, filterFocusNode: node),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tree_filter_field')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
    });
  });
}
