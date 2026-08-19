// ReviewBloc events: LoadReview, per-path stage/unstage (StageNode/
// UnstageNode) and select-all/clear-all (StageAll/UnstageAll), SelectEntry
// (diff-pane selection), Commit, and InitRepo (git init). Every event that
// writes to the repo extends the sealed ReviewMutation marker, which
// ReviewBloc handles through a single sequential (queued) channel — see the
// bloc header for why.
import 'package:equatable/equatable.dart';

abstract class ReviewEvent extends Equatable {
  const ReviewEvent();
  @override
  List<Object?> get props => [];
}

/// Marker base for events that WRITE to the git repo (index or history):
/// stage/unstage/commit/init. ReviewBloc registers one sequential handler
/// for this type, so mutations queue behind each other instead of racing —
/// two concurrent index writes contend on `.git/index.lock`, and the loser
/// becomes a silent no-op. Read paths (LoadReview/SelectEntry) stay outside
/// the channel.
sealed class ReviewMutation extends ReviewEvent {
  const ReviewMutation();
}

class LoadReview extends ReviewEvent {
  const LoadReview(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class StageNode extends ReviewMutation {
  const StageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

class UnstageNode extends ReviewMutation {
  const UnstageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

/// Stages every currently-unstaged entry (the select-all action).
class StageAll extends ReviewMutation {
  const StageAll(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

/// Unstages every currently-staged entry (the clear-selection action).
class UnstageAll extends ReviewMutation {
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

class Commit extends ReviewMutation {
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

class InitRepo extends ReviewMutation {
  const InitRepo(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}
