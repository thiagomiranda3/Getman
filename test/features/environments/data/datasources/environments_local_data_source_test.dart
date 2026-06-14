import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:hive/hive.dart';

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

  EnvironmentModel model(String id, String name) => EnvironmentModel(id: id, name: name);

  test('putEnvironment stores keyed by id and overwrites in place', () async {
    await dataSource.putEnvironment(model('a', 'Staging'));
    await dataSource.putEnvironment(model('a', 'Production')); // same id
    await dataSource.putEnvironment(model('b', 'Other'));

    expect(box.length, 2);
    expect(box.get('a')!.name, 'Production');
    expect((await dataSource.getEnvironments()).map((e) => e.id).toSet(), {'a', 'b'});
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

  test('migrateLegacyKeysIfNeeded re-keys int-keyed entries by id', () async {
    await box.addAll([model('a', 'A'), model('b', 'B')]); // legacy auto int keys
    expect(box.keys.every((k) => k is int), isTrue);

    await EnvironmentsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();

    expect(box.keys.toSet(), {'a', 'b'});
    // A subsequent put overwrites the migrated entry instead of duplicating it.
    await dataSource.putEnvironment(model('a', 'A2'));
    expect(box.length, 2);
    expect(box.get('a')!.name, 'A2');
  });
}
