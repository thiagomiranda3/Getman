import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/utils/layered_variable_context.dart';

const _mapEquality = MapEquality<String, String>();
const _stringListEquality = ListEquality<String>();

/// Order-SIGNIFICANT map equality mirroring the production map hosts'
/// `_orderedHeadersEqual` / `_orderedVariablesEqual` — a pure reorder must
/// compare unequal so the editor's didUpdateWidget rebuild path runs.
bool _orderedMapEquals(Map<String, String> a, Map<String, String> b) =>
    _mapEquality.equals(a, b) &&
    _stringListEquality.equals(a.keys.toList(), b.keys.toList());

/// Harness that echoes every emission back into the editor, mimicking the
/// BLoC round-trip the real editors live in.
class _EchoHarness extends StatefulWidget {
  const _EchoHarness({required this.initial, super.key, this.onEmit});
  final Map<String, String> initial;
  final void Function(Map<String, String>)? onEmit;

  @override
  State<_EchoHarness> createState() => _EchoHarnessState();
}

class _EchoHarnessState extends State<_EchoHarness> {
  late Map<String, String> items = widget.initial;

  void replace(Map<String, String> next) => setState(() => items = next);

  @override
  Widget build(BuildContext context) {
    return KeyValueListEditor<Map<String, String>>(
      items: items,
      decode: (map) => [for (final e in map.entries) (e.key, e.value)],
      encode: (rows) => {
        for (final (key, value) in rows)
          if (key.isNotEmpty) key: value,
      },
      equals: _mapEquality.equals,
      onChanged: (map) {
        widget.onEmit?.call(map);
        setState(() => items = map);
      },
    );
  }
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );
  }

  Finder keyFieldAt(int index) =>
      find.widgetWithText(TextField, 'KEY').at(index);

  Future<void> dragHandleBy(
    WidgetTester tester,
    Finder handle,
    double dy,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(Offset(0, dy / 2));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(Offset(0, dy / 2));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  String keyTextAt(WidgetTester tester, int index) => tester
      .widget<TextField>(find.byKey(ValueKey('kv_key_$index')))
      .controller!
      .text;

  String valTextAt(WidgetTester tester, int index) => tester
      .widget<TextField>(find.byKey(ValueKey('kv_val_$index')))
      .controller!
      .text;

  testWidgets('renders one row per item plus a trailing empty row', (
    tester,
  ) async {
    await pump(tester, const _EchoHarness(initial: {'Accept': '*/*'}));

    expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(2));
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets(
    'typing a key into the trailing row emits it and grows a new trailing row',
    (tester) async {
      final emissions = <Map<String, String>>[];
      await pump(
        tester,
        _EchoHarness(initial: const {}, onEmit: emissions.add),
      );

      await tester.enterText(keyFieldAt(0), 'X-Token');
      await tester.pump();

      expect(emissions.last, {'X-Token': ''});
      expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(2));
    },
  );

  testWidgets('deleting a row emits without it and never leaves zero rows', (
    tester,
  ) async {
    final emissions = <Map<String, String>>[];
    await pump(
      tester,
      _EchoHarness(initial: const {'Accept': '*/*'}, onEmit: emissions.add),
    );

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(emissions.last, isEmpty);
    expect(find.widgetWithText(TextField, 'KEY'), findsOneWidget);

    // Deleting the final remaining row re-adds an empty one.
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    expect(find.widgetWithText(TextField, 'KEY'), findsOneWidget);
  });

  testWidgets(
    'deleting the trailing blank row (with a non-empty row remaining) '
    'still leaves an "add new row" affordance',
    (tester) async {
      // Repro (A2): rows [a=1, <blank>]; deleting the blank row must not
      // strand the editor with zero blank rows to type a new one into.
      await pump(tester, const _EchoHarness(initial: {'a': '1'}));

      // Two rows: 'a' and the trailing blank.
      expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(2));

      // Delete the trailing (blank) row — it's the last one, index 1.
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pump();

      // The remaining 'a' row's key is non-empty, so a fresh blank row must
      // have been re-added — the count should still be 2 (a + new blank),
      // not 1.
      expect(
        find.widgetWithText(TextField, 'KEY'),
        findsNWidgets(2),
        reason:
            'a blank trailing row must survive so the user can still '
            'add a new entry',
      );
      expect(find.text('a'), findsOneWidget);
    },
  );

  testWidgets(
    'echoes of its own emission do not rebuild the text controllers',
    (tester) async {
      await pump(tester, const _EchoHarness(initial: {}));

      final controllerBefore = tester
          .widget<TextField>(keyFieldAt(0))
          .controller;
      await tester.enterText(keyFieldAt(0), 'X-Token');
      await tester.pump(); // echo round-trip via the harness setState

      final controllerAfter = tester
          .widget<TextField>(keyFieldAt(0))
          .controller;
      expect(
        identical(controllerBefore, controllerAfter),
        isTrue,
        reason: 'an echo rebuild would destroy focus and half-typed state',
      );
      expect(find.text('X-Token'), findsOneWidget);
    },
  );

  testWidgets('a genuinely external change rebuilds the rows', (tester) async {
    final key = GlobalKey<_EchoHarnessState>();
    await pump(tester, _EchoHarness(key: key, initial: const {}));

    key.currentState!.replace({'Authorization': 'Bearer x'});
    await tester.pump();

    expect(find.text('Authorization'), findsOneWidget);
    expect(find.text('Bearer x'), findsOneWidget);
  });

  group('secret keys', () {
    testWidgets(
      'no lock toggle when secretKeys is null (params/headers mode)',
      (tester) async {
        await pump(tester, const _EchoHarness(initial: {'Accept': '*/*'}));
        expect(find.byIcon(Icons.lock_open_outlined), findsNothing);
        expect(find.byIcon(Icons.lock_outline), findsNothing);
      },
    );

    testWidgets(
      'a secret variable obscures its value and offers a reveal toggle',
      (tester) async {
        await pump(
          tester,
          const _SecretHarness(
            initialVars: {'TOKEN': 'abc123'},
            initialSecrets: {'TOKEN'},
          ),
        );

        bool anyObscured() => tester
            .widgetList<TextField>(find.byType(TextField))
            .any((f) => f.obscureText);

        expect(anyObscured(), isTrue);
        expect(find.byIcon(Icons.visibility), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);

        await tester.tap(find.byIcon(Icons.visibility));
        await tester.pump();

        expect(
          anyObscured(),
          isFalse,
          reason: 'reveal toggle un-obscures the value',
        );
        expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      },
    );

    testWidgets(
      're-marking a previously-revealed variable secret re-obscures it',
      (tester) async {
        await pump(
          tester,
          const _SecretHarness(
            initialVars: {'TOKEN': 'abc123'},
            initialSecrets: {'TOKEN'},
          ),
        );

        bool anyObscured() => tester
            .widgetList<TextField>(find.byType(TextField))
            .any((f) => f.obscureText);

        // Reveal the secret value.
        await tester.tap(find.byIcon(Icons.visibility));
        await tester.pump();
        expect(anyObscured(), isFalse);

        // Unmark secret (lock -> open), then mark it secret again.
        await tester.tap(find.byIcon(Icons.lock_outline));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.lock_open_outlined).first);
        await tester.pump();

        // The re-marked secret must start obscured, not inherit the stale
        // reveal.
        expect(anyObscured(), isTrue);
      },
    );

    testWidgets('tapping the lock reports the new secret set', (tester) async {
      Set<String>? reported;
      await pump(
        tester,
        _SecretHarness(
          initialVars: const {'TOKEN': 'abc'},
          initialSecrets: const {},
          onSecrets: (s) => reported = s,
        ),
      );

      // TOKEN row + trailing empty row both show an open lock; tap TOKEN's.
      await tester.tap(find.byIcon(Icons.lock_open_outlined).first);
      await tester.pump();

      expect(reported, {'TOKEN'});
    });
  });

  testWidgets('value field shows {{var}} autocomplete when a '
      'variableContext is provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: KeyValueListEditor<Map<String, String>>(
            items: const <String, String>{},
            decode: (map) => [for (final e in map.entries) (e.key, e.value)],
            encode: (rows) => {
              for (final (key, value) in rows)
                if (key.isNotEmpty) key: value,
            },
            equals: const MapEquality<String, String>().equals,
            variableContext: const LayeredVariableContext(
              environmentVariables: {'baseUrl': 'https://x', 'token': 't'},
              environmentName: 'Dev',
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    // First (empty) row's value field.
    await tester.enterText(find.widgetWithText(TextField, 'VALUE').first, '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
    expect(find.text('token'), findsOneWidget);
  });

  testWidgets(
    'accepting a {{var}} suggestion persists via onChanged '
    '(programmatic accept skips TextField.onChanged)',
    (tester) async {
      Map<String, String>? emitted;

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: KeyValueListEditor<Map<String, String>>(
              items: const <String, String>{'X': ''},
              decode: (map) => [for (final e in map.entries) (e.key, e.value)],
              encode: (rows) => {
                for (final (key, value) in rows)
                  if (key.isNotEmpty) key: value,
              },
              equals: const MapEquality<String, String>().equals,
              variableContext: const LayeredVariableContext(
                environmentVariables: {'baseUrl': 'https://x'},
                environmentName: 'Dev',
              ),
              onChanged: (map) => emitted = map,
            ),
          ),
        ),
      );

      // The row for key 'X' is the first VALUE field (index 0).
      await tester.enterText(
        find.widgetWithText(TextField, 'VALUE').first,
        '{{',
      );
      await tester.pumpAndSettle();
      expect(find.text('baseUrl'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        emitted,
        {'X': '{{baseUrl}}'},
        reason:
            'accepting a suggestion must emit via onChanged (onAccepted path)',
      );
    },
  );

  group('per-row enable checkbox (B1)', () {
    testWidgets('no checkbox column when rowEnabled/onToggleEnabled are null', (
      tester,
    ) async {
      await pump(tester, const _EchoHarness(initial: {'Accept': '*/*'}));
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('one checkbox per row, none on the trailing blank row', (
      tester,
    ) async {
      await pump(
        tester,
        const _ToggleHarness(
          initial: {'A': '1', 'B': '2'},
          initiallyDisabled: {},
        ),
      );
      // 3 rows rendered (A, B, trailing blank) but only 2 checkboxes.
      expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(3));
      expect(find.byType(Checkbox), findsNWidgets(2));
    });

    testWidgets('toggling reports index, key, value and the new state', (
      tester,
    ) async {
      (int, String, String, bool)? reported;
      await pump(
        tester,
        _ToggleHarness(
          initial: const {'A': '1', 'B': '2'},
          initiallyDisabled: const {},
          onToggle: (index, key, value, enabled) =>
              reported = (index, key, value, enabled),
        ),
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(reported, (0, 'A', '1', false));
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(checkbox.value, isFalse);
    });

    testWidgets('a disabled row renders dimmed (key and value cells)', (
      tester,
    ) async {
      await pump(
        tester,
        const _ToggleHarness(
          initial: {'A': '1', 'B': '2'},
          initiallyDisabled: {0},
        ),
      );
      expect(
        find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1.0),
        findsNWidgets(2),
        reason: 'the disabled row dims its key cell and its value cell',
      );
    });

    testWidgets(
      'disabledRowsReadOnly makes disabled row fields non-interactive',
      (tester) async {
        await pump(
          tester,
          const _ToggleHarness(
            initial: {'A': '1', 'B': '2'},
            initiallyDisabled: {0},
            readOnlyWhenDisabled: true,
          ),
        );
        expect(
          find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring),
          findsNWidgets(2),
          reason: 'key + value cells of the disabled row are pointer-blocked',
        );
      },
    );

    testWidgets(
      'a headers-style toggle (items unchanged) keeps controllers alive',
      (tester) async {
        await pump(
          tester,
          const _ToggleHarness(
            initial: {'A': '1', 'B': '2'},
            initiallyDisabled: {},
          ),
        );
        final controllerBefore = tester
            .widget<TextField>(keyFieldAt(0))
            .controller;

        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();

        final controllerAfter = tester
            .widget<TextField>(keyFieldAt(0))
            .controller;
        expect(
          identical(controllerBefore, controllerAfter),
          isTrue,
          reason: 'toggling must not rebuild rows when items are unchanged',
        );
      },
    );

    testWidgets('deleting a row keeps flags aligned with remaining rows', (
      tester,
    ) async {
      await pump(
        tester,
        const _ToggleHarness(
          initial: {'A': '1', 'B': '2', 'C': '3'},
          initiallyDisabled: {1},
        ),
      );
      // Delete row 0 (A). B's disabled flag must follow B to index 0.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();

      final firstCheckbox = tester.widget<Checkbox>(
        find.byType(Checkbox).at(0),
      );
      final secondCheckbox = tester.widget<Checkbox>(
        find.byType(Checkbox).at(1),
      );
      expect(firstCheckbox.value, isFalse, reason: 'B stays disabled');
      expect(secondCheckbox.value, isTrue, reason: 'C stays enabled');
    });
  });

  group('reorder + duplicate (B2)', () {
    testWidgets(
      'no drag handles or duplicate buttons when the callbacks are null '
      '(existing hosts unchanged)',
      (tester) async {
        await pump(tester, const _EchoHarness(initial: {'a': '1', 'b': '2'}));
        expect(find.byIcon(Icons.drag_indicator), findsNothing);
        expect(find.byIcon(Icons.content_copy), findsNothing);
      },
    );

    testWidgets(
      'data rows show handle + duplicate; the trailing blank row shows '
      'neither',
      (tester) async {
        await pump(
          tester,
          const _ReorderDuplicateHarness(initial: {'a': '1', 'b': '2'}),
        );
        // 2 data rows + 1 trailing blank = 3 delete buttons, but only the
        // 2 data rows get a handle and a duplicate button.
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
        expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
        expect(find.byIcon(Icons.content_copy), findsNWidgets(2));
      },
    );

    testWidgets(
      'dragging row 0 below row 1 reports onReorder(0, 1) and moves the '
      'row visually',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2'},
            onReorderCalls: calls,
          ),
        );

        final row0 = tester.getCenter(find.byKey(const ValueKey('kv_key_0')));
        final row1 = tester.getCenter(find.byKey(const ValueKey('kv_key_1')));
        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).first,
          row1.dy - row0.dy + 8,
        );

        expect(calls, [(0, 1)]);
        expect(keyTextAt(tester, 0), 'b');
        expect(keyTextAt(tester, 1), 'a');
      },
    );

    testWidgets(
      'a drop past the trailing blank row clamps to the last data slot',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2'},
            onReorderCalls: calls,
          ),
        );

        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).first,
          500,
        );

        expect(
          calls,
          [(0, 1)],
          reason: 'newIndex must clamp to the last data row, never the blank',
        );
        expect(keyTextAt(tester, 0), 'b');
        expect(keyTextAt(tester, 1), 'a');
      },
    );

    testWidgets(
      'tapping duplicate reports the row index and the host copy appears '
      'below',
      (tester) async {
        final calls = <int>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2'},
            onDuplicateCalls: calls,
          ),
        );

        await tester.tap(find.byIcon(Icons.content_copy).first);
        await tester.pumpAndSettle();

        expect(calls, [0]);
        // Host inserted a-copy below a: rows are now a, a-copy, b (+ blank).
        expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(4));
        expect(keyTextAt(tester, 1), 'a-copy');
      },
    );

    testWidgets(
      'a disabled (parked) row shows neither a drag handle nor a duplicate '
      'button — only the checkbox and delete stay live',
      (tester) async {
        await pump(
          tester,
          const _ReorderDuplicateHarness(
            initial: {'a': '1', 'z': '9', 'b': '2'},
            disabledKeys: {'z'},
          ),
        );

        // 3 data rows: a (enabled), z (disabled/parked), b (enabled).
        expect(find.byType(Checkbox), findsNWidgets(3));
        expect(
          find.byIcon(Icons.drag_indicator),
          findsNWidgets(2),
          reason: 'the parked row (z) must not get a drag handle',
        );
        expect(
          find.byIcon(Icons.content_copy),
          findsNWidgets(2),
          reason: 'the parked row (z) must not get a duplicate button',
        );

        // Position-specific: the parked row's own layout Row (nearest Row
        // ancestor of its key field) has neither affordance; the enabled
        // neighbour's Row has both.
        Finder rowOf(String fieldKey) => find
            .ancestor(
              of: find.byKey(ValueKey(fieldKey)),
              matching: find.byType(Row),
            )
            .first;

        expect(
          find.descendant(
            of: rowOf('kv_key_1'),
            matching: find.byIcon(Icons.drag_indicator),
          ),
          findsNothing,
          reason: "no drag handle in the parked row's ('z') own layout row",
        );
        expect(
          find.descendant(
            of: rowOf('kv_key_1'),
            matching: find.byIcon(Icons.content_copy),
          ),
          findsNothing,
          reason:
              "no duplicate button in the parked row's ('z') own layout row",
        );
        expect(
          find.descendant(
            of: rowOf('kv_key_0'),
            matching: find.byIcon(Icons.drag_indicator),
          ),
          findsOneWidget,
          reason: "the enabled neighbour ('a') keeps its drag handle",
        );
      },
    );
  });

  group('cleared interior KEY rows translate host indices (_hostIndexFor)', () {
    // Clearing an interior row's KEY keeps the row alive in the editor
    // (echo suppression) while every host's encode drops it — raw editor
    // indices then sit one past the host's for every row below the cleared
    // one, so index-based host ops must translate through _hostIndexFor.
    Future<void> clearInteriorKey(WidgetTester tester) async {
      await tester.enterText(find.byKey(const ValueKey('kv_key_1')), '');
      await tester.pump();
      // Unfocus: dragging the still-focused row into the reorder overlay
      // trips the LeaderLayer-before-FollowerLayer paint assertion.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    }

    testWidgets(
      "dragging the row below a cleared-key row reports the host's decoded "
      "indices — (1, 0), not the editor's raw (2, 0)",
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onReorderCalls: calls,
          ),
        );
        await clearInteriorKey(tester);

        // Editor rows: a, '' (cleared b, editor-only), c, blank. Drag 'c'
        // (editor row 2, handle icon 2) to the top slot.
        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        expect(
          calls,
          [(1, 0)],
          reason:
              "the host's decoded rows are [a, c] — 'c' is host index 1, "
              'not raw editor index 2',
        );
        expect(keyTextAt(tester, 0), 'c');
        expect(keyTextAt(tester, 1), 'a');
      },
    );

    testWidgets(
      'dragging the cleared-key row itself never reaches the host — it has '
      'no canonical counterpart to move',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onReorderCalls: calls,
          ),
        );
        await clearInteriorKey(tester);

        // The cleared row (editor row 1, handle icon 1) drags to the top.
        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(1),
          -1000,
        );

        expect(calls, isEmpty);
      },
    );

    testWidgets(
      'duplicate on the row below a cleared-key row reports the decoded '
      'index — 1, not raw 2 — and the cleared row itself is a no-op',
      (tester) async {
        final calls = <int>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onDuplicateCalls: calls,
          ),
        );
        await clearInteriorKey(tester);

        // The cleared row's duplicate button is inert — no canonical row.
        await tester.tap(find.byIcon(Icons.content_copy).at(1));
        await tester.pump();
        expect(calls, isEmpty);

        // 'c' (editor row 2) duplicates as host index 1.
        await tester.tap(find.byIcon(Icons.content_copy).at(2));
        await tester.pumpAndSettle();

        expect(calls, [1]);
        expect(find.text('c-copy'), findsOneWidget);
      },
    );

    testWidgets(
      'toggling the checkbox of a row below a cleared-key row reports the '
      'decoded index — 1, not raw 2',
      (tester) async {
        (int, String, String, bool)? reported;
        await pump(
          tester,
          _ToggleHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            initiallyDisabled: const {},
            onToggle: (index, key, value, enabled) =>
                reported = (index, key, value, enabled),
          ),
        );

        // Clear the interior 'b' key (no fieldPrefix here — find by text).
        await tester.enterText(find.widgetWithText(TextField, 'b'), '');
        await tester.pump();

        // Rows: a, '' (cleared), c, blank — checkboxes on the first three.
        await tester.tap(find.byType(Checkbox).at(2));
        await tester.pump();

        expect(reported, (1, 'c', '3', false));
      },
    );
  });

  group('keyless-row reconcile: cleared-key rows survive genuine rebuilds', () {
    // Echo suppression alone cannot keep a cleared-key row alive across a
    // host mutation whose echo genuinely differs (params toggle, any
    // reorder/duplicate): didUpdateWidget rebuilds from canonical items,
    // which dropped the keyless row when its clear was emitted. The
    // reconcile snapshots such rows and reinserts them — the typed VALUE is
    // the data being protected.
    testWidgets(
      'params-style toggle (echo genuinely differs) keeps a cleared-key '
      "row's value alive at its position",
      (tester) async {
        await pump(
          tester,
          const _ParamsStyleToggleHarness(
            initial: [('a', '1', true), ('b', '2', true), ('c', '3', true)],
          ),
        );

        // Clear b's key: the row now lives only inside the editor.
        await tester.enterText(find.byKey(const ValueKey('kv_key_1')), '');
        await tester.pump();

        // Toggle a's checkbox — enabled is part of the canonical rows, so
        // the echo differs and didUpdateWidget takes the full rebuild path.
        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();

        expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(4));
        expect(keyTextAt(tester, 0), 'a');
        expect(keyTextAt(tester, 1), '');
        expect(
          valTextAt(tester, 1),
          '2',
          reason: "the cleared-key row's typed value must survive the rebuild",
        );
        expect(keyTextAt(tester, 2), 'c');
        final checkboxes = tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .toList();
        expect(checkboxes[0].value, isFalse, reason: "a's toggle applied");
        expect(
          checkboxes[1].value,
          isTrue,
          reason: "the keyless row's own enabled flag survives the rebuild",
        );
      },
    );

    testWidgets(
      "reorder on an order-significant map host keeps a cleared-key row's "
      'value alive at its position across the rebuild',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onReorderCalls: calls,
            orderedEquals: true,
          ),
        );

        await tester.enterText(find.byKey(const ValueKey('kv_key_1')), '');
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        // Drag c (editor row 2) to the top; the ordered-equals echo differs
        // from what was emitted, so the editor rebuilds from canonical
        // [c, a] — the ''=2 row must be reinserted, not eaten.
        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        expect(calls, [(1, 0)]);
        expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(4));
        expect(keyTextAt(tester, 0), 'c');
        expect(keyTextAt(tester, 1), 'a');
        expect(keyTextAt(tester, 2), '');
        expect(
          valTextAt(tester, 2),
          '2',
          reason: "the cleared-key row's typed value must survive the rebuild",
        );
      },
    );

    testWidgets(
      "duplicate keeps a cleared-key row's value alive at its position "
      'across the rebuild',
      (tester) async {
        final calls = <int>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onDuplicateCalls: calls,
          ),
        );

        await tester.enterText(find.byKey(const ValueKey('kv_key_1')), '');
        await tester.pump();

        // Duplicate 'a' — the echo ({a, a-copy, c}) genuinely differs even
        // under a plain MapEquality, forcing the rebuild path.
        await tester.tap(find.byIcon(Icons.content_copy).first);
        await tester.pumpAndSettle();

        expect(calls, [0]);
        expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(5));
        expect(keyTextAt(tester, 0), 'a');
        expect(keyTextAt(tester, 1), '');
        expect(
          valTextAt(tester, 1),
          '2',
          reason: "the cleared-key row's typed value must survive the rebuild",
        );
        expect(keyTextAt(tester, 2), 'a-copy');
        expect(keyTextAt(tester, 3), 'c');
      },
    );
  });

  group('map-host index translation with duplicate keys '
      '(KeyValueHostIndexing)', () {
    // Map hosts collapse duplicate keys: the entry's POSITION is the first
    // occurrence's, its VALUE the last's. With a duplicate-key row alive
    // above (echo suppression keeps it), skipping only empty keys reports
    // host indices one past the entry list — reorder/duplicate then hit the
    // wrong row or silently no-op with a persistent visual desync.
    Future<void> renameRowOneTo(WidgetTester tester, String key) async {
      await tester.enterText(find.byKey(const ValueKey('kv_key_1')), key);
      await tester.pump();
      // Unfocus: dragging the still-focused row into the reorder overlay
      // trips the LeaderLayer-before-FollowerLayer paint assertion.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    }

    testWidgets(
      'with a duplicate-key row alive above, dragging a lower row reports '
      "the ENTRY index — (1, 0), not the editor's non-empty-key count (2, 0)",
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onReorderCalls: calls,
            orderedEquals: true,
          ),
        );

        // Rename b → a: encode collapses to {a: 2, c: 3}, the echo matches
        // what was emitted, and BOTH 'a' rows stay alive via suppression.
        await renameRowOneTo(tester, 'a');
        expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(4));

        // Drag c (editor row 2) to the top. Canonical entries are [a, c]:
        // c is entry 1. Empty-only skipping would report (2, 0) — an
        // out-of-range index the host silently drops (persistent desync).
        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        expect(calls, [(1, 0)]);
        // Canonical and visual agree: [c, a], with 'a' carrying the
        // last-write value '2' (the duplicate rows collapse on this
        // genuine rebuild).
        expect(keyTextAt(tester, 0), 'c');
        expect(keyTextAt(tester, 1), 'a');
        expect(valTextAt(tester, 1), '2');
      },
    );

    testWidgets(
      'with a duplicate-key row alive above, duplicating a lower row hits '
      'the right entry — 1, not the non-empty-key count 2',
      (tester) async {
        final calls = <int>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onDuplicateCalls: calls,
            orderedEquals: true,
          ),
        );

        await renameRowOneTo(tester, 'a');

        await tester.tap(find.byIcon(Icons.content_copy).at(2));
        await tester.pumpAndSettle();

        expect(calls, [1]);
        expect(find.text('c-copy'), findsOneWidget);
      },
    );

    testWidgets(
      'dragging the collapsed duplicate row itself never reaches the host — '
      'its map entry belongs to the first occurrence',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onReorderCalls: calls,
            orderedEquals: true,
          ),
        );

        await renameRowOneTo(tester, 'a');

        // Editor row 1 is the second 'a' occurrence — canonically it is the
        // same entry as row 0, so there is nothing for the host to move.
        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(1),
          -1000,
        );

        expect(calls, isEmpty);
      },
    );

    testWidgets(
      'env-style trimming host: keys equal after trim collapse — the '
      'translation derives that from the codec, not a hardcoded rule',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2', 'c': '3'},
            onReorderCalls: calls,
            orderedEquals: true,
            trimKeys: true,
          ),
        );

        // Rename b → ' a ' — trims to a duplicate of 'a', collapsing in
        // encode exactly like the env editor's trimming codec.
        await renameRowOneTo(tester, ' a ');

        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        expect(calls, [(1, 0)]);
        expect(keyTextAt(tester, 0), 'c');
        expect(keyTextAt(tester, 1), 'a');
        expect(valTextAt(tester, 1), '2');
      },
    );

    testWidgets(
      'env-style trimming host: a whitespace-only key row is editor-only — '
      'dragging it never reaches the host',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ReorderDuplicateHarness(
            initial: const {'a': '1', 'b': '2'},
            onReorderCalls: calls,
            trimKeys: true,
          ),
        );

        // Type a whitespace-only key into the trailing blank row: encode
        // drops it, echo suppression keeps it alive.
        await tester.enterText(find.byKey(const ValueKey('kv_key_2')), ' ');
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(find.widgetWithText(TextField, 'KEY'), findsNWidgets(4));

        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        expect(calls, isEmpty);
      },
    );

    testWidgets(
      'list host (auto infers list for non-Map items): duplicate keys are '
      'all real host rows — no first-occurrence collapse',
      (tester) async {
        final calls = <(int, int)>[];
        await pump(
          tester,
          _ListHostReorderHarness(
            initial: const [('a', '1'), ('a', '2'), ('c', '3')],
            onReorderCalls: calls,
          ),
        );

        await dragHandleBy(
          tester,
          find.byIcon(Icons.drag_indicator).at(2),
          -1000,
        );

        expect(
          calls,
          [(2, 0)],
          reason:
              'a list-backed host keeps every duplicate-key row; map-style '
              'first-occurrence counting would report (1, 0)',
        );
        expect(keyTextAt(tester, 0), 'c');
        expect(keyTextAt(tester, 1), 'a');
        expect(valTextAt(tester, 1), '1');
        expect(keyTextAt(tester, 2), 'a');
        expect(valTextAt(tester, 2), '2');
      },
    );
  });

  group('phone layout + row hover', () {
    testWidgets('phone width stacks the value field under the key row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 900); // phone tier ≤ 700
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pump(tester, const _EchoHarness(initial: {'Accept': '*/*'}));

      final keyRect = tester.getRect(
        find.widgetWithText(TextField, 'KEY').first,
      );
      final valRect = tester.getRect(
        find.widgetWithText(TextField, 'VALUE').first,
      );
      expect(
        valRect.top,
        greaterThanOrEqualTo(keyRect.bottom),
        reason: 'value stacks below the key row instead of beside it',
      );
      expect(
        valRect.width,
        greaterThan(keyRect.width),
        reason: 'the value field spans the full row width on phones',
      );
    });

    testWidgets(
      'phone layout keeps checkbox/drag/duplicate affordances on the key row',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await pump(
          tester,
          const _ReorderDuplicateHarness(
            initial: {'a': '1', 'b': '2'},
            disabledKeys: {'b'},
          ),
        );

        expect(find.byType(Checkbox), findsNWidgets(2));
        // Only the enabled row ('a') gets drag + duplicate; 'b' is disabled.
        expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
        expect(find.byIcon(Icons.content_copy), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
      },
    );

    testWidgets(
      'phone layout keeps the secret lock toggle on the key row '
      '(env editor)',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await pump(
          tester,
          const _SecretHarness(
            initialVars: {'TOKEN': 'abc123'},
            initialSecrets: {'TOKEN'},
          ),
        );

        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.byIcon(Icons.visibility), findsOneWidget);
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .any((f) => f.obscureText),
          isTrue,
          reason: 'the secret value stays obscured on the phone layout too',
        );
      },
    );

    testWidgets(
      'hovering a row applies the hover decoration and exit clears it',
      (tester) async {
        await pump(tester, const _EchoHarness(initial: {'Accept': '*/*'}));

        AnimatedContainer rowContainer() => tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('Accept'),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        Color? rowColor() =>
            (rowContainer().decoration as BoxDecoration?)?.color;
        final theme = Theme.of(tester.element(find.text('Accept')));

        expect(rowColor(), Colors.transparent);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: const Offset(750, 550));
        addTearDown(gesture.removePointer);
        await tester.pump();

        await gesture.moveTo(tester.getCenter(find.text('Accept')));
        await tester.pumpAndSettle();
        expect(rowColor(), theme.hoverColor);

        await gesture.moveTo(const Offset(750, 550));
        await tester.pumpAndSettle();
        expect(rowColor(), Colors.transparent);
      },
    );
  });
}

