import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

abstract class TabsLocalDataSource {
  Future<List<HttpRequestTabModel>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabModel> tabs);
  Future<void> putTab(HttpRequestTabModel tab);
  Future<void> deleteTabs(Iterable<String> tabIds);
  Future<void> saveOrder(List<String> orderedTabIds);
}

class TabsLocalDataSourceImpl implements TabsLocalDataSource {
  /// Key inside the meta box holding the ordered list of tabIds.
  static const String orderKey = 'order';

  Box<HttpRequestTabModel> _box() =>
      Hive.box<HttpRequestTabModel>(HiveBoxes.tabs);
  Box<dynamic> _metaBox() => Hive.box(HiveBoxes.tabsMeta);

  @override
  Future<List<HttpRequestTabModel>> getTabs() async {
    try {
      final box = _box();
      await _migrateLegacyIntKeysIfNeeded(box);

      // Reconcile the stored order with the box contents: drop ids that no
      // longer exist, append entries the order list doesn't know about.
      final stored = _metaBox().get(orderKey);
      final order = stored is List ? stored.cast<String>() : const <String>[];
      final byId = {for (final m in box.values) m.tabId: m};

      final result = <HttpRequestTabModel>[];
      for (final id in order) {
        final model = byId.remove(id);
        if (model != null) result.add(model);
      }
      result.addAll(byId.values);
      return result;
    } catch (e) {
      throw PersistenceException('Failed to read tabs', cause: e);
    }
  }

  /// One-time migration from the legacy auto-increment layout: int keys
  /// iterate in insertion order, which *was* the tab order, so capture it
  /// before re-keying every entry by tabId.
  Future<void> _migrateLegacyIntKeysIfNeeded(
    Box<HttpRequestTabModel> box,
  ) async {
    if (!box.keys.any((k) => k is int)) return;
    final models = box.values.toList();
    await box.clear();
    await box.putAll({for (final m in models) m.tabId: m});
    await _metaBox().put(orderKey, models.map((m) => m.tabId).toList());
  }

  @override
  Future<void> saveTabs(List<HttpRequestTabModel> tabs) async {
    try {
      final box = _box();
      await box.clear();
      await box.putAll({for (final t in tabs) t.tabId: t});
      await _metaBox().put(orderKey, tabs.map((t) => t.tabId).toList());
    } catch (e) {
      throw PersistenceException('Failed to save tabs', cause: e);
    }
  }

  @override
  Future<void> putTab(HttpRequestTabModel tab) async {
    try {
      await _box().put(tab.tabId, tab);
    } catch (e) {
      throw PersistenceException('Failed to save tab', cause: e);
    }
  }

  @override
  Future<void> deleteTabs(Iterable<String> tabIds) async {
    try {
      await _box().deleteAll(tabIds);
    } catch (e) {
      throw PersistenceException('Failed to delete tabs', cause: e);
    }
  }

  @override
  Future<void> saveOrder(List<String> orderedTabIds) async {
    try {
      await _metaBox().put(orderKey, orderedTabIds);
    } catch (e) {
      throw PersistenceException('Failed to save tab order', cause: e);
    }
  }
}
