import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings_model.dart';
import '../services/storage_service.dart';

class SettingsNotifier extends StateNotifier<SettingsModel> {
  SettingsNotifier() : super(StorageService.getSettings());

  void updateHistoryLimit(int limit) {
    state = SettingsModel(
      historyLimit: limit,
      saveResponseInHistory: state.saveResponseInHistory,
    );
    StorageService.saveSettings(state);
  }

  void updateSaveResponseInHistory(bool save) {
    state = SettingsModel(
      historyLimit: state.historyLimit,
      saveResponseInHistory: save,
    );
    StorageService.saveSettings(state);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsModel>((ref) {
  return SettingsNotifier();
});
