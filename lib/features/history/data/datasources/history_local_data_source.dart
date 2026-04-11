import 'package:hive_flutter/hive_flutter.dart';
import '../models/request_config_model.dart';

abstract class HistoryLocalDataSource {
  Future<List<HttpRequestConfig>> getHistory();
  Future<void> saveHistory(List<HttpRequestConfig> history);
  Future<void> addToHistory(HttpRequestConfig config, int limit);
  Future<void> clearHistory();
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  static const String historyBoxName = 'history';

  Future<Box<HttpRequestConfig>> _getBox() async {
    if (Hive.isBoxOpen(historyBoxName)) {
      return Hive.box<HttpRequestConfig>(historyBoxName);
    }
    return await Hive.openBox<HttpRequestConfig>(historyBoxName);
  }

  @override
  Future<List<HttpRequestConfig>> getHistory() async {
    final box = await _getBox();
    return box.values.toList();
  }

  @override
  Future<void> saveHistory(List<HttpRequestConfig> history) async {
    final box = await _getBox();
    await box.clear();
    await box.addAll(history);
  }

  @override
  Future<void> addToHistory(HttpRequestConfig config, int limit) async {
    final box = await _getBox();
    final history = box.values.toList();
    
    // Remove if already exists (bring to top)
    final existingIndex = history.indexWhere((item) => 
      item.method == config.method && 
      item.url == config.url && 
      item.body == config.body
    );
    
    if (existingIndex != -1) {
      await box.deleteAt(existingIndex);
    }
    
    await box.add(config);
    
    // Trim
    if (box.length > limit) {
      await box.deleteAt(0);
    }
  }

  @override
  Future<void> clearHistory() async {
    final box = await _getBox();
    await box.clear();
  }
}
