import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/request_config.dart';
import '../services/storage_service.dart';
import 'settings_provider.dart';

class HistoryNotifier extends StateNotifier<List<HttpRequestConfig>> {
  final Ref ref;

  HistoryNotifier(this.ref) : super(StorageService.getHistory());

  void addRequest(HttpRequestConfig config) {
    final settings = ref.read(settingsProvider);
    final newList = [config, ...state];
    
    // Apply limit
    if (newList.length > settings.historyLimit) {
      state = newList.sublist(0, settings.historyLimit);
    } else {
      state = newList;
    }
    
    StorageService.saveHistory(state);
  }

  void clearHistory() {
    state = [];
    StorageService.saveHistory(state);
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, List<HttpRequestConfig>>((ref) {
  return HistoryNotifier(ref);
});
