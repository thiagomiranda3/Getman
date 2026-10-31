// Adversarial completion order, edits, repaint and disposal across async load.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/code_text_loader.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test(
    'prepared user replacement keeps undo and rejects obsolete work',
    () async {
      final controller = CodeLineEditingController.fromText('original');
      addTearDown(controller.dispose);
      final text = 'x' * 65536;
      expect(
        await replaceCodeText(controller, text, isCurrent: () => true),
        isTrue,
      );
      expect(controller.text, text);
      controller.undo();
      expect(controller.text, 'original');
      expect(
        await replaceCodeText(controller, text, isCurrent: () => false),
        isFalse,
      );
      expect(controller.text, 'original');
    },
  );

  test('obsolete replacement never touches a disposed controller', () async {
    final controller = CodeLineEditingController();
    final replacement = replaceCodeText(
      controller,
      'x' * 65536,
      isCurrent: () => false,
    );
    controller.dispose();
    expect(await replacement, isFalse);
  });

  test('worker prepares the whole document without emitting an edit', () async {
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    final ready = Completer<void>();
    final loader = CodeTextLoader(controller, ready.complete);
    addTearDown(loader.dispose);
    final edits = <String>[];
    controller.addListener(() {
      final edit = loader.takeEdit();
      if (edit != null) edits.add(edit);
    });
    final text = List.filled(10000, '{"key":1}').join('\n');
    loader.load(text);
    expect(loader.loading, isTrue);
    controller.forceRepaint(); // must not cancel the pending document
    await ready.future;
    expect(controller.text, text);
    expect(edits, isEmpty);
    expect(loader.loading, isFalse);
    controller.text = 'user edit';
    expect(edits, ['user edit']);
  });

  test('new model and user edits win over late completions', () async {
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    final pending = <Completer<CodeLines>>[];
    var ready = 0;
    final loader = CodeTextLoader(
      controller,
      () => ready++,
      prepare: (_) {
        final result = Completer<CodeLines>();
        pending.add(result);
        return result.future;
      },
    );
    addTearDown(loader.dispose);
    controller.addListener(loader.takeEdit);
    loader
      ..load('a' * 65536)
      ..load('b' * 65536);
    pending[1].complete('new'.codeLines);
    await Future<void>.delayed(Duration.zero);
    pending[0].complete('old'.codeLines);
    await Future<void>.delayed(Duration.zero);
    expect(controller.text, 'new');
    expect(ready, 1);
    loader.load('c' * 65536);
    controller.text = 'typed while pending';
    pending[2].complete('stale'.codeLines);
    await Future<void>.delayed(Duration.zero);
    expect(controller.text, 'typed while pending');
    expect(ready, 1);
  });

  test(
    'disposed loader ignores a completion and an error remains visible',
    () async {
      final controller = CodeLineEditingController();
      final pending = Completer<CodeLines>();
      CodeTextLoader(
          controller,
          () => fail('disposed callback'),
          prepare: (_) => pending.future,
        )
        ..load('x' * 65536)
        ..dispose();
      controller.dispose();
      pending.complete('late'.codeLines);
      await Future<void>.delayed(Duration.zero);

      final next = CodeLineEditingController();
      addTearDown(next.dispose);
      final failed = Completer<void>();
      final bad = CodeTextLoader(
        next,
        failed.complete,
        prepare: (_) => Future.error(StateError('cannot load')),
      );
      addTearDown(bad.dispose);
      bad.load('x' * 65536);
      await failed.future;
      expect(bad.error, isStateError);
      expect(bad.loading, isFalse);
    },
  );
}
