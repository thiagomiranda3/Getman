// UI-side persistence adapters. Only immutable domain snapshots cross the
// storage connection; Hive models/adapters and repository CPU stay in its owner.
// Network cancellation and live response bytes never cross this boundary.
import 'package:flutter/foundation.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_persistence.dart';

class BackgroundTabsPersistence implements TabsPersistence {
  BackgroundTabsPersistence(this.connection);
  final StorageConnection connection;

  @override
  Future<List<HttpRequestTabEntity>> getTabs() =>
      connection.invoke(StorageOperation.tabsGet);

  @override
  Future<void> saveTabs(List<HttpRequestTabEntity> tabs) => connection.invoke(
    StorageOperation.tabsSave,
    tabs.map(_storageTab).toList(),
  );

  @override
  Future<void> putTab(HttpRequestTabEntity tab) =>
      connection.invoke(StorageOperation.tabPut, _storageTab(tab));

  @override
  Future<void> deleteTabs(List<String> ids) =>
      connection.invoke(StorageOperation.tabsDelete, ids);

  @override
  Future<void> saveTabOrder(List<String> ids) =>
      connection.invoke(StorageOperation.tabOrder, ids);

  @override
  Future<List<PanelEntity>> getPanels() =>
      connection.invoke(StorageOperation.panelsGet);

  @override
  Future<String?> getActivePanelId() =>
      connection.invoke(StorageOperation.panelActive);

  @override
  Future<void> putPanel(PanelEntity panel) =>
      connection.invoke(StorageOperation.panelPut, (
        panel.id,
        panel.name,
        panel.tabs.map((t) => t.tabId).toList(),
        panel.activeTabId,
      ));

  @override
  Future<void> deletePanels(List<String> ids) =>
      connection.invoke(StorageOperation.panelsDelete, ids);

  @override
  Future<void> savePanelMeta(List<String> order, String activeId) =>
      connection.invoke(StorageOperation.panelMeta, (order, activeId));
}

class BackgroundCollectionsRepository implements CollectionsRepository {
  BackgroundCollectionsRepository(this.connection);
  final StorageConnection connection;

  @override
  Future<List<CollectionNodeEntity>> getCollections() =>
      connection.invoke(StorageOperation.collectionsGet);

  @override
  Future<void> saveCollections(List<CollectionNodeEntity> collections) =>
      connection.invoke(StorageOperation.collectionsSave, collections);
}

class BackgroundHistoryRepository implements HistoryRepository {
  BackgroundHistoryRepository(this.connection);
  final StorageConnection connection;

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) =>
      connection.invoke(StorageOperation.historyAdd, (config, limit));

  @override
  Future<void> deleteHistoryEntry(String id) =>
      connection.invoke(StorageOperation.historyDelete, id);

  @override
  Future<void> clearHistory() =>
      connection.invoke(StorageOperation.historyClear);

  @override
  Future<void> restoreHistoryEntries(List<HttpRequestConfigEntity> entries) =>
      connection.invoke(StorageOperation.historyRestore, entries);

  @override
  Stream<List<HttpRequestConfigEntity>> watchHistory() =>
      connection.watch(StorageOperation.historyWatch);
}

class BackgroundEnvironmentsRepository implements EnvironmentsRepository {
  BackgroundEnvironmentsRepository(this.connection);
  final StorageConnection connection;

  @override
  Future<List<EnvironmentEntity>> getEnvironments() =>
      connection.invoke(StorageOperation.environmentsGet);

  @override
  Stream<List<EnvironmentEntity>> watchEnvironments() =>
      connection.watch(StorageOperation.environmentsWatch);

  @override
  Future<void> putEnvironment(EnvironmentEntity env) =>
      connection.invoke(StorageOperation.environmentPut, env);

  @override
  Future<void> deleteEnvironment(String id) =>
      connection.invoke(StorageOperation.environmentDelete, id);

  @override
  Future<void> importEnvironments(List<EnvironmentEntity> envs) =>
      connection.invoke(StorageOperation.environmentsImport, envs);

  @override
  Future<void> saveEnvironments(List<EnvironmentEntity> envs) =>
      connection.invoke(StorageOperation.environmentsSave, envs);

  @override
  Future<void> updateEnvironment(
    EnvironmentEntity environment, {
    required EnvironmentEntity previous,
  }) => connection.invoke(StorageOperation.environmentUpdate, (
    environment,
    previous,
  ));

  @override
  Future<void> applyVariablePatch(String environmentId, ScriptPatch patch) =>
      connection.invoke(StorageOperation.environmentPatch, (
        environmentId,
        patch,
      ));
}

class BackgroundScriptTrustRepository implements ScriptTrustRepository {
  BackgroundScriptTrustRepository(this.connection);
  final StorageConnection connection;

  @override
  Future<bool> isTrusted(String configId, RequestScripts scripts) =>
      connection.invoke(StorageOperation.trustCheck, (configId, scripts));

  @override
  Future<void> trust(String configId, RequestScripts scripts) =>
      connection.invoke(StorageOperation.trustSave, (configId, scripts));
}

class BackgroundBodyFieldDictionary implements BodyFieldDictionaryRepository {
  BackgroundBodyFieldDictionary(this.connection, this._entries);
  final StorageConnection connection;
  List<BodyFieldEntry> _entries;

  @override
  List<BodyFieldEntry> get entries => _entries;

  @override
  Future<void> recordUsage(Map<String, int> increments) async {
    final next = await connection.invoke<List<BodyFieldEntry>>(
      StorageOperation.dictionaryRecord,
      Map<String, int>.of(increments),
    );
    _entries = List.unmodifiable(next);
  }
}

class BackgroundCookiePersistence implements CookiePersistence {
  BackgroundCookiePersistence(this.connection, this.initialCookies);
  final StorageConnection connection;
  final List<NetworkCookie> initialCookies;

  // CookieStore owns the live jar; this boot snapshot is read only by hydrate.
  @override
  List<NetworkCookie> loadAll() => initialCookies;

  Future<void> _write(StorageOperation operation, [Object? argument]) async {
    try {
      await connection.invoke<void>(operation, argument);
    } on Object catch (error) {
      // Cookie persistence remains best-effort, including worker failure.
      debugPrint('Cookie persistence failed: $error');
    }
  }

  @override
  Future<void> upsert(NetworkCookie cookie) =>
      _write(StorageOperation.cookiePut, cookie);
  @override
  Future<void> remove(String key) => _write(StorageOperation.cookieDelete, key);
  @override
  Future<void> clearAll() => _write(StorageOperation.cookiesClear);
}

// Strip transient data BEFORE port.send, which otherwise copies its full
// object graph on the UI isolate (notably up to 50 MiB media buffers).
HttpRequestTabEntity _storageTab(HttpRequestTabEntity tab) =>
    HttpRequestTabEntity(
      config: tab.config,
      tabId: tab.tabId,
      response: _storageResponse(tab.response),
      isSending: tab.isSending,
      collectionNodeId: tab.collectionNodeId,
      collectionName: tab.collectionName,
      responseHistory: tab.responseHistory
          .map(
            (entry) =>
                entry.copyWith(response: _storageResponse(entry.response)),
          )
          .toList(),
    );

HttpResponseEntity? _storageResponse(HttpResponseEntity? response) =>
    response?.copyWithBody(response.body, keepBytes: false);
