// test/core/ui/widgets/variable_autocomplete_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

ResolvedVariable _classify(String name) => ResolvedVariable(
  name: name,
  kind: VariableValueKind.resolved,
  value: 'v-$name',
  environmentName: 'Dev',
);

List<VariableSuggestion> _suggest(String q) => buildVariableSuggestions(
  query: q,
  userVariableNames: const ['baseUrl', 'token', 'userId'],
  classify: _classify,
  includeDynamics: false,
);

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: VariableAutocomplete(
            controller: controller,
            focusNode: focusNode,
            suggestionsFor: _suggest,
            child: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );
  }

  testWidgets('typing "{{" opens the menu with all suggestions', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
    expect(find.text('token'), findsOneWidget);
    expect(find.text('userId'), findsOneWidget);
  });

  testWidgets('typing filters the menu', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{to');
    await tester.pumpAndSettle();
    expect(find.text('token'), findsOneWidget);
    expect(find.text('baseUrl'), findsNothing);
  });

  testWidgets('Enter inserts the selected suggestion with closing braces', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '{{baseUrl}}');
    expect(controller.selection.baseOffset, '{{baseUrl}}'.length);
  });

  testWidgets('ArrowDown then Enter inserts the second suggestion', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '{{token}}');
  });

  testWidgets('Escape closes the menu and does not reopen on the same text', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsNothing);
  });

  testWidgets('tapping a row inserts it', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.tap(find.text('userId'));
    await tester.pumpAndSettle();
    expect(controller.text, '{{userId}}');
  });

  testWidgets('Ctrl+Space opens the menu on an empty field', (tester) async {
    await pump(tester);
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
  });

  testWidgets('Tab accepts the first suggestion, same as Enter', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, '{{baseUrl}}');
  });

  testWidgets('secret variable value is masked with bullets', (tester) async {
    final secretController = TextEditingController();
    final secretFocusNode = FocusNode();
    addTearDown(() {
      secretController.dispose();
      secretFocusNode.dispose();
    });

    final secretSuggestion = [
      const VariableSuggestion(
        name: 'apiKey',
        classification: ResolvedVariable(
          name: 'apiKey',
          kind: VariableValueKind.secret,
          value: 'shh',
          environmentName: 'Dev',
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: VariableAutocomplete(
            controller: secretController,
            focusNode: secretFocusNode,
            suggestionsFor: (_) => secretSuggestion,
            child: TextField(
              controller: secretController,
              focusNode: secretFocusNode,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('••••'), findsOneWidget);
    expect(find.text('shh'), findsNothing);
  });

  testWidgets(
    'onAccepted fires with full text after Enter; not when menu merely opens',
    (tester) async {
      String? accepted;
      var acceptedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: VariableAutocomplete(
              controller: controller,
              focusNode: focusNode,
              suggestionsFor: _suggest,
              onAccepted: (value) {
                accepted = value;
                acceptedCount++;
              },
              child: TextField(controller: controller, focusNode: focusNode),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '{{');
      await tester.pumpAndSettle();

      // Menu is open — onAccepted must NOT have been called yet.
      expect(
        acceptedCount,
        0,
        reason: 'opening the menu must not fire onAccepted',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.text, '{{baseUrl}}');
      expect(
        acceptedCount,
        1,
        reason: 'Enter must fire onAccepted exactly once',
      );
      expect(accepted, '{{baseUrl}}');
    },
  );

  testWidgets('Esc latch: stays closed on caret move, reopens on text change', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsNothing);

    // Half A: caret move with no text change — latch holds, menu stays closed.
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(find.text('baseUrl'), findsNothing);

    // Half B: text change clears the latch — menu reopens and filters on 'b'.
    await tester.enterText(find.byType(TextField), '{{b');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);
  });

  testWidgets('the open menu is wrapped in a TextFieldTapRegion so a tap '
      'inside it is not treated as a tap-outside', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '{{');
    await tester.pumpAndSettle();
    expect(find.text('baseUrl'), findsOneWidget);

    // The overlay must be grouped with the field's tap region; otherwise a
    // pointer-down anywhere on the dropdown unfocuses the field (desktop
    // tap-outside behavior) and closes the menu before a row tap can land.
    expect(
      find.ancestor(
        of: find.text('baseUrl'),
        matching: find.byType(TextFieldTapRegion),
      ),
      findsOneWidget,
    );
  });
}
