import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';

/// Drives the Review Changes dialog over [ReviewService]. git's index
/// is the source of truth, so stage/unstage/commit re-run the review.
class ReviewBloc extends Bloc<ReviewEvent, ReviewState> {
  ReviewBloc({required this._service}) : super(const ReviewState()) {
    on<LoadReview>(_onLoad);
    on<StageNode>(_onStage);
    on<UnstageNode>(_onUnstage);
    on<SelectEntry>(_onSelect);
    on<Commit>(_onCommit);
    on<InitRepo>(_onInit);
  }

  final ReviewService _service;

  Future<void> _onLoad(LoadReview event, Emitter<ReviewState> emit) async {
    emit(state.copyWith(status: ReviewStatus.loading));
    try {
      final r = await _service.review(event.root);
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
      log('review load failed: $e', name: 'ReviewBloc');
      emit(
        state.copyWith(status: ReviewStatus.error, errorMessage: e.toString()),
      );
    }
  }

  Future<void> _onStage(StageNode event, Emitter<ReviewState> emit) async {
    try {
      await _service.stage(event.root, event.path);
    } on Object catch (e) {
      log('stage failed: $e', name: 'ReviewBloc');
    }
    add(LoadReview(event.root));
  }

  Future<void> _onUnstage(UnstageNode event, Emitter<ReviewState> emit) async {
    try {
      await _service.unstage(event.root, event.path);
    } on Object catch (e) {
      log('unstage failed: $e', name: 'ReviewBloc');
    }
    add(LoadReview(event.root));
  }

  void _onSelect(SelectEntry event, Emitter<ReviewState> emit) {
    emit(state.copyWith(selectedPath: event.path));
  }

  Future<void> _onCommit(Commit event, Emitter<ReviewState> emit) async {
    emit(state.copyWith(status: ReviewStatus.committing));
    try {
      await _service.commit(event.root, event.message);
    } on Object catch (e) {
      log('commit failed: $e', name: 'ReviewBloc');
      emit(
        state.copyWith(status: ReviewStatus.error, errorMessage: e.toString()),
      );
      return;
    }
    add(LoadReview(event.root));
  }

  Future<void> _onInit(InitRepo event, Emitter<ReviewState> emit) async {
    try {
      await _service.init(event.root);
    } on Object catch (e) {
      log('init failed: $e', name: 'ReviewBloc');
      emit(
        state.copyWith(status: ReviewStatus.error, errorMessage: e.toString()),
      );
      return;
    }
    add(LoadReview(event.root));
  }
}
