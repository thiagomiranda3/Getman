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
}
