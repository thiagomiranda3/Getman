import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';

class PullRequestsBloc extends Bloc<PullRequestsEvent, PullRequestsState> {
  PullRequestsBloc({required this._service})
    : super(const PullRequestsState()) {
    on<LoadPullRequests>(_onLoad);
    on<CreatePullRequest>(_onCreate);
  }

  final PullRequestService _service;

  /// The workspace root [PullRequestsState.defaultBase] was resolved for.
  String? _defaultBaseRoot;

  Future<void> _onLoad(
    LoadPullRequests event,
    Emitter<PullRequestsState> emit,
  ) async {
    if (_dropWhileBusy('LoadPullRequests')) return;
    emit(state.copyWith(status: PrStatus.loading));
    try {
      final availability = await _service.availability(event.root);
      if (availability != GhAvailability.available) {
        emit(
          state.copyWith(
            status: PrStatus.ready,
            availability: availability,
            prs: const [],
          ),
        );
        return;
      }
      final prs = await _service.list(event.root);
      // Resolve the default base once per workspace (for the create form) —
      // the bloc is app-scoped, so a cache not keyed by root would pre-fill
      // the previous repo's default branch after a workspace switch.
      final String? base;
      if (_defaultBaseRoot == event.root && state.defaultBase != null) {
        base = state.defaultBase;
      } else {
        base = await _service.defaultBase(event.root);
        _defaultBaseRoot = event.root;
      }
      emit(
        state.copyWith(
          status: PrStatus.ready,
          availability: availability,
          prs: prs,
          defaultBase: base,
        ),
      );
    } on Object catch (e) {
      _fail(emit, e);
    }
  }

  Future<void> _onCreate(
    CreatePullRequest event,
    Emitter<PullRequestsState> emit,
  ) async {
    if (_dropWhileBusy('CreatePullRequest')) return;
    emit(state.copyWith(status: PrStatus.creating));
    final PullRequestRef ref;
    try {
      ref = await _service.create(
        event.root,
        base: event.base,
        title: event.title,
        body: event.body,
        draft: event.draft,
      );
    } on Object catch (e) {
      _fail(emit, e);
      return;
    }
    // The PR now exists — surface it (lastCreated) even if the follow-up list
    // refresh fails, so a transient list error can't hide a real PR behind a
    // misleading GIT ERROR.
    List<PullRequestEntity> prs;
    try {
      prs = await _service.list(event.root);
    } on Object catch (e) {
      log('created PR but list refresh failed: $e', name: 'PullRequestsBloc');
      prs = state.prs;
    }
    emit(state.copyWith(status: PrStatus.ready, prs: prs, lastCreated: ref));
  }

  /// Drops a second op while one is running: a concurrent gh call could race
  /// the push/create. Every handler always emits a terminal state, so busy is
  /// always exited — this cannot deadlock.
  bool _dropWhileBusy(String event) {
    if (state.isBusy) {
      log('dropping $event while busy', name: 'PullRequestsBloc');
      return true;
    }
    return false;
  }

  void _fail(Emitter<PullRequestsState> emit, Object error) {
    log('pull-request op failed: $error', name: 'PullRequestsBloc');
    emit(
      state.copyWith(status: PrStatus.error, errorMessage: error.toString()),
    );
  }
}
