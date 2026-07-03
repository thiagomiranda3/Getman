import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

enum NodeKind { request, folder, workspaceOrder }

enum ChangeType { added, modified, deleted }

/// One reviewable change: a node (request/folder/order file), how it changed,
/// whether it is staged in the git index, and its semantic diff.
class ReviewEntry extends Equatable {
  const ReviewEntry({
    required this.path,
    required this.nodeKind,
    required this.changeType,
    required this.displayName,
    required this.staged,
    required this.diff,
  });
  final String path;
  final NodeKind nodeKind;
  final ChangeType changeType;
  final String displayName;
  final bool staged;
  final SemanticDiff diff;

  @override
  List<Object?> get props => [
    path,
    nodeKind,
    changeType,
    displayName,
    staged,
    diff,
  ];
}

/// The result of reviewing a workspace: git availability + the change set.
class ReviewResult extends Equatable {
  const ReviewResult({
    required this.gitAvailable,
    required this.repoExists,
    required this.branch,
    required this.entries,
  });
  final bool gitAvailable;
  final bool repoExists;
  final String? branch;
  final List<ReviewEntry> entries;

  static const empty = ReviewResult(
    gitAvailable: false,
    repoExists: false,
    branch: null,
    entries: [],
  );

  @override
  List<Object?> get props => [gitAvailable, repoExists, branch, entries];
}
