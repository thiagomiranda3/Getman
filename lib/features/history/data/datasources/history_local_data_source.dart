import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../../../../core/storage/hive_helpers.dart';
import '../models/request_config_model.dart';

abstract class HistoryLocalDataSource {
  Future<List<HttpRequestConfig>> getHistory();
  Future<void> saveHistory(List<HttpRequestConfig> history);
  Future<void> addToHistory(HttpRequestConfig config, int limit);
  Future<void> clearHistory();
  Stream<void> watch();
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  Box<HttpRequestConfig> _box() => Hive.box<HttpRequestConfig>(HiveBoxes.history);

  @override
  Future<List<HttpRequestConfig>> getHistory() async {
    try {
      return _box().values.toList();
    } catch (e) {
      throw PersistenceException('Failed to read history', cause: e);
    }
  }

  @override
  Future<void> saveHistory(List<HttpRequestConfig> history) async {
    try {
      await replaceAllInBox(_box(), history);
    } catch (e) {
      throw PersistenceException('Failed to save history', cause: e);
    }
  }

  @override
  Future<void> addToHistory(HttpRequestConfig config, int limit) async {
    try {
      final box = _box();
      final history = box.values.toList();

      final existingIndex = history.indexWhere((item) =>
        item.method == config.method &&
        item.url == config.url &&
        item.body == config.body
      );

      if (existingIndex != -1) {
        await box.deleteAt(existingIndex);
      }

      await box.add(config);

      while (box.length > limit && box.isNotEmpty) {
        await box.deleteAt(0);
      }
    } catch (e) {
      throw PersistenceException('Failed to add to history', cause: e);
    }
  }

  @override
  Future<void> clearHistory() async {
    try {
      await _box().clear();
    } catch (e) {
      throw PersistenceException('Failed to clear history', cause: e);
    }
  }

  @override
  Stream<void> watch() => _box().watch().map((_) {});
}
