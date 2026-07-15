export 'git_service_stub.dart'
    if (dart.library.io) 'git_service_io.dart'
    show createGitService;

/// A change entry from `git status --porcelain`. Statuses are single chars:
/// `' '` unmodified, `'M'` modified, `'A'` added, `'D'` deleted, `'R'` renamed,
/// `'?'` untracked (both columns `'?'`).
class GitStatusEntry {
  const GitStatusEntry({
    required this.indexStatus,
    required this.worktreeStatus,
    required this.path,
    this.renamedFrom,
  });
  final String indexStatus;
  final String worktreeStatus;
  final String path;
  final String? renamedFrom;

  bool get isUntracked => indexStatus == '?' && worktreeStatus == '?';
  bool get isStaged => !isUntracked && indexStatus != ' ';
}

/// A git command failure (non-zero exit, or git missing).
class GitException implements Exception {
  GitException(this.message, {this.exitCode});
  final String message;
  final int? exitCode;
  @override
  String toString() => 'GitException($message)';
}

/// Commits the current branch is ahead of / behind its upstream. Both are 0
/// when the branch has no upstream (a brand-new local branch is normal, not
/// an error).
class AheadBehind {
  const AheadBehind({required this.ahead, required this.behind});
  final int ahead;
  final int behind;

  static const none = AheadBehind(ahead: 0, behind: 0);
}

/// One entry of `git stash list`. [index] is its position (`stash@{index}`).
class StashEntry {
  const StashEntry({required this.index, required this.message});
  final int index;
  final String message;
}

/// The result of a rebase-pull: it either fast-forwarded/rebased cleanly, or
/// it stopped on conflicts that are now sitting in the index for resolution.
enum PullOutcome { clean, conflicted }

/// Drives the system `git` CLI over a workspace directory. The `_io`
/// implementation is the sole `dart:io` importer; web gets the no-op stub.
abstract class GitService {
  Future<bool> isAvailable();
  Future<bool> isRepo(String root);
  Future<void> init(String root);
  Future<String?> currentBranch(String root);
  Future<List<GitStatusEntry>> status(String root);

  /// Content of [path] at HEAD, or null if it does not exist there.
  Future<String?> headContent(String root, String path);

  /// Current working-tree content of [path], or null if it does not exist.
  Future<String?> workingContent(String root, String path);

  Future<void> stage(String root, List<String> paths);
  Future<void> unstage(String root, List<String> paths);
  Future<void> commit(String root, String message);

  /// Local branch names.
  Future<List<String>> branches(String root);

  /// Creates [name] and switches to it (`git switch -c`).
  Future<void> createBranch(String root, String name);

  /// Switches to an existing branch. Throws [GitException] when git refuses
  /// (e.g. the checkout would clobber local changes).
  Future<void> switchBranch(String root, String name);

  /// Whether the repo has at least one remote configured.
  Future<bool> hasRemote(String root);

  /// Ahead/behind counts vs the current branch's upstream.
  Future<AheadBehind> aheadBehind(String root);

  /// Whether the current branch has an upstream configured.
  Future<bool> hasUpstream(String root);

  /// `git pull --rebase`. On a true conflict, the rebase is left **paused**
  /// (see [PullOutcome.conflicted]) so the caller can resolve it — see
  /// [isRebaseInProgress] / [conflictedPaths] / [showStage] /
  /// [writeWorkingFile] / [add] / [rebaseContinue] / [rebaseAbort]. Any other
  /// failure (auth/network/local changes) aborts the rebase before throwing,
  /// so a non-resolvable failed pull leaves the working tree exactly as it
  /// was.
  Future<PullOutcome> pull(String root);

  /// Pushes the current branch. Pass [setUpstream] for a branch that has
  /// never been pushed (`git push -u origin <branch>`).
  Future<void> push(String root, {required bool setUpstream});

  Future<List<StashEntry>> stashList(String root);

  /// Stashes tracked *and* untracked changes (`git stash push -u`), so a
  /// stash-then-switch does not carry a new request onto the target branch.
  Future<void> stashPush(String root, String message);

  Future<void> stashPop(String root, int index);
  Future<void> stashDrop(String root, int index);

  /// Whether a rebase is currently paused (mid-conflict) on [root].
  Future<bool> isRebaseInProgress(String root);

  /// Paths with unresolved merge conflicts (`git diff --name-only
  /// --diff-filter=U`).
  Future<List<String>> conflictedPaths(String root);

  /// Content of [path] at merge stage [stage] (1=base, 2=ours/incoming,
  /// 3=theirs/yours), or null when that stage is absent (e.g. add/add has no
  /// base).
  Future<String?> showStage(String root, String path, int stage);

  /// Overwrites the working-tree copy of [path] with [content] (creating
  /// parent directories as needed). Used to write a resolved conflict.
  Future<void> writeWorkingFile(String root, String path, String content);

  /// Stages [path] (`git add`) — marks a conflict as resolved.
  Future<void> add(String root, String path);

  /// `git rebase --continue`, non-interactively (no editor prompt).
  Future<void> rebaseContinue(String root);

  /// `git rebase --abort` — restores the pre-rebase tree.
  Future<void> rebaseAbort(String root);

  /// `git fetch` — updates remote-tracking refs without touching the working
  /// tree.
  Future<void> fetch(String root);
}
