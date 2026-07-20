// ConflictBloc events: load a rebase-halt's conflict batch (LoadConflicts),
// apply resolutions and continue the rebase (ResolveAndContinue), or abort
// it (AbortRebase).
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';

abstract class ConflictEvent extends Equatable {
  const ConflictEvent();

  @override
  List<Object?> get props => [];
}

/// Loads the current batch of conflicted files for an in-progress rebase.
class LoadConflicts extends ConflictEvent {
  const LoadConflicts(this.root);
  final String root;

  @override
  List<Object?> get props => [root];
}

/// Applies [resolutions], stages them, and continues the rebase.
class ResolveAndContinue extends ConflictEvent {
  const ResolveAndContinue(
    this.root,
    this.resolutions, {
    this.authorName,
    this.authorEmail,
  });
  final String root;
  final List<FileResolution> resolutions;

  /// Getman-owned commit identity from Settings (see
  /// `GitService.commit`) — threaded through so the commit
  /// `rebase --continue` creates still succeeds without a configured OS git
  /// identity.
  final String? authorName;
  final String? authorEmail;

  @override
  List<Object?> get props => [root, resolutions, authorName, authorEmail];
}

/// Aborts the in-progress rebase, restoring the pre-pull state.
class AbortRebase extends ConflictEvent {
  const AbortRebase(this.root);
  final String root;

  @override
  List<Object?> get props => [root];
}
