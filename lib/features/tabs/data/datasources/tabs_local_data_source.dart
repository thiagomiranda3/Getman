import 'package:hive_flutter/hive_flutter.dart';
import '../models/request_tab_model.dart';

abstract class TabsLocalDataSource {
  Future<List<HttpRequestTabModel>> getTabs();
  Future<void> saveTabs(List<HttpRequestTabModel> tabs);
}

class TabsLocalDataSourceImpl implements TabsLocalDataSource {
  static const String tabsBoxName = 'tabs';

  @override
  Future<List<HttpRequestTabModel>> getTabs() async {
    final box = Hive.box<HttpRequestTabModel>(tabsBoxName);
    return box.values.toList();
  }

  @override
  Future<void> saveTabs(List<HttpRequestTabModel> tabs) async {
    final box = Hive.box<HttpRequestTabModel>(tabsBoxName);
    await box.clear();
    await box.addAll(tabs);
  }
}
