import 'package:hive_flutter/hive_flutter.dart';
import '../models/settings_model.dart';

abstract class SettingsLocalDataSource {
  Future<SettingsModel> getSettings();
  Future<void> saveSettings(SettingsModel settings);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  static const String settingsBoxName = 'settings';

  @override
  Future<SettingsModel> getSettings() async {
    final box = Hive.box<SettingsModel>(settingsBoxName);
    return box.get('current', defaultValue: SettingsModel())!;
  }

  @override
  Future<void> saveSettings(SettingsModel settings) async {
    final box = Hive.box<SettingsModel>(settingsBoxName);
    await box.put('current', settings);
  }
}
