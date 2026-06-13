import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';

class AddToHistoryUseCase {
  final HistoryRepository repository;
  AddToHistoryUseCase(this.repository);
  Future<void> call(HttpRequestConfigEntity config, int limit) => repository.addToHistory(config, limit);
}

class WatchHistoryUseCase {
  final HistoryRepository repository;
  WatchHistoryUseCase(this.repository);
  Stream<List<HttpRequestConfigEntity>> call() => repository.watchHistory();
}
