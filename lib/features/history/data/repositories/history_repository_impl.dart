import 'dart:async';

import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/guard.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl(this.localDataSource);
  final HistoryLocalDataSource localDataSource;

  /// One `addToHistory` performs up to ~3 box mutations (dedup delete + add +
  /// batched trim), each firing a watch event. Coalescing within this window
  /// turns that burst into a single full re-read + emission.
  static const Duration _coalesceWindow = Duration(milliseconds: 80);

  Future<List<HttpRequestConfigEntity>> _read() => guardPersistence(() async {
    final models = await localDataSource.getHistory();
    // Newest first: the UI always wants this ordering.
    return models.reversed.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) =>
      guardPersistence(() async {
        await localDataSource.addToHistory(
          HttpRequestConfig.fromEntity(config),
          limit,
        );
      });

  @override
  Stream<List<HttpRequestConfigEntity>> watchHistory() {
    StreamSubscription<void>? sub;
    Timer? debounce;
    late StreamController<List<HttpRequestConfigEntity>> controller;

    Future<void> push() async {
      try {
        final list = await _read();
        if (!controller.isClosed) controller.add(list);
      } on Object catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller = StreamController<List<HttpRequestConfigEntity>>(
      onListen: () {
        unawaited(push()); // initial snapshot on subscribe
        sub = localDataSource.watch().listen((_) {
          debounce?.cancel();
          debounce = Timer(_coalesceWindow, push);
        });
      },
      onCancel: () async {
        debounce?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }
}
