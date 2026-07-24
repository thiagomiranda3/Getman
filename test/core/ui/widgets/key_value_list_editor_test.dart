import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/utils/layered_variable_context.dart';

const _mapEquality = MapEquality<String, String>();

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
