import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/domain/conflict_service.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_event.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_state.dart';

/// Drives the resolve → continue loop over an in-progress rebase, one commit
/// (batch) of conflicts at a time. Errors are surfaced in state and the
/// rebase is left paused — never auto-aborted — so the user never loses
/// work to a swallowed failure.
class ConflictBloc extends Bloc<ConflictEvent, ConflictState> {
  ConflictBloc({required this._service}) : super(const ConflictState()) {
    on<LoadConflicts>(_onLoad);
    on<ResolveAndContinue>(_onResolveAndContinue);
    on<AbortRebase>(_onAbort);
  }

  final ConflictService _service;

  /// Drops an event while another op is in flight — the bloc is effectively
  /// droppable. Every handler always emits a terminal (ready/done/error)
  /// state in a try/catch, so [ConflictState.isBusy] is always exited and
  /// this cannot deadlock.
  bool _dropWhileBusy(String op) {
    if (state.isBusy) {
      log('$op ignored: another operation is in flight', name: 'ConflictBloc');
      return true;
    }
    return false;
  }

  Future<void> _onLoad(LoadConflicts event, Emitter<ConflictState> emit) async {
    if (_dropWhileBusy('load')) return;
    emit(state.copyWith(status: ConflictStatus.loading));
    try {
      final conflicts = await _service.currentConflicts(event.root);
      _emitBatch(emit, conflicts, state.batch);
    } on Object catch (e) {
      _fail(e, emit, 'load');
    }
  }

  Future<void> _onResolveAndContinue(
    ResolveAndContinue event,
    Emitter<ConflictState> emit,
  ) async {
    if (_dropWhileBusy('resolve')) return;
    emit(state.copyWith(status: ConflictStatus.resolving));
    try {
      await _service.resolve(event.root, event.resolutions);
      final step = await _service.continueRebase(event.root);
      if (step == RebaseStep.done) {
        emit(state.copyWith(status: ConflictStatus.done));
        return;
      }
      final conflicts = await _service.currentConflicts(event.root);
      _emitBatch(emit, conflicts, state.batch + 1);
    } on Object catch (e) {
      // Leave the repo paused mid-rebase — do NOT abort on a resolve failure,
      // the user's picks (and the in-progress rebase) must survive a retry.
      _fail(e, emit, 'resolve');
    }
  }

  Future<void> _onAbort(AbortRebase event, Emitter<ConflictState> emit) async {
    if (_dropWhileBusy('abort')) return;
    emit(state.copyWith(status: ConflictStatus.resolving));
    try {
      await _service.abort(event.root);
      emit(state.copyWith(status: ConflictStatus.done));
    } on Object catch (e) {
      _fail(e, emit, 'abort');
    }
  }

  /// Emits `done` when [conflicts] is empty (nothing left to resolve),
  /// otherwise `ready` with the batch populated.
  void _emitBatch(
    Emitter<ConflictState> emit,
    List<FileConflict> conflicts,
    int batch,
  ) {
    if (conflicts.isEmpty) {
      emit(state.copyWith(status: ConflictStatus.done));
      return;
    }
    emit(
      state.copyWith(
        status: ConflictStatus.ready,
        conflicts: conflicts,
        batch: batch,
      ),
    );
  }

  void _fail(Object e, Emitter<ConflictState> emit, String op) {
    log('$op failed: $e', name: 'ConflictBloc');
    emit(
      state.copyWith(status: ConflictStatus.error, errorMessage: e.toString()),
    );
  }
}
