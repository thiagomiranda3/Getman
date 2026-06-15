import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/data/models/saved_example_model.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/tabs/data/models/multipart_field_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<CollectionNode> box;
  late CollectionsLocalDataSourceImpl dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'getman_collections_ds_test',
    );
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(HttpRequestConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(CollectionNodeAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MultipartFieldModelAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(SavedExampleModelAdapter());
    }
    box = await Hive.openBox<CollectionNode>(HiveBoxes.collections);
    dataSource = CollectionsLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  CollectionNode node(String id, String name) =>
      CollectionNode(id: id, name: name);

  test('saveCollections writes each root keyed by id', () async {
    await dataSource.saveCollections([node('a', 'A'), node('b', 'B')]);

    expect(box.keys.toSet(), {'a', 'b'});
    expect((await dataSource.getCollections()).map((n) => n.id).toSet(), {
      'a',
      'b',
    });
  });

  test('saveCollections clears roots that are no longer present', () async {
    await dataSource.saveCollections([node('a', 'A'), node('b', 'B')]);
    await dataSource.saveCollections([node('a', 'A')]);

    expect(box.keys.toSet(), {'a'});
  });

  test('putRoots upserts by id without touching other roots', () async {
    await dataSource.saveCollections([node('a', 'A'), node('b', 'B')]);
    await dataSource.putRoots([node('a', 'A-renamed'), node('c', 'C')]);

    expect(box.keys.toSet(), {'a', 'b', 'c'});
    expect(box.get('a')!.name, 'A-renamed');
    expect(box.get('b')!.name, 'B');
  });

  test('deleteRoots removes only the given ids', () async {
    await dataSource.saveCollections([
      node('a', 'A'),
      node('b', 'B'),
      node('c', 'C'),
    ]);
    await dataSource.deleteRoots(['a', 'c']);

    expect(box.keys.toSet(), {'b'});
  });

  test('migrateLegacyKeysIfNeeded re-keys int-keyed roots by node '
      'id', () async {
    await box.addAll([node('a', 'A'), node('b', 'B')]); // legacy auto int keys
    expect(box.keys.every((k) => k is int), isTrue);

    await CollectionsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();

    expect(box.keys.toSet(), {'a', 'b'});
    // A subsequent put overwrites the migrated entry instead of duplicating it.
    await dataSource.putRoots([node('a', 'A2')]);
    expect(box.length, 2);
    expect(box.get('a')!.name, 'A2');
  });
}
