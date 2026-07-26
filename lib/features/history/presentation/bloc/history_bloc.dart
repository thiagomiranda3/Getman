// History bloc: subscribes to WatchHistoryUseCase on construction and mirrors
// emissions into state (no explicit load event — the watch yields the current
// list on subscribe). Since D3 the UI also dispatches DeleteHistoryEntry /
// ClearHistory (both optimistic: the row/list vanishes immediately, then the
// debounced watch emission confirms the Equatable-equal list) and
// RestoreHistoryEntries (the UNDO path — deliberately NOT optimistic: the
// repository owns sentAt-based ordering, so the watch emission delivers the
// correctly merged list). All writes go through use cases over the abstract
// repository only.

import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';

/// Mirrors the history box through `watchHistory()` and handles the D3
/// management events: per-entry delete, clear-all, and undo-restore.
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc({
    required this._watchHistoryUseCase,
    required this._deleteHistoryEntryUseCase,
    required this._clearHistoryUseCase,
    required this._restoreHistoryEntriesUseCase,
  }) : super(const HistoryState(isLoading: true)) {
    on<HistoryUpdated>(_onHistoryUpdated);
    on<DeleteHistoryEntry>(_onDeleteHistoryEntry);
    on<ClearHistory>(_onClearHistory);
    on<RestoreHistoryEntries>(_onRestoreHistoryEntries);

    // Guard against the stream emitting during/after close() — otherwise
    // `add(HistoryUpdated)` on a closed bloc throws StateError.
    _subscription = _watchHistoryUseCase().listen(
      (history) {
        if (!isClosed) add(HistoryUpdated(history));
      },
      onError: (Object e) {
        log('History watch error: $e', name: 'HistoryBloc');
        // Clear isLoading too: with only the log, a failed initial read left
        // the drawer on a permanent spinner with no way to notice or retry.
        if (!isClosed) add(const HistoryUpdated([]));
      },
    );
  }
  final WatchHistoryUseCase _watchHistoryUseCase;
  final DeleteHistoryEntryUseCase _deleteHistoryEntryUseCase;
  final ClearHistoryUseCase _clearHistoryUseCase;
  final RestoreHistoryEntriesUseCase _restoreHistoryEntriesUseCase;

  StreamSubscription<List<HttpRequestConfigEntity>>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }

  void _onHistoryUpdated(HistoryUpdated event, Emitter<HistoryState> emit) {
    emit(state.copyWith(history: event.history, isLoading: false));
  }

  Future<void> _onDeleteHistoryEntry(
    DeleteHistoryEntry event,
    Emitter<HistoryState> emit,
  ) async {
    // Optimistic: drop the row immediately; the debounced watchHistory()
    // emission then confirms the same (Equatable-equal) list, so no rebuild.
    emit(
      state.copyWith(
        history: state.history.where((e) => e.id != event.id).toList(),
      ),
    );
    try {
      await _deleteHistoryEntryUseCase(event.id);
    } on Object catch (e) {
      log('Delete history entry failed: $e', name: 'HistoryBloc');
    }
  }

  Future<void> _onClearHistory(
    ClearHistory event,
    Emitter<HistoryState> emit,
  ) async {
    emit(state.copyWith(history: const []));
    try {
      await _clearHistoryUseCase();
    } on Object catch (e) {
      log('Clear history failed: $e', name: 'HistoryBloc');
    }
  }

  Future<void> _onRestoreHistoryEntries(
    RestoreHistoryEntries event,
    Emitter<HistoryState> emit,
  ) async {
    // No optimistic emit: the repository orders by sentAt, so the watch
    // emission delivers the restored entries at their original positions.
    try {
      await _restoreHistoryEntriesUseCase(event.entries);
    } on Object catch (e) {
      log('Restore history entries failed: $e', name: 'HistoryBloc');
    }
  }
}
