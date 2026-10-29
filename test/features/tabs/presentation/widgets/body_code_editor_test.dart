import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';
import 'package:getman/features/tabs/presentation/bloc/body_field_dictionary_cubit.dart';
import 'package:getman/features/tabs/presentation/widgets/body_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

class _Dictionary implements BodyFieldDictionaryRepository {
  final counts = <String, int>{'name': 8, 'nationality': 2};

  @override
  List<BodyFieldEntry> get entries => [
    for (final e in counts.entries)
      BodyFieldEntry(name: e.key, usageCount: e.value),
  ];

  @override
  Future<void> recordUsage(Map<String, int> increments) async {
    increments.forEach(
      (key, count) => counts.update(
        key,
        (value) => value + count,
        ifAbsent: () => count,
      ),
    );
  }
}

void main() {
  late CodeLineEditingController controller;
  late _Dictionary repository;
  late BodyFieldDictionaryCubit dictionary;

  setUp(() {
    controller = createJsonCodeController();
    repository = _Dictionary();
    dictionary = BodyFieldDictionaryCubit(repository);
  });

  tearDown(() async {
    controller.dispose();
    await dictionary.close();
  });

  Future<void> mount(WidgetTester tester, {bool offstage = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: Offstage(
            offstage: offstage,
            child: TickerMode(
              enabled: !offstage,
              child: SizedBox(
                width: 600,
                height: 400,
                child: BodyCodeEditor(
                  controller: controller,
                  dictionary: dictionary,
                  variableContext: const LayeredVariableContext(
                    environmentVariables: {'token': 'secret-value'},
                    environmentSecrets: {'token'},
                    environmentName: 'Production',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> complete(WidgetTester tester) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.altLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets(
    'manual completion ranks keys and inserts without losing value',
    (
      tester,
    ) async {
      controller.text = '{"na": 42}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      await complete(tester);
      expect(find.text('name').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, '{"name": 42}');
      expect(find.text('name').hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'learns added keys once and ignores caret moves and reopening',
    (
      tester,
    ) async {
      await mount(tester);
      controller.text = '{"accountId": 1, "nested": {"accountId": 2}}';
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.counts['accountId'], 2);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.counts['accountId'], 2);
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.counts['accountId'], 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'variable completion masks secrets and keeps paired braces',
    (
      tester,
    ) async {
      controller.text = '{"auth": "{{to}}"}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 13,
      );
      await complete(tester);
      expect(find.text('token').hitTestable(), findsOneWidget);
      expect(find.textContaining('secret-value'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, '{"auth": "{{token}}"}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'offstage edits do not leave a stale completion visible',
    (
      tester,
    ) async {
      controller.text = '{"na": 1}';
      await mount(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      await complete(tester);
      expect(find.text('name').hitTestable(), findsOneWidget);
      await mount(tester, offstage: true);
      controller.text = '{"value": true}';
      await tester.pump(const Duration(milliseconds: 300));
      await mount(tester);
      expect(find.text('name').hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );
  testWidgets(
    'incomplete edits do not inflate later field frequencies',
    (tester) async {
      await mount(tester);
      controller.text = '{"first": 1, "second": 2}';
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.counts['second'], 1);
      controller.text = '{"first: 1, "second": 2}';
      await tester.pump(const Duration(milliseconds: 300));
      controller.text = '{"first": 1, "second": 2}';
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(repository.counts['second'], 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'closing before debounce still retains a completed field',
    (tester) async {
      await mount(tester);
      controller.text = '{"quickField": 1}';
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.counts['quickField'], 1);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
