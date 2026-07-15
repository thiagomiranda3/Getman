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
  const ResolveAndContinue(this.root, this.resolutions);
  final String root;
  final List<FileResolution> resolutions;

  @override
  List<Object?> get props => [root, resolutions];
}

/// Aborts the in-progress rebase, restoring the pre-pull state.
class AbortRebase extends ConflictEvent {
  const AbortRebase(this.root);
  final String root;

  @override
  List<Object?> get props => [root];
}
