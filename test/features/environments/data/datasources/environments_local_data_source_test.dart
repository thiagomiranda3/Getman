import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<EnvironmentModel> box;
  late EnvironmentsLocalDataSourceImpl dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_env_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(EnvironmentModelAdapter());
    }
    box = await Hive.openBox<EnvironmentModel>(HiveBoxes.environments);
    dataSource = EnvironmentsLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  EnvironmentModel model(String id, String name) =>
      EnvironmentModel(id: id, name: name);

  test('putEnvironment stores keyed by id and overwrites in place', () async {
    await dataSource.putEnvironment(model('a', 'Staging'));
    await dataSource.putEnvironment(model('a', 'Production')); // same id
    await dataSource.putEnvironment(model('b', 'Other'));

    expect(box.length, 2);
    expect(box.get('a')!.name, 'Production');
    expect((await dataSource.getEnvironments()).map((e) => e.id).toSet(), {
      'a',
      'b',
    });
  });

  test('deleteEnvironment removes one by id', () async {
    await dataSource.putEnvironment(model('a', 'A'));
    await dataSource.putEnvironment(model('b', 'B'));
    await dataSource.deleteEnvironment('a');

    expect(box.containsKey('a'), isFalse);
    expect((await dataSource.getEnvironments()).single.id, 'b');
  });

  test('saveEnvironments replaces the whole list, keyed by id', () async {
    await dataSource.putEnvironment(model('old', 'Old'));
    await dataSource.saveEnvironments([model('x', 'X'), model('y', 'Y')]);

    expect(box.keys.toSet(), {'x', 'y'});
  });

  // Regression: saveEnvironments used to be a destructive clear+putAll. The
  // chaining write-back (MergeEnvironmentVariables -> putEnvironment) can run
  // while an import's save is awaiting, and its keyed put landed in the
  // clear/putAll gap — erased by the clear, then overwritten by the stale
  // pre-merge snapshot — so captured variables silently vanished on restart.
  // These two tests interleave a putEnvironment with an in-flight
  // saveEnvironments and fail under the old clear+putAll implementation.
  group('saveEnvironments concurrent-write safety', () {
    test(
      'a putEnvironment interleaved with an in-flight saveEnvironments '
      'survives the replace (chaining write-back vs import race)',
      () async {
        // Active environment on disk, pre-merge.
        await dataSource.putEnvironment(model('active', 'Active'));

        // The import persists a whole-list snapshot still holding the
        // PRE-merge copy of 'active'. Start it but don't await, so the put
        // below lands while the replace is in flight — exactly where the
        // chaining write-back can run.
        final save = dataSource.saveEnvironments([
          model('active', 'Active'),
          model('imported', 'Imported'),
        ]);
        final merged = EnvironmentModel(
          id: 'active',
          name: 'Active',
          variables: const {'token': 'captured'},
        );
        final concurrentPut = dataSource.putEnvironment(merged);
        await Future.wait([save, concurrentPut]);

        // The merged write must win: clear+putAll wiped it (clear emptied the
        // box under it, putAll re-wrote the pre-merge copy).
        expect(box.get('active')!.variables['token'], 'captured');
        expect(box.keys.toSet(), {'active', 'imported'});
      },
    );

    test(
      'a NEW environment put during an in-flight saveEnvironments is neither '
      'cleared nor swept by the removed-keys phase',
      () async {
        await dataSource.putEnvironment(model('stale', 'Stale'));

        final save = dataSource.saveEnvironments([model('x', 'X')]);
        final concurrentPut = dataSource.putEnvironment(
          model('fresh', 'Fresh'),
        );
        await Future.wait([save, concurrentPut]);

        // 'stale' (absent from the new list) is removed; 'fresh' (put after
        // the save started, so absent from its removed-keys snapshot) stays.
        expect(box.keys.toSet(), {'x', 'fresh'});
      },
    );
  });

  test(
    'getEnvironments returns entries sorted case-insensitively by name, '
    'independent of Hive key order',
    () async {
      // Keys are UUIDs (post key-migration) so Hive's own key-lexicographic
      // order is unrelated to display order; insertion order here is
      // deliberately neither alphabetical nor key-sorted.
      await dataSource.putEnvironment(model('zzz-key', 'banana'));
      await dataSource.putEnvironment(model('aaa-key', 'Apple'));
      await dataSource.putEnvironment(model('mmm-key', 'cherry'));

      final names = (await dataSource.getEnvironments())
          .map((e) => e.name)
          .toList();
      expect(names, ['Apple', 'banana', 'cherry']);
    },
  );

  test('migrateLegacyKeysIfNeeded re-keys int-keyed entries by id', () async {
    await box.addAll([
      model('a', 'A'),
      model('b', 'B'),
    ]); // legacy auto int keys
    expect(box.keys.every((k) => k is int), isTrue);

    await EnvironmentsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();

    expect(box.keys.toSet(), {'a', 'b'});
    // A subsequent put overwrites the migrated entry instead of duplicating it.
    await dataSource.putEnvironment(model('a', 'A2'));
    expect(box.length, 2);
    expect(box.get('a')!.name, 'A2');
  });
}
