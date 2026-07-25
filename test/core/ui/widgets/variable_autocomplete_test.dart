// test/core/ui/widgets/variable_autocomplete_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/utils/url_suggestion_source.dart';
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

  Future<void> pump(
    WidgetTester tester, {
    List<String> Function(String text)? urlSuggestionsFor,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: VariableAutocomplete(
            controller: controller,
            focusNode: focusNode,
            suggestionsFor: _suggest,
            urlSuggestionsFor: urlSuggestionsFor,
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

  testWidgets(
    'Ctrl+Space notifies onAccepted with the inserted {{}} token — '
    'regression guard (A3): the programmatic insert must reach the owner',
    (tester) async {
      String? accepted;
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: Scaffold(
            body: VariableAutocomplete(
              controller: controller,
              focusNode: focusNode,
              suggestionsFor: _suggest,
              onAccepted: (value) => accepted = value,
              child: TextField(controller: controller, focusNode: focusNode),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        accepted,
        '{{}}',
        reason:
            'onAccepted must fire with the controller text after the '
            'shortcut inserts the {{}} token, or the visible text never '
            'reaches the bloc',
      );
    },
  );

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

  group('URL suggestion mode (B4)', () {
    List<String> urlSuggest(String text) => buildUrlSuggestions(
      query: text,
      historyUrls: const [
        'https://api.dev/users',
        'https://api.dev/orders',
        'https://api.dev/users/all',
      ],
      collectionUrls: const ['https://saved.dev/items'],
    );

    testWidgets('3+ typed chars with no {{ token open URL suggestions', (
      tester,
    ) async {
      await pump(tester, urlSuggestionsFor: urlSuggest);
      await tester.enterText(find.byType(TextField), 'api');
      await tester.pumpAndSettle();
      expect(find.text('https://api.dev/users'), findsOneWidget);
      expect(find.text('https://api.dev/orders'), findsOneWidget);
    });

    testWidgets('fewer than 3 chars keep the menu closed', (tester) async {
      await pump(tester, urlSuggestionsFor: urlSuggest);
      await tester.enterText(find.byType(TextField), 'ap');
      await tester.pumpAndSettle();
      expect(find.text('https://api.dev/users'), findsNothing);
    });

    testWidgets('variable mode wins while the caret is inside a {{ token', (
      tester,
    ) async {
      await pump(
        tester,
        urlSuggestionsFor: (_) => const ['https://api.dev/users'],
      );
      await tester.enterText(find.byType(TextField), '{{ba');
      await tester.pumpAndSettle();
      expect(find.text('baseUrl'), findsOneWidget);
      expect(find.text('https://api.dev/users'), findsNothing);
    });

    testWidgets(
      // FIX I4: plain Enter (no arrow-navigation) in URL mode must NOT
      // accept a suggestion — the _EnterAcceptIntent action must report
      // itself disabled so Flutter's Actions/Shortcuts leaves the key
      // event unconsumed (per _GatedAction's contract, exercised
      // identically by every other gated intent in this widget; the
      // engine-level "does it then reach onSubmitted" hop is untestable
      // via sendKeyEvent — see EditableText.onSubmitted's own testing
      // note — so this asserts the proxy the widget actually controls:
      // no accept happened, the menu is still open). Regression guard for
      // the reviewer's exact trap: typing a URL that happens to prefix
      // another history entry must not have it silently rewritten.
      'Enter with no arrow-navigation does not accept — text and menu '
      'unchanged',
      (tester) async {
        await pump(tester, urlSuggestionsFor: urlSuggest);
        await tester.enterText(find.byType(TextField), 'api');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(
          controller.text,
          'api',
          reason: 'an unnavigated Enter must not rewrite the field',
        );
        expect(
          find.text('https://api.dev/users'),
          findsOneWidget,
          reason: 'the menu must still be open — Enter was not consumed',
        );
      },
    );

    testWidgets(
      'ArrowDown then Enter picks the second URL and onAccepted fires — '
      'FIX I4 (navigated Enter still accepts)',
      (tester) async {
        String? accepted;
        await tester.pumpWidget(
          MaterialApp(
            theme: brutalistTheme(Brightness.light),
            home: Scaffold(
              body: VariableAutocomplete(
                controller: controller,
                focusNode: focusNode,
                suggestionsFor: _suggest,
                urlSuggestionsFor: urlSuggest,
                onAccepted: (value) => accepted = value,
                child: TextField(controller: controller, focusNode: focusNode),
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'api');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(controller.text, 'https://api.dev/orders');
        expect(accepted, 'https://api.dev/orders');
      },
    );

    testWidgets(
      'Tab still accepts a URL suggestion with no navigation required — '
      'only Enter is gated (FIX I4)',
      (tester) async {
        await pump(tester, urlSuggestionsFor: urlSuggest);
        await tester.enterText(find.byType(TextField), 'api');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        expect(controller.text, 'https://api.dev/users');
      },
    );

    testWidgets('tapping a URL row accepts it', (tester) async {
      await pump(tester, urlSuggestionsFor: urlSuggest);
      await tester.enterText(find.byType(TextField), 'saved');
      await tester.pumpAndSettle();
      await tester.tap(find.text('https://saved.dev/items'));
      await tester.pumpAndSettle();
      expect(controller.text, 'https://saved.dev/items');
    });

    testWidgets(
      'Escape closes URL mode and stays closed until the text changes',
      (tester) async {
        await pump(tester, urlSuggestionsFor: urlSuggest);
        await tester.enterText(find.byType(TextField), 'api');
        await tester.pumpAndSettle();
        expect(find.text('https://api.dev/users'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('https://api.dev/users'), findsNothing);

        await tester.enterText(find.byType(TextField), 'api.');
        await tester.pumpAndSettle();
        expect(find.text('https://api.dev/users'), findsOneWidget);
      },
    );

    testWidgets(
      'dual mode: accepting a {{variable}} whose result matches a URL '
      'candidate does not reopen URL mode; a real text change re-enables '
      'it (regression)',
      (tester) async {
        // Realistic dual-mode config (the URL bar wires both callbacks):
        // one history URL is itself a {{var}} template, so the text left
        // behind by accepting the variable suggestion is a substring of it.
        List<String> dualModeUrlSuggest(String text) => buildUrlSuggestions(
          query: text,
          historyUrls: const ['{{baseUrl}}/users'],
          collectionUrls: const [],
        );

        await pump(tester, urlSuggestionsFor: dualModeUrlSuggest);
        await tester.enterText(find.byType(TextField), '{{');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(controller.text, '{{baseUrl}}');
        expect(
          find.text('{{baseUrl}}/users'),
          findsNothing,
          reason:
              'accepting a variable suggestion must not instantly reopen '
              'URL mode even though the resulting text matches a history '
              'URL — the latch must be pre-synced the same way as '
              '_acceptUrlAt',
        );

        // A genuine subsequent text change clears the latch — URL mode can
        // reopen normally.
        await tester.enterText(find.byType(TextField), '{{baseUrl}}/');
        await tester.pumpAndSettle();
        expect(find.text('{{baseUrl}}/users'), findsOneWidget);
      },
    );
  });
}
