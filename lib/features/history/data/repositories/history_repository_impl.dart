import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../../core/error/guard.dart';
import '../../domain/repositories/history_repository.dart';
import '../datasources/history_local_data_source.dart';
import '../models/request_config_model.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryLocalDataSource localDataSource;

  HistoryRepositoryImpl(this.localDataSource);

  @override
  Future<List<HttpRequestConfigEntity>> getHistory() => guardPersistence(() async {
    final models = await localDataSource.getHistory();
    // Newest first: the UI always wants this ordering.
    return models.reversed.map((m) => m.toEntity()).toList();
  });

  @override
  Future<void> saveHistory(List<HttpRequestConfigEntity> history) =>
      guardPersistence(() async {
    final models = history.map((e) => HttpRequestConfig.fromEntity(e)).toList();
    await localDataSource.saveHistory(models);
  });

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) =>
      guardPersistence(() async {
    await localDataSource.addToHistory(HttpRequestConfig.fromEntity(config), limit);
  });

  @override
  Future<void> clearHistory() => guardPersistence(localDataSource.clearHistory);

  @override
  Stream<List<HttpRequestConfigEntity>> watchHistory() async* {
    yield await getHistory();
    await for (final _ in localDataSource.watch()) {
      yield await getHistory();
    }
  }
}
