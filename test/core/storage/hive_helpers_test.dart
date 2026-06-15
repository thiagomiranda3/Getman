import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_helpers.dart';
import 'package:hive_ce/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockBox extends Mock implements Box<String> {}

void main() {
  group('replaceAllInBox (real box)', () {
    late Directory tempDir;
    late Box<String> box;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'getman_hive_helpers_test',
      );
      Hive.init(tempDir.path);
      box = await Hive.openBox<String>('replace_all_test');
      await box.addAll(['old1', 'old2']);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('replaces the box contents', () async {
      await replaceAllInBox(box, ['new1', 'new2', 'new3']);
      expect(box.values.toList(), ['new1', 'new2', 'new3']);
    });

    test(
      'materializes items before clearing, so values-derived input survives',
      () async {
        // A lazy iterable that reads the box would be emptied by an early
        // clear().
        await replaceAllInBox(box, box.values.map((v) => v.toUpperCase()));
        expect(box.values.toList(), ['OLD1', 'OLD2']);
      },
    );
  });

  group('replaceAllInBox (addAll failure)', () {
    test('restores the previous contents and rethrows', () async {
      final box = _MockBox();
      var addCalls = 0;
      when(() => box.values).thenReturn(['old1', 'old2']);
      when(box.clear).thenAnswer((_) async => 0);
      when(() => box.addAll(any())).thenAnswer((_) async {
        addCalls++;
        if (addCalls == 1) throw StateError('disk full');
        return <int>[];
      });

      await expectLater(replaceAllInBox(box, ['new']), throwsStateError);

      final captured = verify(() => box.addAll(captureAny())).captured;
      expect(captured.first, ['new']); // attempted write
      expect(captured.last, ['old1', 'old2']); // restored snapshot
    });
  });
}