class _SecretHarness extends StatefulWidget {
  const _SecretHarness({
    required this.initialVars,
    required this.initialSecrets,
    this.onSecrets,
  });
  final Map<String, String> initialVars;
  final Set<String> initialSecrets;
  final void Function(Set<String>)? onSecrets;

  @override
  State<_SecretHarness> createState() => _SecretHarnessState();
}

class _SecretHarnessState extends State<_SecretHarness> {
  late Map<String, String> vars = widget.initialVars;
  late Set<String> secrets = widget.initialSecrets;

  @override
  Widget build(BuildContext context) {
    return KeyValueListEditor<Map<String, String>>(
      items: vars,
      decode: (map) => [for (final e in map.entries) (e.key, e.value)],
      encode: (rows) => {
        for (final (key, value) in rows)
          if (key.isNotEmpty) key: value,
      },
      equals: _mapEquality.equals,
      secretKeys: secrets,
      onChanged: (map) => setState(() => vars = map),
      onSecretKeysChanged: (s) {
        widget.onSecrets?.call(s);
        setState(() => secrets = s);
      },
    );
  }
}

class _ToggleHarness extends StatefulWidget {
  const _ToggleHarness({
    required this.initial,
    required this.initiallyDisabled,
    this.readOnlyWhenDisabled = false,
    this.onToggle,
  });
  final Map<String, String> initial;
  final Set<int> initiallyDisabled;
  final bool readOnlyWhenDisabled;
  // Positional `enabled` mirrors the widget's onToggleEnabled contract.
  // ignore: avoid_positional_boolean_parameters
  final void Function(int index, String key, String value, bool enabled)?
  onToggle;

