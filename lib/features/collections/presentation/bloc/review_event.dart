// ReviewBloc events: LoadReview, per-path stage/unstage (StageNode/
// UnstageNode) and select-all/clear-all (StageAll/UnstageAll), SelectEntry
// (diff-pane selection), Commit, and InitRepo (git init).
import 'package:equatable/equatable.dart';

abstract class ReviewEvent extends Equatable {
  const ReviewEvent();
  @override
  List<Object?> get props => [];
}

class LoadReview extends ReviewEvent {
  const LoadReview(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class StageNode extends ReviewEvent {
  const StageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

class UnstageNode extends ReviewEvent {
  const UnstageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

/// Stages every currently-unstaged entry (the select-all action).
class StageAll extends ReviewEvent {
  const StageAll(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

/// Unstages every currently-staged entry (the clear-selection action).
class UnstageAll extends ReviewEvent {
  const UnstageAll(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class SelectEntry extends ReviewEvent {
  const SelectEntry(this.path);
  final String path;
  @override
  List<Object?> get props => [path];
}

class Commit extends ReviewEvent {
  const Commit(this.root, this.message, {this.authorName, this.authorEmail});
  final String root;
  final String message;

  /// Getman-owned commit identity from Settings (see
  /// `GitService.commit`) — threaded through so a commit succeeds even
  /// without a configured OS git identity.
  final String? authorName;
  final String? authorEmail;
  @override
  List<Object?> get props => [root, message, authorName, authorEmail];
}

class InitRepo extends ReviewEvent {
  const InitRepo(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}
