import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_helpers.dart';
import 'package:hive_ce/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockBox extends Mock implements Box<String> {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, String>{});
    registerFallbackValue(<dynamic>[]);
  });

  group('replaceAllKeyedInBox (real box)', () {
    late Directory tempDir;
    late Box<String> box;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'getman_hive_helpers_test',
      );
      Hive.init(tempDir.path);
      box = await Hive.openBox<String>('replace_all_keyed_test');
      await box.putAll({'a': 'old-a', 'b': 'old-b'});
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('upserts new entries and deletes stale keys', () async {
      await replaceAllKeyedInBox(box, {'a': 'new-a', 'c': 'new-c'});

      expect(box.toMap(), {'a': 'new-a', 'c': 'new-c'});
    });

    test('an empty replacement empties the box', () async {
      await replaceAllKeyedInBox(box, <String, String>{});

      expect(box.isEmpty, isTrue);
    });
  });

  group('replaceAllKeyedInBox (failure ordering)', () {
    test('a failing putAll leaves the old entries intact: no clear, '
        'no deleteAll, rethrows', () async {
      final box = _MockBox();
      when(() => box.keys).thenReturn(['a', 'b']);
      when(() => box.putAll(any())).thenThrow(StateError('disk full'));

      await expectLater(
        replaceAllKeyedInBox(box, {'c': 'new-c'}),
        throwsStateError,
      );

      // The old-data-destroying calls must never have run.
      verifyNever(box.clear);
      verifyNever(() => box.deleteAll(any()));
    });

    test('happy path: putAll first, then deleteAll of only the stale keys, '
        'never clear', () async {
      final box = _MockBox();
      when(() => box.keys).thenReturn(['a', 'stale']);
      when(() => box.putAll(any())).thenAnswer((_) async {});
      when(() => box.deleteAll(any())).thenAnswer((_) async {});

      await replaceAllKeyedInBox(box, {'a': 'new-a'});

      final put = verify(() => box.putAll(captureAny())).captured.single;
      expect(put, {'a': 'new-a'});
      final deleted = verify(() => box.deleteAll(captureAny())).captured.single;
      expect(deleted, ['stale']);
      verifyNever(box.clear);
    });
  });
}
