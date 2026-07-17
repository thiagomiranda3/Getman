// GitSyncBloc events: branch status/switch/create, pull/push/stash/pop/
// drop, fetch (silent auto-fetch tick vs a manual FETCH), and
// ConflictsResolved (bumps reloadToken once the conflict resolver finishes
// a rebase).
import 'package:equatable/equatable.dart';

abstract class GitSyncEvent extends Equatable {
  const GitSyncEvent();
  @override
  List<Object?> get props => [];
}

class LoadBranchStatus extends GitSyncEvent {
  const LoadBranchStatus(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class SwitchBranch extends GitSyncEvent {
  const SwitchBranch(this.root, this.branch);
  final String root;
  final String branch;
  @override
  List<Object?> get props => [root, branch];
}

class CreateBranch extends GitSyncEvent {
  const CreateBranch(this.root, this.branch);
  final String root;
  final String branch;
  @override
  List<Object?> get props => [root, branch];
}

class PullChanges extends GitSyncEvent {
  const PullChanges(
    this.root, {
    this.authorName,
    this.authorEmail,
    this.addRemoteUrl,
  });
  final String root;

  /// Getman-owned commit identity from Settings (see
  /// `GitService.commit`) — threaded through so a rebase that needs to
  /// create a commit still succeeds without a configured OS git identity.
  final String? authorName;
  final String? authorEmail;

  /// When non-null (and non-blank), the bloc adds this URL as the `origin`
  /// remote before pulling — set from the add-remote prompt when the repo
  /// had no remote configured yet.
  final String? addRemoteUrl;
  @override
  List<Object?> get props => [root, authorName, authorEmail, addRemoteUrl];
}

class PushChanges extends GitSyncEvent {
  const PushChanges(this.root, {this.addRemoteUrl});
  final String root;

  /// When non-null (and non-blank), the bloc adds this URL as the `origin`
  /// remote before pushing — set from the add-remote prompt when the repo
  /// had no remote configured yet.
  final String? addRemoteUrl;
  @override
  List<Object?> get props => [root, addRemoteUrl];
}

class StashChanges extends GitSyncEvent {
  const StashChanges(this.root, this.message);
  final String root;
  final String message;
  @override
  List<Object?> get props => [root, message];
}

class PopStash extends GitSyncEvent {
  const PopStash(this.root, this.index);
  final String root;
  final int index;
  @override
  List<Object?> get props => [root, index];
}

class DropStash extends GitSyncEvent {
  const DropStash(this.root, this.index);
  final String root;
  final int index;
  @override
  List<Object?> get props => [root, index];
}

/// `git fetch` — updates remote-tracking refs without touching the working
/// tree. [silent] marks a background auto-fetch tick: a failure (e.g. offline)
/// is logged and swallowed rather than surfaced as an error status, so the
/// branch chip never nags the user for a routine connectivity hiccup. A
/// manual FETCH menu selection leaves it `false` so a real failure (e.g. auth)
/// still shows the GIT ERROR dialog.
class FetchRemote extends GitSyncEvent {
  const FetchRemote(this.root, {this.silent = false, this.addRemoteUrl});
  final String root;
  final bool silent;

  /// When non-null (and non-blank), the bloc adds this URL as the `origin`
  /// remote before fetching — set from the add-remote prompt when the repo
  /// had no remote configured yet.
  final String? addRemoteUrl;
  @override
  List<Object?> get props => [root, silent, addRemoteUrl];
}

/// Dispatched by the conflict resolver after it finishes a rebase
/// (RESOLVE & CONTINUE reaches `RebaseStep.done`). Bumps `reloadToken` so
/// `BranchSyncListener` reloads the merged tree from disk — without this the
/// resolved files sit on disk while the app's Hive tree stays pre-pull, and
/// the next edit's debounced mirror silently reverts the merge.
class ConflictsResolved extends GitSyncEvent {
  const ConflictsResolved(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}
