import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_code_autocomplete.dart';
import 'package:re_editor/re_editor.dart';

/// Drives a real insertion delta into the focused re_editor.
///
/// re_editor is a [DeltaTextInputClient] (`enableDeltaModel: true`) whose
/// plain `updateEditingValue` is a no-op — only `updateEditingValueWithDeltas`
/// applies text and triggers the autocomplete. `tester.testTextInput.enterText`
/// sends the plain (non-delta) message, so we hand-build the delta platform
/// message here. Client id `-1` is the framework's magic test id that bypasses
/// the connection-id check.
Future<void> sendInsertionDelta(
  WidgetTester tester, {
  required String oldText,
  required String deltaText,
  required int insertAt,
  required int caret,
}) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
      -1,
      <String, dynamic>{
        'deltas': <dynamic>[
          <String, dynamic>{
            'oldText': oldText,
            'deltaText': deltaText,
            'deltaStart': insertAt,
            'deltaEnd': insertAt,
            'selectionBase': caret,
            'selectionExtent': caret,
            'selectionAffinity': 'TextAffinity.downstream',
            'selectionIsDirectional': false,
            'composingBase': -1,
            'composingExtent': -1,
          },
        ],
      },
    ]),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/textinput',
    message,
    (_) {},
  );
}

void main() {
  const ctx = LayeredVariableContext(
    environmentVariables: {'host': 'example.com', 'token': 'abc'},
    environmentName: 'Staging',
  );

  group('variablePromptsFor', () {
    test('returns suggestions for an open {{ token', () {
      final r = variablePromptsFor(ctx, '{{ho', 4);
      expect(r, isNotNull);
      expect(r!.input, 'ho');
      expect(r.hasClosingBraces, isFalse);
      expect(r.suggestions.map((s) => s.name), contains('host'));
    });

    test('returns null when caret is not in a {{ token', () {
      expect(variablePromptsFor(ctx, 'plain text', 5), isNull);
    });

    test('detects already-present closing braces', () {
      // Caret between `{{` and `}}` at offset 4 ('{{ho}}').
      final r = variablePromptsFor(ctx, '{{ho}}', 4);
      expect(r, isNotNull);
      expect(r!.hasClosingBraces, isTrue);
    });
  });

  group('variableInsertionWord', () {
    test('appends closing braces when not already present', () {
      expect(variableInsertionWord('host', hasClosingBraces: false), 'host}}');
    });

    test('keeps the bare name when braces already present', () {
      expect(variableInsertionWord('host', hasClosingBraces: true), 'host');
    });
  });

  group('VariablePromptsBuilder.build', () {
    final builder = VariablePromptsBuilder(() => ctx);

    testWidgets('produces a CodeAutocompleteEditingValue for {{ho', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final value = builder.build(
        capturedContext,
        const CodeLine('{{ho'),
        const CodeLineSelection.collapsed(index: 0, offset: 4),
      );
      expect(value, isNotNull);
      expect(value!.input, 'ho');
      expect(value.prompts, isNotEmpty);
      expect(
        value.prompts.map((p) => p.word),
        contains('host'),
      );
    });

    testWidgets('returns null on a non-collapsed selection', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final value = builder.build(
        capturedContext,
        const CodeLine('{{ho'),
        const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 2,
          extentIndex: 0,
          extentOffset: 4,
        ),
      );
      expect(value, isNull);
    });
  });

  group('wrapBodyWithVariableAutocomplete', () {
    testWidgets('returns the child unchanged when the context is empty', (
      tester,
    ) async {
      const child = SizedBox(key: Key('body-child'));
      final wrapped = wrapBodyWithVariableAutocomplete(
        contextProvider: () => LayeredVariableContext.empty,
        child: child,
      );
      expect(identical(wrapped, child), isTrue);
    });

    testWidgets('wraps with CodeAutocomplete when variables exist', (
      tester,
    ) async {
      const child = SizedBox(key: Key('body-child'));
      final wrapped = wrapBodyWithVariableAutocomplete(
        contextProvider: () => ctx,
        child: child,
      );
      expect(wrapped, isA<CodeAutocomplete>());
    });

    testWidgets('shows the suggestion overlay and inserts {{host}}', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme('brutalist')(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: wrapBodyWithVariableAutocomplete(
                contextProvider: () => ctx,
                child: CodeEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the editor so it attaches a text-input connection.
      await tester.tap(find.byType(CodeEditor));
      await tester.pumpAndSettle();

      // Type `{{ho` via a real insertion delta (the path re_editor honors).
      await sendInsertionDelta(
        tester,
        oldText: '',
        deltaText: '{{ho',
        insertAt: 0,
        caret: 4,
      );
      // The autocomplete update is fired 50ms after user input.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(controller.text, '{{ho');
      expect(find.text('host'), findsOneWidget);

      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();

      expect(controller.text, '{{host}}');
    });

    testWidgets(
      'accepts host without doubling braces when closing braces present',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: resolveTheme('brutalist')(Brightness.light),
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: wrapBodyWithVariableAutocomplete(
                  contextProvider: () => ctx,
                  child: CodeEditor(controller: controller),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Focus the editor so it attaches a text-input connection.
        await tester.tap(find.byType(CodeEditor));
        await tester.pumpAndSettle();

        // Establish `{{}}` in the editor with the caret at offset 2 (between
        // the braces) — simulates the user already having `{{}}` and moving
        // the caret inside it.
        await sendInsertionDelta(
          tester,
          oldText: '',
          deltaText: '{{}}',
          insertAt: 0,
          caret: 2,
        );
        // Brief pump — do NOT wait the 60 ms autocomplete timer yet.
        await tester.pump(const Duration(milliseconds: 5));

        // Now type `ho` at position 2 (between `{{` and `}}`).
        await sendInsertionDelta(
          tester,
          oldText: '{{}}',
          deltaText: 'ho',
          insertAt: 2,
          caret: 4,
        );
        // Wait for the 50 ms autocomplete debounce.
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        expect(controller.text, '{{ho}}');
        expect(find.text('host'), findsOneWidget);

        // Accepting must yield `{{host}}`, NOT the doubled `{{host}}}}`.
        await tester.tap(find.text('host'));
        await tester.pumpAndSettle();

        expect(controller.text, '{{host}}');
      },
    );
  });
}
