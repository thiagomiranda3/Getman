import '../entities/request_config_entity.dart';
import '../repositories/history_repository.dart';

class GetHistoryUseCase {
  final HistoryRepository repository;
  GetHistoryUseCase(this.repository);
  Future<List<HttpRequestConfigEntity>> call() => repository.getHistory();
}

class AddToHistoryUseCase {
  final HistoryRepository repository;
  AddToHistoryUseCase(this.repository);
  Future<void> call(HttpRequestConfigEntity config, int limit) => repository.addToHistory(config, limit);
}

class ClearHistoryUseCase {
  final HistoryRepository repository;
  ClearHistoryUseCase(this.repository);
  Future<void> call() => repository.clearHistory();
}
