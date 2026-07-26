// HistoryBloc events. HistoryUpdated is internal-only — dispatched by the
// bloc's own watchHistory() subscription. The D3 management events
// (DeleteHistoryEntry / ClearHistory / RestoreHistoryEntries) ARE dispatched
// from the UI (history_list.dart): the per-row hover delete, the CLEAR ALL
// toolbar button, and the UNDO snackbar action respectively.

import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

abstract class HistoryEvent extends Equatable {
  const HistoryEvent();
  @override
  List<Object?> get props => [];
}

/// Internal: dispatched by the bloc's own `watchHistory()` subscription.
class HistoryUpdated extends HistoryEvent {
  const HistoryUpdated(this.history);
  final List<HttpRequestConfigEntity> history;
  @override
  List<Object?> get props => [history];
}

/// Deletes one history entry by its config [id] (instant, no dialog — A1
/// single-item pattern); the UI pairs it with a 5 s UNDO snackbar that
/// dispatches [RestoreHistoryEntries].
class DeleteHistoryEntry extends HistoryEvent {
  const DeleteHistoryEntry(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Clears the entire history. The UI confirms first (ConfirmDialog — A1 bulk
/// pattern) and then offers UNDO restoring the captured list via
/// [RestoreHistoryEntries].
class ClearHistory extends HistoryEvent {
  const ClearHistory();
}

/// Re-inserts previously deleted history snapshots (the UNDO action).
/// Signature duplicates already back in the box are skipped by the data
/// source; display position is recovered via sentAt ordering.
class RestoreHistoryEntries extends HistoryEvent {
  const RestoreHistoryEntries(this.entries);
  final List<HttpRequestConfigEntity> entries;
  @override
  List<Object?> get props => [entries];
}
