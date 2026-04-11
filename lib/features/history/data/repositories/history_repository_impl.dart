import '../../domain/entities/request_config_entity.dart';
import '../../domain/repositories/history_repository.dart';
import '../datasources/history_local_data_source.dart';
import '../models/request_config_model.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryLocalDataSource localDataSource;

  HistoryRepositoryImpl(this.localDataSource);

  @override
  Future<List<HttpRequestConfigEntity>> getHistory() async {
    final models = await localDataSource.getHistory();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> saveHistory(List<HttpRequestConfigEntity> history) async {
    final models = history.map((e) => HttpRequestConfig.fromEntity(e)).toList();
    await localDataSource.saveHistory(models);
  }

  @override
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit) async {
    final model = HttpRequestConfig.fromEntity(config);
    await localDataSource.addToHistory(model, limit);
  }

  @override
  Future<void> clearHistory() async {
    await localDataSource.clearHistory();
  }
}
