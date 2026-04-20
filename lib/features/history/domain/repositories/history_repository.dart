import '../../../../core/domain/entities/request_config_entity.dart';

abstract class HistoryRepository {
  Future<List<HttpRequestConfigEntity>> getHistory();
  Future<void> saveHistory(List<HttpRequestConfigEntity> history);
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit);
  Future<void> clearHistory();
  Stream<List<HttpRequestConfigEntity>> watchHistory();
}
