// ConflictBloc state: status (initial/loading/ready/resolving/done/error),
// the current batch of FileConflicts, and a 0-based batch counter driving
// the dialog's "commit N" header.
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';

/// `ready` is the only non-busy, non-terminal status: the dialog shows the
/// current batch of conflicts and waits for the user to resolve them.
enum ConflictStatus { initial, loading, ready, resolving, done, error }

class ConflictState extends Equatable {
  const ConflictState({
    this.status = ConflictStatus.initial,
    this.conflicts = const [],
    this.batch = 0,
    this.errorMessage,
    this.editsStashed = false,
  });

  final ConflictStatus status;

  /// The current batch of conflicted files (one rebase-halt's worth).
  final List<FileConflict> conflicts;

  /// 0-based commit index — bumped each time a resolve+continue surfaces
  /// another commit's conflicts, for the dialog's "commit N" header.
  final int batch;

  final String? errorMessage;

  /// Only meaningful with [ConflictStatus.done]: the rebase finished but the
  /// user's uncommitted edits (the pull's autostash) conflicted on re-apply
  /// and were kept in `stash@{0}` (`RebaseStep.doneEditsStashed`) — the
  /// dialog tells the user where their edits went instead of a plain
  /// "Conflicts resolved."
  final bool editsStashed;

  bool get isBusy =>
      status == ConflictStatus.loading || status == ConflictStatus.resolving;

  ConflictState copyWith({
    ConflictStatus? status,
    List<FileConflict>? conflicts,
    int? batch,
    String? errorMessage,
    bool? editsStashed,
  }) {
    final next = status ?? this.status;
    return ConflictState(
      status: next,
      conflicts: conflicts ?? this.conflicts,
      batch: batch ?? this.batch,
      // Only an error state keeps a message; anything else clears it.
      errorMessage: next == ConflictStatus.error
          ? (errorMessage ?? this.errorMessage)
          : null,
      // Same idea: the flag only survives into a done state.
      editsStashed: next == ConflictStatus.done && (editsStashed ?? false),
    );
  }

  @override
  List<Object?> get props => [
    status,
    conflicts,
    batch,
    errorMessage,
    editsStashed,
  ];
}
