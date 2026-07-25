// Abstract repository for the request-history feature: append (with a size
// limit), per-entry delete, clear-all, undo-restore, and a newest-first
// watch stream. Implemented by HistoryRepositoryImpl.

import 'package:getman/core/domain/entities/request_config_entity.dart';

abstract class HistoryRepository {
  Future<void> addToHistory(HttpRequestConfigEntity config, int limit);

  /// Deletes the entry whose config id equals [id] (instant delete; UNDO
  /// re-inserts via [restoreHistoryEntries]).
  Future<void> deleteHistoryEntry(String id);

  /// Removes the entire history (CLEAR ALL).
  Future<void> clearHistory();

  /// Re-inserts previously deleted snapshots (the UNDO path). Signature
  /// duplicates are skipped; display position is recovered via sentAt
  /// ordering, so append-at-tail storage is fine.
  Future<void> restoreHistoryEntries(List<HttpRequestConfigEntity> entries);

  /// Emits the full newest-first list on subscribe and after every change.
  Stream<List<HttpRequestConfigEntity>> watchHistory();
}
