// Typed operation names for the single owner of feature persistence. Messages
// contain domain values only: never HiveObjects, widgets, sockets or callbacks.
// Native uses a persistent isolate; web preserves the same async API locally.
import 'package:getman/core/storage/storage_connection_stub.dart'
    if (dart.library.io) 'package:getman/core/storage/storage_connection_io.dart'
    as platform;

enum StorageOperation {
  tabsGet,
  tabsSave,
  tabPut,
  tabsDelete,
  tabOrder,
  panelsGet,
  panelActive,
  panelPut,
  panelsDelete,
  panelMeta,
  collectionsGet,
  collectionsSave,
  historyAdd,
  historyDelete,
  historyClear,
  historyRestore,
  environmentsGet,
  environmentPut,
  environmentDelete,
  environmentsImport,
  environmentsSave,
  environmentUpdate,
  environmentPatch,
  cookiesGet,
  cookiePut,
  cookieDelete,
  cookiesClear,
  dictionaryGet,
  dictionaryRecord,
  trustCheck,
  trustSave,
  historyWatch,
  environmentsWatch,
  flush,
  close,
}

abstract class StorageConnection {
  Future<T> invoke<T>(StorageOperation operation, [Object? arguments]);
  Stream<T> watch<T>(StorageOperation operation);
  Future<void> flush() => invoke<void>(StorageOperation.flush);
  Future<void> close();
}

/// [settingsPath] identifies the already-open settings file. Feature boxes
/// use its directory, but the worker never opens the settings box itself.
Future<StorageConnection> openStorageConnection(String? settingsPath) =>
    platform.openStorageConnection(settingsPath);
