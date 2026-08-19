// ReviewBloc: drives the Review Changes dialog over ReviewService. git's
// index is the source of truth, so every stage/unstage/commit mutation
// re-dispatches LoadReview rather than patching state locally.
//
// Concurrency: every ReviewMutation runs through ONE sequential channel —
// two concurrent index writes contend on `.git/index.lock` and the loser
// becomes a silent no-op. Unlike the droppable GitSyncBloc/ConflictBloc
// (heavyweight working-tree ops), mutations here QUEUE: they are cheap
// index writes dispatched from per-row checkboxes the dialog never
// disables, so dropping a click would be exactly the silent no-op the
// guard exists to prevent. LoadReview is latest-wins (_loadSeq): loads may
// still overlap and resolve out of order, and a superseded load must not
// overwrite the newer snapshot. Mutation failures surface as an error
// state (sibling-bloc rule: never only logged) with no follow-up reload —
// the failed write left the index unchanged, and a reload's `ready` would
// wipe the error banner.
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/git/git_service.dart' show GitException;
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';

/// bloc_concurrency's `sequential()` (not a dependency of this app):
/// processes one event at a time, queueing later ones in dispatch order.
EventTransformer<E> _sequential<E>() =>
    (events, mapper) => events.asyncExpand(mapper);

/// Drives the Review Changes dialog over [ReviewService]. git's index
/// is the source of truth, so stage/unstage/commit re-run the review.
/// Mutations are serialized, loads are latest-wins — see the file header.
class ReviewBloc extends Bloc<ReviewEvent, ReviewState> {
  ReviewBloc({required this._service}) : super(const ReviewState()) {
    on<LoadReview>(_onLoad);
    on<ReviewMutation>(_onMutation, transformer: _sequential());
    on<SelectEntry>(_onSelect);
  }

  final ReviewService _service;

  /// Monotonic id of the newest LoadReview — an older in-flight load
  /// compares against it after awaiting and discards its stale snapshot.
  int _loadSeq = 0;

  Future<void> _onLoad(LoadReview event, Emitter<ReviewState> emit) async {
    final seq = ++_loadSeq;
    emit(state.copyWith(status: ReviewStatus.loading));
    try {
      final r = await _service.review(event.root);
      if (seq != _loadSeq) return; // Superseded by a newer load.
      final selected = r.entries.any((e) => e.path == state.selectedPath)
          ? state.selectedPath
          : r.entries.isNotEmpty
          ? r.entries.first.path
          : null;
      emit(
        state.copyWith(
          status: ReviewStatus.ready,
          gitAvailable: r.gitAvailable,
          repoExists: r.repoExists,
          branch: r.branch,
          entries: r.entries,
          selectedPath: selected,
        ),
      );
    } on Object catch (e) {
      if (seq != _loadSeq) return; // Superseded by a newer load.
      _fail(e, emit, 'review load');
    }
  }

  /// Single sequential entry point for every repo-writing event — see the
  /// file header for why these queue instead of dropping or racing.
  Future<void> _onMutation(
    ReviewMutation event,
    Emitter<ReviewState> emit,
  ) => switch (event) {
    StageNode() => _onStage(event, emit),
    UnstageNode() => _onUnstage(event, emit),
    StageAll() => _onStageAll(event, emit),
    UnstageAll() => _onUnstageAll(event, emit),
    Commit() => _onCommit(event, emit),
    InitRepo() => _onInit(event, emit),
  };

  Future<void> _onStage(StageNode event, Emitter<ReviewState> emit) async {
    try {
      await _service.stage(event.root, [event.path]);
    } on Object catch (e) {
      _fail(e, emit, 'stage');
      return;
    }
    add(LoadReview(event.root));
  }

  Future<void> _onUnstage(UnstageNode event, Emitter<ReviewState> emit) async {
    try {
      await _service.unstage(event.root, [event.path]);
    } on Object catch (e) {
      _fail(e, emit, 'unstage');
      return;
    }
    add(LoadReview(event.root));
  }

  Future<void> _onStageAll(StageAll event, Emitter<ReviewState> emit) async {
    final paths = state.entries
        .where((e) => !e.staged)
        .map((e) => e.path)
        .toList();
    if (paths.isEmpty) return;
    try {
      await _service.stage(event.root, paths);
    } on Object catch (e) {
      _fail(e, emit, 'stage all');
      return;
    }
    add(LoadReview(event.root));
  }

  Future<void> _onUnstageAll(
    UnstageAll event,
    Emitter<ReviewState> emit,
  ) async {
    final paths = state.entries
        .where((e) => e.staged)
        .map((e) => e.path)
        .toList();
    if (paths.isEmpty) return;
    try {
      await _service.unstage(event.root, paths);
    } on Object catch (e) {
      _fail(e, emit, 'unstage all');
      return;
    }
    add(LoadReview(event.root));
  }

  void _onSelect(SelectEntry event, Emitter<ReviewState> emit) {
    emit(state.copyWith(selectedPath: event.path));
  }

  Future<void> _onCommit(Commit event, Emitter<ReviewState> emit) async {
    emit(state.copyWith(status: ReviewStatus.committing));
    try {
      await _service.commit(
        event.root,
        event.message,
        authorName: event.authorName,
        authorEmail: event.authorEmail,
      );
    } on Object catch (e) {
      if (e is GitException && GitException.isMissingIdentity(e.message)) {
        log('commit failed: $e', name: 'ReviewBloc');
        emit(state.copyWith(status: ReviewStatus.needsIdentity));
      } else {
        _fail(e, emit, 'commit');
      }
      return;
    }
    add(LoadReview(event.root));
  }

  Future<void> _onInit(InitRepo event, Emitter<ReviewState> emit) async {
    try {
      await _service.init(event.root);
    } on Object catch (e) {
      _fail(e, emit, 'init');
      return;
    }
    add(LoadReview(event.root));
  }

  void _fail(Object e, Emitter<ReviewState> emit, String op) {
    log('$op failed: $e', name: 'ReviewBloc');
    emit(
      state.copyWith(status: ReviewStatus.error, errorMessage: e.toString()),
    );
  }
}
