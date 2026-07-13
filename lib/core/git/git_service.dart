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

  /// `git pull --rebase`. On conflict the rebase is **aborted** before
  /// throwing, so a failed pull leaves the working tree exactly as it was —
  /// Getman has no conflict-resolution UI yet (Spec D).
  Future<void> pull(String root);

  /// Pushes the current branch. Pass [setUpstream] for a branch that has
  /// never been pushed (`git push -u origin <branch>`).
  Future<void> push(String root, {required bool setUpstream});
}
