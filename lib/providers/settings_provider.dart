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
    _save(state.copyWith(historyLimit: limit));
  }

  void updateSaveResponseInHistory(bool save) {
    _save(state.copyWith(saveResponseInHistory: save));
  }

  void updateDarkMode(bool isDark) {
    _save(state.copyWith(isDarkMode: isDark));
  }

  void updateCompactMode(bool isCompact) {
    _save(state.copyWith(isCompactMode: isCompact));
  }

  void updateVerticalLayout(bool isVertical) {
    _save(state.copyWith(isVerticalLayout: isVertical));
  }

  void updateSplitRatio(double ratio) {
    _save(state.copyWith(splitRatio: ratio));
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsModel>((ref) {
  return SettingsNotifier();
});