  @override
  State<_ToggleHarness> createState() => _ToggleHarnessState();
}

class _ToggleHarnessState extends State<_ToggleHarness> {
  late Map<String, String> items = widget.initial;
  late Set<int> disabled = Set.of(widget.initiallyDisabled);

  @override
  Widget build(BuildContext context) {
    return KeyValueListEditor<Map<String, String>>(
      items: items,
      decode: (map) => [for (final e in map.entries) (e.key, e.value)],
      encode: (rows) => {
        for (final (key, value) in rows)
          if (key.isNotEmpty) key: value,
      },
      equals: _mapEquality.equals,
      rowEnabled: (index) => !disabled.contains(index),
      onToggleEnabled: (index, key, value, enabled) {
        widget.onToggle?.call(index, key, value, enabled);
        setState(() {
          enabled ? disabled.remove(index) : disabled.add(index);
        });
      },
      disabledRowsReadOnly: widget.readOnlyWhenDisabled,
      onChanged: (map) => setState(() => items = map),
    );
  }
}

/// Harness for the B2 affordances: applies reorder/duplicate to its canonical
/// map exactly the way a map-backed host (headers/env) does, and records the
/// callback arguments for assertions. Optional [disabledKeys] wires
/// `rowEnabled`/`onToggleEnabled` too, so a single harness covers the B1+B2
/// interaction (a disabled row's affordance gating).
class _ReorderDuplicateHarness extends StatefulWidget {
  const _ReorderDuplicateHarness({
    required this.initial,
    this.onReorderCalls,
    this.onDuplicateCalls,
    this.disabledKeys,
    this.orderedEquals = false,
    this.trimKeys = false,
  });
  final Map<String, String> initial;
  final List<(int, int)>? onReorderCalls;
  final List<int>? onDuplicateCalls;
  final Set<String>? disabledKeys;

