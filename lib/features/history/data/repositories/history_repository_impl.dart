import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/request_config_entity.dart';
import '../../domain/repositories/history_repository.dart';
import '../datasources/history_local_data_source.dart';
import '../models/request_config_model.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryLocalDataSource localDataSource;

  HistoryRepositoryImpl(this.localDataSource);

  @override
  Future<List<HttpRequestConfigEntity>> getHistory() async {
    try {
      final models = await localDataSource.getHistory();
      return models.map((m) => m.toEntity()).toList();
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Future<void> saveHistory(List<HttpRequestConfigEntity> history) async {
    try {
      final models = history.map((e) => HttpRequestConfig.fromEntity(e)).toList();
      await localDataSource.saveHistory(models);
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) async {
    try {
      final model = HttpRequestConfig.fromEntity(config);
      await localDataSource.addToHistory(model, limit);
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Future<void> clearHistory() async {
    try {
      await localDataSource.clearHistory();
    } on PersistenceException catch (e) {
      throw PersistenceFailure(e.message);
    }
  }

  @override
  Stream<List<HttpRequestConfigEntity>> watchHistory() async* {
    yield await getHistory();
    await for (final _ in localDataSource.watch()) {
      yield await getHistory();
    }
  }
}
