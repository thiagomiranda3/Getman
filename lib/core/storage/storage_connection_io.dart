// Persistent native storage isolate. One owner per canonical data directory;
// FIFO commands preserve read/write ordering, subscriptions keep repository
// watch semantics, and exit/error handling fails pending calls instead of
// hanging the UI. Closing drains accepted commands and releases Hive locks.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:getman/core/error/failures.dart';
import 'package:getman/core/storage/storage_backend.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:hive_ce/hive.dart';

final _activeDirectories = <String>{};

Future<StorageConnection> openStorageConnection(String? settingsPath) async {
  if (settingsPath == null) throw StateError('Missing native storage path');
  if (StorageBackend.boxNames.any(Hive.isBoxOpen)) {
    throw StateError('Feature boxes must be closed on the UI isolate');
  }
  final path = await File(settingsPath).parent.resolveSymbolicLinks();
  if (!_activeDirectories.add(path)) {
    throw StateError('Storage is already open for this directory');
  }
  final client = _IsolateStorageConnection(path);
  try {
    await client.start();
    return client;
  } on Object {
    client.dispose();
    rethrow;
  }
}

class _IsolateStorageConnection extends StorageConnection {
  _IsolateStorageConnection(this.path);
  final String path;
  final _responses = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  final _streams = <int, StreamController<Object?>>{};
  late SendPort _commands;
  Isolate? _isolate;
  int _nextId = 0;
  bool _disposed = false;
  Future<void>? _closing;

  Future<void> start() async {
    _responses.listen(_onResponse);
    _isolate = await Isolate.spawn(
      _storageMain,
      (path, _responses.sendPort),
      onError: _responses.sendPort,
      onExit: _responses.sendPort,
      debugName: 'getman.storage',
    );
    await _ready.future;
  }

  void _onResponse(dynamic message) {
    if (message is SendPort) {
      _commands = message;
      _ready.complete();
      return;
    }
    if (message is List && message.length == 5) {
      final kind = message[0] as String;
      final id = message[1] as int;
      final error = message[3] as String?;
      final stack = StackTrace.fromString(message[4] as String? ?? '');
      if (kind == 'event') {
        // Borrowed controller; watch.onCancel/dispose owns its closure.
        // ignore: close_sinks
        final stream = _streams[id];
        if (stream == null) return;
        if (error == null) {
          stream.add(message[2]);
        } else {
          stream.addError(PersistenceFailure(error), stack);
        }
      } else if (kind == 'done') {
        final stream = _streams.remove(id);
        if (stream != null) unawaited(stream.close());
      } else {
        final pending = _pending.remove(id);
        if (pending == null) return;
        if (error == null) {
          pending.complete(message[2]);
        } else {
          pending.completeError(PersistenceFailure(error), stack);
        }
      }
      return;
    }
    // Dart sends null on exit, or [error, stack] for an unhandled exception.
    final error = PersistenceFailure(
      message is List
          ? 'Storage worker failed: ${message.first}'
          : 'Storage worker stopped',
    );
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    for (final stream in _streams.values) {
      stream.addError(error);
    }
    dispose();
  }

  @override
  Future<T> invoke<T>(StorageOperation operation, [Object? arguments]) {
    if (_disposed || _closing != null) {
      return Future.error(const PersistenceFailure('Storage is closed'));
    }
    return _send(operation, arguments).then((value) => value as T);
  }

  Future<Object?> _send(StorageOperation operation, Object? arguments) {
    final id = _nextId++;
    final pending = Completer<Object?>();
    _pending[id] = pending;
    try {
      _commands.send(['call', id, operation, arguments]);
    } on Object catch (error, stack) {
      _pending.remove(id);
      pending.completeError(PersistenceFailure('$error'), stack);
    }
    return pending.future;
  }

  @override
  Stream<T> watch<T>(StorageOperation operation) {
    final id = _nextId++;
    // Subscription ownership ends on cancellation, worker exit or close.
    late StreamController<Object?> controller;
    controller = StreamController<Object?>(
      onListen: () {
        if (_disposed || _closing != null) {
          controller.addError(const PersistenceFailure('Storage is closed'));
          unawaited(controller.close());
          return;
        }
        _streams[id] = controller;
        _commands.send(['watch', id, operation, null]);
      },
      onCancel: () {
        _streams.remove(id);
        if (!_disposed && _closing == null) {
          _commands.send(['unwatch', id, operation, null]);
        }
        unawaited(controller.close());
      },
    );
    return controller.stream.cast<T>();
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_disposed) return;
    try {
      await _send(StorageOperation.close, null);
    } finally {
      dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _responses.close();
    _isolate?.kill(priority: Isolate.immediate);
    _activeDirectories.remove(path);
    for (final stream in _streams.values) {
      unawaited(stream.close());
    }
    _streams.clear();
  }
}

Future<void> _storageMain((String, SendPort) boot) async {
  final (path, replies) = boot;
  // This isolate is the sole owner of feature boxes. UI ownership is checked
  // before spawn, and a second owner for the directory is rejected. Hive's
  // name-based warning cannot recognize this RPC owner. Keep other warnings.
  HiveLogger.unsafeIsolateWarning = false;
  Hive.init(path);
  final backend = StorageBackend();
  await backend.open();
  final commands = ReceivePort();
  final subscriptions = <int, StreamSubscription<Object?>>{};
  replies.send(commands.sendPort);
  await for (final dynamic message in commands) {
    final request = message as List;
    final kind = request[0] as String;
    final id = request[1] as int;
    final operation = request[2] as StorageOperation;
    try {
      if (kind == 'watch') {
        subscriptions[id] = backend
            .watch(operation)
            .listen(
              (value) => replies.send(['event', id, value, null, null]),
              onError: (Object error, StackTrace stack) =>
                  replies.send(['event', id, null, '$error', '$stack']),
              onDone: () => replies.send(['done', id, null, null, null]),
            );
      } else if (kind == 'unwatch') {
        await subscriptions.remove(id)?.cancel();
      } else {
        if (operation == StorageOperation.close) {
          for (final subscription in subscriptions.values) {
            await subscription.cancel();
          }
          subscriptions.clear();
        }
        final value = await backend.invoke(operation, request[3] as Object?);
        replies.send(['reply', id, value, null, null]);
        if (operation == StorageOperation.close) {
          commands.close();
          break;
        }
      }
    } on Object catch (error, stack) {
      final text = error is Failure ? error.message : '$error';
      replies.send([
        if (kind == 'watch') 'event' else 'reply',
        id,
        null,
        text,
        '$stack',
      ]);
    }
  }
}
