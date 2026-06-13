import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/guard.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryLocalDataSource localDataSource;

  HistoryRepositoryImpl(this.localDataSource);

  Future<List<HttpRequestConfigEntity>> _read() => guardPersistence(() async {
    final models = await localDataSource.getHistory();
    // Newest first: the UI always wants this ordering.
    return models.reversed.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) =>
      guardPersistence(() async {
    await localDataSource.addToHistory(HttpRequestConfig.fromEntity(config), limit);
  });

  @override
  Stream<List<HttpRequestConfigEntity>> watchHistory() async* {
    yield await _read();
    await for (final _ in localDataSource.watch()) {
      yield await _read();
    }
  }
}
