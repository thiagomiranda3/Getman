import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';

enum GitSyncStatus { initial, loading, ready, busy, error }

class GitSyncState extends Equatable {
  const GitSyncState({
    this.status = GitSyncStatus.initial,
    this.branch = BranchStatus.none,
    this.errorMessage,
    this.reloadToken = 0,
  });

  final GitSyncStatus status;
  final BranchStatus branch;
  final String? errorMessage;

  /// Bumped after any operation that changed the files on disk (switch, pull,
  /// stash, pop). The widget-layer BranchSyncListener reloads the collections
  /// tree when it changes — blocs never talk to each other directly.
  final int reloadToken;

  bool get isBusy => status == GitSyncStatus.busy;

  GitSyncState copyWith({
    GitSyncStatus? status,
    BranchStatus? branch,
    String? errorMessage,
    int? reloadToken,
  }) {
    final next = status ?? this.status;
    return GitSyncState(
      status: next,
      branch: branch ?? this.branch,
      // Gated on the *resolved* status, not the parameter: an error state
      // copied without a status (e.g. copyWith(branch: …)) must keep its
      // message. Cleared on every non-error emission — a stale banner
      // outlives its cause.
      errorMessage: next == GitSyncStatus.error
          ? (errorMessage ?? this.errorMessage)
          : null,
      reloadToken: reloadToken ?? this.reloadToken,
    );
  }

  @override
  List<Object?> get props => [status, branch, errorMessage, reloadToken];
}
