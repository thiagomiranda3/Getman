import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/git/git_service.dart' show PullOutcome;
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';

/// Drives branch + sync over [BranchService]. Errors are surfaced in state
/// (never only logged) — a silent failure here looks like a no-op to the user.
///
/// Every working-tree op on [BranchService] flushes the pending Hive → disk
/// mirror first and throws when that write failed (workspace not writable), so
/// those failures land in the error state through the same paths as git's own.
class GitSyncBloc extends Bloc<GitSyncEvent, GitSyncState> {
  GitSyncBloc({required this._service}) : super(const GitSyncState()) {
    on<LoadBranchStatus>(_onLoad);
    on<SwitchBranch>(_onSwitch);
    on<CreateBranch>(_onCreate);
    on<PullChanges>(_onPull);
    on<PushChanges>(_onPush);
    on<StashChanges>(_onStash);
    on<PopStash>(_onPop);
    on<DropStash>(_onDrop);
    on<FetchRemote>(_onFetch);
    on<ConflictsResolved>(_onResolved);
  }

  final BranchService _service;

  /// Drops an event while another op is in flight — the bloc is effectively
  /// droppable. A second op would run git against a working tree the first one
  /// is mid-way through changing, and whichever finished last would overwrite
  /// the other's terminal state. Every handler always emits a terminal
  /// (ready/error) state in a try/catch, so [GitSyncStatus.busy] is always
  /// exited and this cannot deadlock.
  bool _dropWhileBusy(String op) {
    if (state.status != GitSyncStatus.busy) return false;
    log('$op ignored: another operation is in flight', name: 'GitSyncBloc');
    return true;
  }

  Future<void> _onLoad(
    LoadBranchStatus event,
    Emitter<GitSyncState> emit,
  ) async {
    if (_dropWhileBusy('load')) return;
    emit(state.copyWith(status: GitSyncStatus.loading));
    await _refresh(event.root, emit);
  }

  /// Re-reads git state.
  Future<void> _refresh(String root, Emitter<GitSyncState> emit) async {
    try {
      final branch = await _service.status(root);
      emit(state.copyWith(status: GitSyncStatus.ready, branch: branch));
    } on Object catch (e) {
      _fail(e, emit, 'status');
    }
  }

  void _fail(Object e, Emitter<GitSyncState> emit, String op) {
    log('$op failed: $e', name: 'GitSyncBloc');
    emit(
      state.copyWith(status: GitSyncStatus.error, errorMessage: e.toString()),
    );
  }

  /// Runs [action], then refreshes.
  ///
  /// When [changedDisk] is true, [GitSyncState.reloadToken] is bumped as soon
  /// as [action] returns — git has already rewritten the working tree at that
  /// point, so the reload must not hinge on the follow-up status() read (which
  /// can fail on e.g. `.git/index.lock` contention right after a checkout).
  Future<void> _run(
    String root,
    Emitter<GitSyncState> emit,
    String op,
    Future<void> Function() action, {
    bool changedDisk = false,
  }) async {
    emit(state.copyWith(status: GitSyncStatus.busy));
    try {
      await action();
    } on Object catch (e) {
      _fail(e, emit, op);
      return;
    }
    if (changedDisk) {
      emit(
        state.copyWith(
          status: GitSyncStatus.busy,
          reloadToken: state.reloadToken + 1,
        ),
      );
    }
    await _refresh(root, emit);
  }

  Future<void> _onSwitch(SwitchBranch event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('switch')) return;
    emit(state.copyWith(status: GitSyncStatus.busy));
    final bool dirty;
    try {
      dirty = await _service.isDirty(event.root);
    } on Object catch (e) {
      _fail(e, emit, 'switch');
      return;
    }
    if (dirty) {
      // Refuse rather than clobber. The widget offers commit or stash.
      emit(
        state.copyWith(
          status: GitSyncStatus.error,
          errorMessage: 'You have uncommitted changes',
        ),
      );
      return;
    }
    await _run(
      event.root,
      emit,
      'switch',
      () => _service.switchTo(event.root, event.branch),
      changedDisk: true,
    );
  }

  Future<void> _onCreate(
    CreateBranch event,
    Emitter<GitSyncState> emit,
  ) async {
    if (_dropWhileBusy('create')) return;
    await _run(
      event.root,
      emit,
      'create',
      () => _service.create(event.root, event.branch),
    );
  }

  /// Unlike the other mutating ops, `pull` doesn't go through the uniform
  /// [_run] helper: it needs the [PullOutcome] to decide *which* token to
  /// bump. A clean pull behaves like every other disk-changing op
  /// (`reloadToken`); a conflicted pull leaves the tree mid-rebase — it must
  /// NOT bump `reloadToken` (nothing to reload yet, the rebase is paused) and
  /// instead bumps `conflictToken` so the widget layer opens the resolver.
  /// Either way a terminal `ready` state is always emitted so the bloc is
  /// never left stuck on `busy`.
  Future<void> _onPull(PullChanges event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('pull')) return;
    emit(state.copyWith(status: GitSyncStatus.busy));
    final PullOutcome outcome;
    try {
      outcome = await _service.pull(event.root);
    } on Object catch (e) {
      _fail(e, emit, 'pull');
      return;
    }
    emit(
      state.copyWith(
        status: GitSyncStatus.busy,
        reloadToken: outcome == PullOutcome.clean
            ? state.reloadToken + 1
            : null,
        conflictToken: outcome == PullOutcome.conflicted
            ? state.conflictToken + 1
            : null,
      ),
    );
    await _refresh(event.root, emit);
  }

  Future<void> _onFetch(FetchRemote event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('fetch')) return;
    emit(state.copyWith(status: GitSyncStatus.busy));
    try {
      await _service.fetch(event.root);
    } on Object catch (e) {
      if (event.silent) {
        // Auto-fetch runs unattended every few minutes — being offline is
        // normal, not an error. Log only and fall through to the refresh so
        // the bloc still lands on a terminal `ready` state.
        log('fetch (silent) failed: $e', name: 'GitSyncBloc');
      } else {
        _fail(e, emit, 'fetch');
        return;
      }
    }
    await _refresh(event.root, emit);
  }

  /// The conflict resolver finished a rebase (RESOLVE & CONTINUE reached
  /// `RebaseStep.done`). Nothing here touches git directly — the resolved
  /// files are already on disk — this only needs to bump `reloadToken` so
  /// `BranchSyncListener` reloads the merged tree, using the same
  /// `changedDisk: true` pattern as every other disk-changing op.
  Future<void> _onResolved(
    ConflictsResolved event,
    Emitter<GitSyncState> emit,
  ) async {
    if (_dropWhileBusy('resolved')) return;
    await _run(event.root, emit, 'resolved', () async {}, changedDisk: true);
  }

  Future<void> _onPush(PushChanges event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('push')) return;
    await _run(event.root, emit, 'push', () => _service.push(event.root));
  }

  Future<void> _onStash(StashChanges event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('stash')) return;
    await _run(
      event.root,
      emit,
      'stash',
      () => _service.stash(event.root, event.message),
      changedDisk: true,
    );
  }

  Future<void> _onPop(PopStash event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('pop stash')) return;
    await _run(
      event.root,
      emit,
      'pop stash',
      () => _service.popStash(event.root, event.index),
      changedDisk: true,
    );
  }

  Future<void> _onDrop(DropStash event, Emitter<GitSyncState> emit) async {
    if (_dropWhileBusy('drop stash')) return;
    await _run(
      event.root,
      emit,
      'drop stash',
      () => _service.dropStash(event.root, event.index),
    );
  }
}
