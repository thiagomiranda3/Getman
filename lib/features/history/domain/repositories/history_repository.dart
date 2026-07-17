// Abstract repository for the request-history feature: append (with a size
// limit) and a newest-first watch stream. Implemented by HistoryRepositoryImpl.

import 'package:getman/core/domain/entities/request_config_entity.dart';

abstract class HistoryRepository {
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit);

  /// Emits the full newest-first list on subscribe and after every change.
  Stream<List<HttpRequestConfigEntity>> watchHistory();
}
