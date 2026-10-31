// Executes complete repository operations in the storage owner, including
// model conversion, history dedup/sorting, migrations and Hive serialization.
// Existing repository rules and file formats are reused without a data rewrite.
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/hive_adapters.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/cookies/data/hive_cookie_persistence.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/data/repositories/environments_repository_impl.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/data/repositories/history_repository_impl.dart';
import 'package:getman/features/scripting/data/repositories/script_trust_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/repositories/body_field_dictionary_repository_impl.dart';
import 'package:getman/features/tabs/data/repositories/hive_tabs_persistence.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:hive_ce/hive.dart';

class StorageBackend {
  final List<Box<dynamic>> _boxes = [];

  Future<Box<T>> _open<T>(String name) async {
    final box = await Hive.openBox<T>(name);
    _boxes.add(box);
    return box;
  }

  final tabs = HiveTabsPersistence(TabsLocalDataSourceImpl());
  final collections = CollectionsRepositoryImpl(
    CollectionsLocalDataSourceImpl(),
  );
  final history = HistoryRepositoryImpl(HistoryLocalDataSourceImpl());
  final environments = EnvironmentsRepositoryImpl(
    EnvironmentsLocalDataSourceImpl(),
  );
  final cookies = HiveCookiePersistence();
  late final dictionary = BodyFieldDictionaryRepositoryImpl(
    Hive.box<int>(HiveBoxes.bodyFieldDictionary),
  );
  late final trust = ScriptTrustRepositoryImpl(
    Hive.box<String>(HiveBoxes.scriptTrust),
  );

  static const List<String> boxNames = [
    HiveBoxes.environments,
    HiveBoxes.history,
    HiveBoxes.tabs,
    HiveBoxes.tabsMeta,
    HiveBoxes.collections,
    HiveBoxes.cookies,
    HiveBoxes.panels,
    HiveBoxes.bodyFieldDictionary,
    HiveBoxes.scriptTrust,
  ];

  Future<void> open() async {
    registerHiveAdapters();
    try {
      await Future.wait<Box<dynamic>>([
        _open<EnvironmentModel>(HiveBoxes.environments),
        _open<HttpRequestConfig>(HiveBoxes.history),
        _open<HttpRequestTabModel>(HiveBoxes.tabs),
        _open(HiveBoxes.tabsMeta),
        _open<CollectionNode>(HiveBoxes.collections),
        _open<StoredCookieModel>(HiveBoxes.cookies),
        _open<PanelModel>(HiveBoxes.panels),
        _open<int>(HiveBoxes.bodyFieldDictionary),
        _open<String>(HiveBoxes.scriptTrust),
      ]);
      await EnvironmentsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();
      await CollectionsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();
      await HiveCookiePersistence.migrateLegacyKeysIfNeeded();
    } on Object {
      await close();
      rethrow;
    }
  }

  Future<void> close() async {
    for (final box in _boxes) {
      if (box.isOpen) await box.close();
    }
    _boxes.clear();
  }

  Stream<Object?> watch(StorageOperation operation) => switch (operation) {
    StorageOperation.historyWatch => history.watchHistory(),
    StorageOperation.environmentsWatch => environments.watchEnvironments(),
    _ => throw ArgumentError('Not a storage stream: $operation'),
  };

  Future<Object?> invoke(StorageOperation operation, Object? args) async {
    switch (operation) {
      case StorageOperation.tabsGet:
        return tabs.getTabs();
      case StorageOperation.tabsSave:
        await tabs.saveTabs(args! as List<HttpRequestTabEntity>);
        return null;
      case StorageOperation.tabPut:
        await tabs.putTab(args! as HttpRequestTabEntity);
        return null;
      case StorageOperation.tabsDelete:
        await tabs.deleteTabs(args! as List<String>);
        return null;
      case StorageOperation.tabOrder:
        await tabs.saveTabOrder(args! as List<String>);
        return null;
      case StorageOperation.panelsGet:
        return tabs.getPanels();
      case StorageOperation.panelActive:
        return tabs.getActivePanelId();
      case StorageOperation.panelPut:
        final (id, name, ids, active) =
            args! as (String, String, List<String>, String);
        await tabs.localDataSource.putPanel(
          PanelModel(
            id: id,
            name: name,
            orderedTabIds: ids,
            activeTabId: active,
          ),
        );
        return null;
      case StorageOperation.panelsDelete:
        await tabs.deletePanels(args! as List<String>);
        return null;
      case StorageOperation.panelMeta:
        await tabs.savePanelMeta(
          (args! as (List<String>, String)).$1,
          (args as (List<String>, String)).$2,
        );
        return null;
      case StorageOperation.collectionsGet:
        return collections.getCollections();
      case StorageOperation.collectionsSave:
        await collections.saveCollections(args! as List<CollectionNodeEntity>);
        return null;
      case StorageOperation.historyAdd:
        await history.addToHistory(
          (args! as (HttpRequestConfigEntity, int)).$1,
          (args as (HttpRequestConfigEntity, int)).$2,
        );
        return null;
      case StorageOperation.historyDelete:
        await history.deleteHistoryEntry(args! as String);
        return null;
      case StorageOperation.historyClear:
        await history.clearHistory();
        return null;
      case StorageOperation.historyRestore:
        await history.restoreHistoryEntries(
          args! as List<HttpRequestConfigEntity>,
        );
        return null;
      case StorageOperation.environmentsGet:
        return environments.getEnvironments();
      case StorageOperation.environmentPut:
        await environments.putEnvironment(args! as EnvironmentEntity);
        return null;
      case StorageOperation.environmentDelete:
        await environments.deleteEnvironment(args! as String);
        return null;
      case StorageOperation.environmentsImport:
        await environments.importEnvironments(args! as List<EnvironmentEntity>);
        return null;
      case StorageOperation.environmentsSave:
        await environments.saveEnvironments(args! as List<EnvironmentEntity>);
        return null;
      case StorageOperation.environmentUpdate:
        await environments.updateEnvironment(
          (args! as (EnvironmentEntity, EnvironmentEntity)).$1,
          previous: (args as (EnvironmentEntity, EnvironmentEntity)).$2,
        );
        return null;
      case StorageOperation.environmentPatch:
        await environments.applyVariablePatch(
          (args! as (String, ScriptPatch)).$1,
          (args as (String, ScriptPatch)).$2,
        );
        return null;
      case StorageOperation.cookiesGet:
        return cookies.loadAll();
      case StorageOperation.cookiePut:
        await cookies.upsert(args! as NetworkCookie);
        return null;
      case StorageOperation.cookieDelete:
        await cookies.remove(args! as String);
        return null;
      case StorageOperation.cookiesClear:
        await cookies.clearAll();
        return null;
      case StorageOperation.dictionaryGet:
        return dictionary.entries;
      case StorageOperation.dictionaryRecord:
        await dictionary.recordUsage(args! as Map<String, int>);
        return dictionary.entries;
      case StorageOperation.trustCheck:
        return trust.isTrusted(
          (args! as (String, RequestScripts)).$1,
          (args as (String, RequestScripts)).$2,
        );
      case StorageOperation.trustSave:
        await trust.trust(
          (args! as (String, RequestScripts)).$1,
          (args as (String, RequestScripts)).$2,
        );
        return null;
      case StorageOperation.flush:
        for (final box in _boxes) {
          await box.flush();
        }
        return null;
      case StorageOperation.close:
        await close();
        return null;
      case StorageOperation.historyWatch:
      case StorageOperation.environmentsWatch:
        throw ArgumentError('Use watch for storage streams');
    }
  }
}
