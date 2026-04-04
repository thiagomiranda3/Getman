import 'package:hive_flutter/hive_flutter.dart';
import '../models/settings_model.dart';
import '../models/request_config.dart';
import '../models/request_tab.dart';
import '../models/collection_node.dart';

class StorageService {
  static const String settingsBoxName = 'settings';
  static const String historyBoxName = 'history';
  static const String collectionsBoxName = 'collections';
  static const String tabsBoxName = 'tabs';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register Adapters
    Hive.registerAdapter(SettingsModelAdapter());
    Hive.registerAdapter(HttpRequestConfigAdapter());
    Hive.registerAdapter(HttpRequestTabModelAdapter());
    Hive.registerAdapter(CollectionNodeAdapter());

    // Open Boxes
    await Hive.openBox<SettingsModel>(settingsBoxName);
    await Hive.openBox<HttpRequestConfig>(historyBoxName);
    await Hive.openBox<CollectionNode>(collectionsBoxName);
    await Hive.openBox<HttpRequestTabModel>(tabsBoxName);
  }

  // Settings
  static SettingsModel getSettings() {
    final box = Hive.box<SettingsModel>(settingsBoxName);
    return box.get('current', defaultValue: SettingsModel())!;
  }

  static Future<void> saveSettings(SettingsModel settings) async {
    final box = Hive.box<SettingsModel>(settingsBoxName);
    await box.put('current', settings);
  }

  // History
  static List<HttpRequestConfig> getHistory() {
    final box = Hive.box<HttpRequestConfig>(historyBoxName);
    return box.values.toList();
  }

  static Future<void> saveHistory(List<HttpRequestConfig> history) async {
    final box = Hive.box<HttpRequestConfig>(historyBoxName);
    await box.clear();
    await box.addAll(history);
  }

  // Collections
  static List<CollectionNode> getCollections() {
    final box = Hive.box<CollectionNode>(collectionsBoxName);
    return box.values.toList();
  }

  static Future<void> saveCollections(List<CollectionNode> collections) async {
    final box = Hive.box<CollectionNode>(collectionsBoxName);
    await box.clear();
    await box.addAll(collections);
  }

  // Tabs
  static List<HttpRequestTabModel> getTabs() {
    final box = Hive.box<HttpRequestTabModel>(tabsBoxName);
    return box.values.toList();
  }

  static Future<void> saveTabs(List<HttpRequestTabModel> tabs) async {
    final box = Hive.box<HttpRequestTabModel>(tabsBoxName);
    await box.clear();
    await box.addAll(tabs);
  }
}