  /// Mirrors the production hosts' order-SIGNIFICANT `equals` (headers/env)
  /// so a pure reorder echo triggers the editor's rebuild path instead of
  /// slipping past a plain MapEquality.
  final bool orderedEquals;

  /// Mirrors the env editor's encode, which trims keys (whitespace-only keys
  /// drop; keys equal after trim collapse onto the first occurrence).
  final bool trimKeys;

  @override
  State<_ReorderDuplicateHarness> createState() =>
      _ReorderDuplicateHarnessState();
}

class _ReorderDuplicateHarnessState extends State<_ReorderDuplicateHarness> {
  late Map<String, String> items = widget.initial;
  late Set<String> disabled = Set.of(widget.disabledKeys ?? const {});

  @override
  Widget build(BuildContext context) {
    final keys = items.keys.toList();
    return KeyValueListEditor<Map<String, String>>(
      items: items,
      fieldPrefix: 'kv',
      decode: (map) => [for (final e in map.entries) (e.key, e.value)],
      encode: widget.trimKeys
          ? (rows) => {
              for (final (key, value) in rows)
                if (key.trim().isNotEmpty) key.trim(): value,
            }
          : (rows) => {
              for (final (key, value) in rows)
                if (key.isNotEmpty) key: value,
            },
      equals: widget.orderedEquals ? _orderedMapEquals : _mapEquality.equals,
      onChanged: (map) => setState(() => items = map),
      rowEnabled: widget.disabledKeys == null
          ? null
          : (index) => index >= keys.length || !disabled.contains(keys[index]),
      onToggleEnabled: widget.disabledKeys == null
          ? null
          : (index, key, value, enabled) {
              setState(() {
                enabled ? disabled.remove(key) : disabled.add(key);
              });
            },
      onReorder: (oldIndex, newIndex) {
        widget.onReorderCalls?.add((oldIndex, newIndex));
        final entries = items.entries.toList();
        if (oldIndex < 0 || oldIndex >= entries.length) return;
        final entry = entries.removeAt(oldIndex);
        entries.insert(newIndex.clamp(0, entries.length), entry);
        setState(() => items = Map.fromEntries(entries));
      },
      onDuplicate: (index) {
        widget.onDuplicateCalls?.add(index);
        final entries = items.entries.toList();
        if (index < 0 || index >= entries.length) return;
        final source = entries[index];
        entries.insert(
          index + 1,
          MapEntry('${source.key}-copy', source.value),
        );
        setState(() => items = Map.fromEntries(entries));
      },
    );
  }
}

