import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';
import 'package:getman/features/tabs/presentation/bloc/body_field_dictionary_cubit.dart';
import 'package:getman/features/tabs/presentation/widgets/body_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

class _Dictionary implements BodyFieldDictionaryRepository {
  @override
  List<BodyFieldEntry> get entries => const [
    BodyFieldEntry(name: 'name', usageCount: 8),
    BodyFieldEntry(name: 'nationality', usageCount: 2),
  ];

  @override
  Future<void> recordUsage(Map<String, int> increments) async {}
}

Future<void> _insert(
  WidgetTester tester, {
  required String oldText,
  required String text,
  required int offset,
}) async {
  final caret = offset + text.length;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/textinput',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
        -1,
        <String, dynamic>{
          'deltas': <dynamic>[
            <String, dynamic>{
              'oldText': oldText,
              'deltaText': text,
              'deltaStart': offset,
              'deltaEnd': offset,
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
    ),
    (_) {},
  );
}

void main() {
  late CodeLineEditingController controller;
  late BodyFieldDictionaryCubit dictionary;
  var sent = 0;
  final controllers = <CodeLineEditingController>[];

  setUp(() {
    controller = createJsonCodeController();
    controllers.add(controller);
    dictionary = BodyFieldDictionaryCubit(_Dictionary());
    sent = 0;
  });

  Future<void> mount(
    WidgetTester tester, {
    String theme = 'brutalist',
    double width = 600,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: resolveTheme(theme)(Brightness.light),
        home: Scaffold(
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.enter,
                control: true,
              ): () =>
                  sent++,
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                  sent++,
            },
            child: SizedBox(
              width: width,
              height: 400,
              child: BodyCodeEditor(
                controller: controller,
                dictionary: dictionary,
                variableContext: LayeredVariableContext.empty,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> manual(WidgetTester tester) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.altLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  void cleanup(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      for (final item in controllers) {
        item.dispose();
      }
      controllers.clear();
      await dictionary.close();
    });
  }

  testWidgets(
    'typing an unquoted field opens suggestions and Tab adds quotes',
    (tester) async {
      cleanup(tester);
      controller.text = '{}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 1,
      );
      await tester.pump();
      await _insert(tester, oldText: '{}', text: 'na', offset: 1);
      await tester.pump();
      await tester.pump();
      expect(controller.text, '{na}');
      expect(find.text('name').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, '{"name": }');
      expect(controller.selection.extentOffset, 9);
      expect(find.text('name').hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'real typing opens suggestions and Tab replaces the key token',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text = '{"": 42}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );
      await tester.pump();
      await _insert(tester, oldText: '{"": 42}', text: 'na', offset: 2);
      await tester.pump();
      await tester.pump();
      expect(controller.text, '{"na": 42}');
      expect(find.text('name').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, '{"name": 42}');
      expect(controller.selection.extentOffset, 7);
      expect(find.text('name').hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'moving the caret cannot accept a stale completion before repaint',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text = '{"na": 42}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      await manual(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 9,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, contains('"na"'));
      expect(controller.text, isNot(contains('"name"')));
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'multiline acceptance preserves the body and can be undone',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text = '{\n  "na": 42,\n  "other": true\n}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 5,
      );
      await manual(tester);
      expect(find.text('name').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, '{\n  "name": 42,\n  "other": true\n}');
      expect(controller.selection.extentIndex, 1);
      expect(controller.selection.extentOffset, 8);
      controller.undo();
      await tester.pump();
      expect(controller.text, '{\n  "na": 42,\n  "other": true\n}');
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'send chord passes through and Escape stays dismissed',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text = '{"na": 42}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      await manual(tester);
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(sent, 1);
      expect(controller.text, '{"na": 42}');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('name').hitTestable(), findsNothing);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'completion after a folded object uses absolute document offsets',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text =
          '{\n  "nested": {\n    "other": true\n  },\n  "na": 42\n}';
      await mount(tester);
      controller.collapseChunk(1, 3);
      final field = controller.lineIndex2Index(4);
      controller.selection = CodeLineSelection.collapsed(
        index: field.index,
        offset: 5,
      );
      await manual(tester);
      expect(find.text('name').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        controller.text,
        '{\n  "nested": {\n    "other": true\n  },\n  "name": 42\n}',
      );
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'controller swap discards pending completion and old listeners',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text = '{"na": 42}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      await manual(tester);
      final old = controller;
      controller = createJsonCodeController()..text = '{"different": true}';
      controllers.add(controller);
      await mount(tester);
      expect(find.text('name').hitTestable(), findsNothing);
      old.text = '{"name": false}';
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.text, '{"different": true}');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'open completion survives theme switch and narrow resize',
    (
      tester,
    ) async {
      cleanup(tester);
      controller.text = '{"na": 42}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      await manual(tester);
      await mount(tester, theme: 'glass', width: 180);
      expect(tester.takeException(), isNull);
      expect(find.text('name').hitTestable(), findsOneWidget);
      await tester.tap(find.text('name').hitTestable());
      await tester.pump();
      expect(controller.text, '{"name": 42}');
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
