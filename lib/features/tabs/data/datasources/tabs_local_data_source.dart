import 'package:hive_flutter/hive_flutter.dart';
import '../models/request_tab_model.dart';

abstract class TabsLocalDataSource {
  Future<List<HttpRequestTabModel>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabModel> tabs);
}

class TabsLocalDataSourceImpl implements TabsLocalDataSource {
  static const String tabsBoxName = 'tabs';

  Future<Box<HttpRequestTabModel>> _getBox() async {
    if (Hive.isBoxOpen(tabsBoxName)) {
      return Hive.box<HttpRequestTabModel>(tabsBoxName);
    }
    return await Hive.openBox<HttpRequestTabModel>(tabsBoxName);
  }

  @override
  Future<List<HttpRequestTabModel>> getTabs() async {
    final box = await _getBox();
    return box.values.toList();
  }

  @override
  Future<void> saveTabs(List<HttpRequestTabModel> tabs) async {
    final box = await _getBox();
    await box.clear();
    await box.addAll(tabs);
  }
}
