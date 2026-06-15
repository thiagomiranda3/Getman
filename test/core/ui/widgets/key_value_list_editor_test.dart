import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';

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
