import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/cookies/data/hive_cookie_persistence.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<StoredCookieModel> box;
  late HiveCookiePersistence persistence;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_cookie_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(StoredCookieModelAdapter());
    }
    box = await Hive.openBox<StoredCookieModel>(HiveBoxes.cookies);
    persistence = HiveCookiePersistence();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  NetworkCookie cookie(
    String name,
    String value, {
    String domain = 'api.dev',
  }) => NetworkCookie(name: name, value: value, domain: domain);

  test(
    'upsert stores keyed by domain|path|name and overwrites in place',
    () async {
      await persistence.upsert(cookie('sid', 'one'));
      await persistence.upsert(cookie('sid', 'two')); // same key
      await persistence.upsert(cookie('other', 'x'));

      expect(box.length, 2, reason: 'same-key upsert overwrites, not appends');
      expect(box.get('api.dev|/|sid')!.value, 'two');
      expect(box.get('api.dev|/|other')!.value, 'x');
      expect(persistence.loadAll().map((c) => '${c.name}=${c.value}').toSet(), {
        'sid=two',
        'other=x',
      });
    },
  );

  test('remove deletes a single cookie by key', () async {
    await persistence.upsert(cookie('sid', 'one'));
    await persistence.upsert(cookie('keep', 'y'));
    await persistence.remove('api.dev|/|sid');

    expect(box.containsKey('api.dev|/|sid'), isFalse);
    expect(persistence.loadAll().single.name, 'keep');
  });

  test(
    'migrateLegacyKeysIfNeeded re-keys int-keyed entries by cookie key',
    () async {
      // Legacy layout: auto-increment int keys (the old whole-jar addAll
      // style).
      await box.addAll([
        StoredCookieModel.fromCookie(cookie('a', '1')),
        StoredCookieModel.fromCookie(cookie('b', '2')),
      ]);
      expect(box.keys.every((k) => k is int), isTrue);

      await HiveCookiePersistence.migrateLegacyKeysIfNeeded();

      expect(box.keys.toSet(), {'api.dev|/|a', 'api.dev|/|b'});
      // A subsequent upsert with the same key now overwrites the migrated
      // entry.
      await persistence.upsert(cookie('a', '99'));
      expect(box.length, 2);
      expect(box.get('api.dev|/|a')!.value, '99');
    },
  );

  test(
    'migrateLegacyKeysIfNeeded is a no-op when keys are already strings',
    () async {
      await persistence.upsert(cookie('a', '1'));
      final before = box.toMap();
      await HiveCookiePersistence.migrateLegacyKeysIfNeeded();
      expect(box.toMap().keys, before.keys);
    },
  );
}