/// Params-mirror harness for the keyless-row reconcile: T is an ordered list
/// of (key, value, enabled) records whose equality is enabled-SIGNIFICANT —
/// exactly like `ParamRow.enabled` inside params' ListEquality — so a
/// checkbox toggle produces an echo that genuinely differs and forces
/// didUpdateWidget's full rebuild path (a map host's toggle leaves items
/// untouched and never rebuilds).
class _ParamsStyleToggleHarness extends StatefulWidget {
  const _ParamsStyleToggleHarness({required this.initial});
  final List<(String, String, bool)> initial;

  @override
  State<_ParamsStyleToggleHarness> createState() =>
      _ParamsStyleToggleHarnessState();
}

class _ParamsStyleToggleHarnessState extends State<_ParamsStyleToggleHarness> {
  static const ListEquality<(String, String, bool)> _rowsEquality =
      ListEquality<(String, String, bool)>();
  late List<(String, String, bool)> items = List.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return KeyValueListEditor<List<(String, String, bool)>>(
      items: items,
      fieldPrefix: 'kv',
      decode: (list) => [for (final r in list) (r.$1, r.$2)],
      encode: (rows) {
        // Re-attach enabled flags by key (params re-attaches via parked
        // matching); rows with new keys default to enabled.
        final flagByKey = {for (final r in items) r.$1: r.$3};
        return [
          for (final (key, value) in rows)
            if (key.isNotEmpty) (key, value, flagByKey[key] ?? true),
        ];
      },
      equals: _rowsEquality.equals,
      rowEnabled: (index) => index >= items.length || items[index].$3,
      onToggleEnabled: (index, key, value, enabled) => setState(() {
        items = [
          for (final (i, r) in items.indexed)
            i == index ? (r.$1, r.$2, enabled) : r,
        ];
      }),
      onChanged: (rows) => setState(() => items = rows),
    );
  }
}

