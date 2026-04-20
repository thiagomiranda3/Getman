import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../models/request_tab_model.dart';

abstract class TabsLocalDataSource {
  Future<List<HttpRequestTabModel>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabModel> tabs);
}

class TabsLocalDataSourceImpl implements TabsLocalDataSource {
  Box<HttpRequestTabModel> _box() => Hive.box<HttpRequestTabModel>(HiveBoxes.tabs);

  @override
  Future<List<HttpRequestTabModel>> getTabs() async {
    try {
      return _box().values.toList();
    } catch (e) {
      throw PersistenceException('Failed to read tabs', cause: e);
    }
  }

  @override
  Future<void> saveTabs(List<HttpRequestTabModel> tabs) async {
    try {
      final box = _box();
      await box.clear();
      await box.addAll(tabs);
    } catch (e) {
      throw PersistenceException('Failed to save tabs', cause: e);
    }
  }
}
