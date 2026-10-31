// Web fallback: browsers cannot use dart:isolate. Preserves the native
// operation ordering and repository behavior against browser Hive storage.
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/storage/storage_backend.dart';
import 'package:getman/core/storage/storage_connection.dart';

Future<StorageConnection> openStorageConnection(String? settingsPath) async {
  final backend = StorageBackend();
  await backend.open();
  return _LocalStorageConnection(backend);
}

class _LocalStorageConnection extends StorageConnection {
  _LocalStorageConnection(this.backend);
  final StorageBackend backend;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<T> invoke<T>(StorageOperation operation, [Object? arguments]) {
    if (_closed) {
      return Future.error(const PersistenceFailure('Storage is closed'));
    }
    final result = _tail.then((_) => backend.invoke(operation, arguments));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result.then((value) => value as T);
  }

  @override
  Stream<T> watch<T>(StorageOperation operation) =>
      backend.watch(operation).cast<T>();

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _tail;
    await backend.close();
  }
}