/// List-backed host (params-style): duplicate keys are all real host rows —
/// locks `KeyValueHostIndexing.auto`'s list inference for non-Map items.
class _ListHostReorderHarness extends StatefulWidget {
  const _ListHostReorderHarness({required this.initial, this.onReorderCalls});
  final List<(String, String)> initial;
  final List<(int, int)>? onReorderCalls;

  @override
  State<_ListHostReorderHarness> createState() =>
      _ListHostReorderHarnessState();
}

class _ListHostReorderHarnessState extends State<_ListHostReorderHarness> {
  static const ListEquality<(String, String)> _rowsEquality =
      ListEquality<(String, String)>();
  late List<(String, String)> items = List.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return KeyValueListEditor<List<(String, String)>>(
      items: items,
      fieldPrefix: 'kv',
      decode: List.of,
      encode: (rows) => [
        for (final row in rows)
          if (row.$1.isNotEmpty) row,
      ],
      equals: _rowsEquality.equals,
      onChanged: (rows) => setState(() => items = rows),
      onReorder: (oldIndex, newIndex) {
        widget.onReorderCalls?.add((oldIndex, newIndex));
        if (oldIndex < 0 || oldIndex >= items.length) return;
        final next = List.of(items);
        final row = next.removeAt(oldIndex);
        next.insert(newIndex.clamp(0, next.length), row);
        setState(() => items = next);
      },
    );
  }
}
