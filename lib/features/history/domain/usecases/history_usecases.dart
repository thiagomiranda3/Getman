import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';

class AddToHistoryUseCase {
  AddToHistoryUseCase(this.repository);
  final HistoryRepository repository;
  Future<void> call(HttpRequestConfigEntity config, int limit) =>
      repository.addToHistory(config, limit);
}

class WatchHistoryUseCase {
  WatchHistoryUseCase(this.repository);
  final HistoryRepository repository;
  Stream<List<HttpRequestConfigEntity>> call() => repository.watchHistory();
}
