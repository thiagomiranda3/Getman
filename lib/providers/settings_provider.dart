import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../services/storage_service.dart';

class SettingsNotifier extends StateNotifier<SettingsModel> {
  SettingsNotifier() : super(StorageService.getSettings());

  void _save(SettingsModel newSettings) {
    state = newSettings;
    StorageService.saveSettings(state);
  }

  void updateHistoryLimit(int limit) {
    _save(SettingsModel(
      historyLimit: limit,
      saveResponseInHistory: state.saveResponseInHistory,
      isDarkMode: state.isDarkMode,
    ));
  }

  void updateSaveResponseInHistory(bool save) {
    _save(SettingsModel(
      historyLimit: state.historyLimit,
      saveResponseInHistory: save,
      isDarkMode: state.isDarkMode,
    ));
  }

  void updateDarkMode(bool isDark) {
    _save(SettingsModel(
      historyLimit: state.historyLimit,
      saveResponseInHistory: state.saveResponseInHistory,
      isDarkMode: isDark,
    ));
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsModel>((ref) {
  return SettingsNotifier();
});
