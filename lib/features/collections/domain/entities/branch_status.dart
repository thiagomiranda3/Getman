// Domain entities for git branch/stash state (BranchStatus + StashInfo),
// consumed by the collections branch chip UI.
import 'package:equatable/equatable.dart';

/// One stashed change set. Domain-owned (the domain layer never depends on
/// infrastructure types).
class StashInfo extends Equatable {
  const StashInfo({required this.index, required this.message});
  final int index;
  final String message;

  @override
  List<Object?> get props => [index, message];
}

/// The git state of the workspace, as the branch chip needs it.
class BranchStatus extends Equatable {
  const BranchStatus({
    this.isRepo = false,
    this.current,
    this.branches = const [],
    this.ahead = 0,
    this.behind = 0,
    this.hasRemote = false,
    this.stashes = const [],
    this.rebaseInProgress = false,
  });

  /// Nothing to show: not a repo (or git is unavailable).
  static const none = BranchStatus();

  final bool isRepo;
  final String? current;
  final List<String> branches;
  final int ahead;
  final int behind;
  final bool hasRemote;
  final List<StashInfo> stashes;

  /// A rebase is paused mid-conflict (e.g. a pull halted on conflicts).
  /// Durable — re-read from the repo on every status load — unlike the
  /// edge-delivered `GitSyncState.conflictToken` bump, which is lost when the
  /// branch chip is unmounted (or the app restarts) at bump time. While true,
  /// HEAD is typically detached ([current] is null), so this flag is what
  /// keeps the chip rendered with a path back into the conflict resolver.
  final bool rebaseInProgress;

  int get stashCount => stashes.length;

  @override
  List<Object?> get props => [
    isRepo,
    current,
    branches,
    ahead,
    behind,
    hasRemote,
    stashes,
    rebaseInProgress,
  ];
}
