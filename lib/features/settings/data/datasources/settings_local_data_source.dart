import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../models/settings_model.dart';

abstract class SettingsLocalDataSource {
  Future<SettingsModel> getSettings();
  Future<void> saveSettings(SettingsModel settings);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  Box<SettingsModel> _box() => Hive.box<SettingsModel>(HiveBoxes.settings);

  @override
  Future<SettingsModel> getSettings() async {
    try {
      return _box().get('current', defaultValue: SettingsModel())!;
    } catch (e) {
      throw PersistenceException('Failed to read settings', cause: e);
    }
  }

  @override
  Future<void> saveSettings(SettingsModel settings) async {
    try {
      await _box().put('current', settings);
    } catch (e) {
      throw PersistenceException('Failed to save settings', cause: e);
    }
  }
}
