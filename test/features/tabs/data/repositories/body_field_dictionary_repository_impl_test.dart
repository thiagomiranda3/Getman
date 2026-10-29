import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/tabs/data/repositories/body_field_dictionary_repository_impl.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:hive_ce/hive.dart';
import 'package:mocktail/mocktail.dart';

class _FailingBox extends Mock implements Box<int> {}

void main() {
  late Directory directory;
  late Box<int> box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('body_dictionary_test');
    Hive.init(directory.path);
    box = await Hive.openBox<int>('dictionary');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'persists names and cumulative counts across closing and reopening',
    () async {
      final repository = BodyFieldDictionaryRepositoryImpl(box);
      await repository.recordUsage({'name': 2, 'email': 1});
      await repository.recordUsage({'email': 2});
      await box.close();
      box = await Hive.openBox<int>('dictionary');
      final reopened = BodyFieldDictionaryRepositoryImpl(box);
      expect(reopened.entries, const [
        BodyFieldEntry(name: 'email', usageCount: 3),
        BodyFieldEntry(name: 'name', usageCount: 2),
      ]);
    },
  );

  test('rejects names beyond Hive UTF-8 key capacity before writing', () async {
    final repository = BodyFieldDictionaryRepositoryImpl(box);
    final atLimit = List.filled(85, '名').join();
    final tooLong = List.filled(86, '名').join();
    await repository.recordUsage({atLimit: 1, tooLong: 1});
    await box.close();
    box = await Hive.openBox<int>('dictionary');
    expect(box.toMap(), {atLimit: 1});
  });

  test('serializes concurrent increments without losing counts', () async {
    final repository = BodyFieldDictionaryRepositoryImpl(box);
    await Future.wait([
      for (var i = 0; i < 30; i++) repository.recordUsage({'name': 1}),
    ]);
    expect(repository.entries.single.usageCount, 30);
    expect(box.get('name'), 30);
  });

  test('ranks frequency first and lexical name for equal counts', () async {
    final repository = BodyFieldDictionaryRepositoryImpl(box);
    await repository.recordUsage({'zebra': 2, 'alpha': 2, 'often': 5});
    expect(repository.entries.map((entry) => entry.name), [
      'often',
      'alpha',
      'zebra',
    ]);
  });

  test('bounds storage and ignores invalid increments', () async {
    final repository = BodyFieldDictionaryRepositoryImpl(box);
    await repository.recordUsage({
      for (var i = 0; i < 2100; i++) 'key$i': 1,
      'popular': 10,
      '': 5,
      List.filled(257, 'x').join(): 5,
      'negative': -2,
      'zero': 0,
      'huge': 2000000000,
    });
    expect(box.length, 2000);
    expect(box.get('huge'), 1000000000);
    expect(box.get('popular'), 10);
    expect(box.containsKey('negative'), isFalse);
    expect(box.containsKey('zero'), isFalse);
    expect(box.containsKey(''), isFalse);
  });

  test(
    'failed write surfaces a domain failure and next write recovers',
    () async {
      final failingBox = _FailingBox();
      when(() => failingBox.keys).thenReturn(<String>[]);
      when(failingBox.toMap).thenReturn(<dynamic, int>{});
      var fail = true;
      when(() => failingBox.putAll(any())).thenAnswer((_) async {
        if (fail) {
          fail = false;
          throw const FileSystemException('disk full');
        }
      });
      final repository = BodyFieldDictionaryRepositoryImpl(failingBox);
      await expectLater(
        repository.recordUsage({'name': 1}),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(repository.entries, isEmpty);
      await repository.recordUsage({'name': 2});
      expect(repository.entries, const [
        BodyFieldEntry(name: 'name', usageCount: 2),
      ]);
    },
  );
}
