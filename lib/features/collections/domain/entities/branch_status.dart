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
  ];
}
