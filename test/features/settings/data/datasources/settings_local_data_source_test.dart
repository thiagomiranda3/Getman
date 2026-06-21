import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/settings/data/datasources/settings_local_data_source.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late SettingsLocalDataSourceImpl ds;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_settings_ds_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SettingsModelAdapter());
    }
    await Hive.openBox<SettingsModel>(HiveBoxes.settings);
    ds = SettingsLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'getSettings returns a default SettingsModel when box is empty',
    () async {
      final s = await ds.getSettings();
      expect(s, isA<SettingsModel>());
    },
  );

  test('saveSettings then getSettings round-trips the value', () async {
    final model = SettingsModel()..themeId = 'rpg';
    await ds.saveSettings(model);

    final loaded = await ds.getSettings();
    expect(loaded.themeId, 'rpg');
  });

  test('getSettings wraps a Hive failure in PersistenceException', () async {
    // Closing the box makes Hive.box(...) throw inside the try/catch.
    await Hive.box<SettingsModel>(HiveBoxes.settings).close();
    expect(ds.getSettings, throwsA(isA<PersistenceException>()));
  });
}
