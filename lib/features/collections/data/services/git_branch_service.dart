import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';

/// Composes [GitService] + [WorkspaceSyncService] into the branch/sync
/// operations. Pure of `dart:io` — all git access goes through [GitService].
class GitBranchService implements BranchService {
  GitBranchService(this._git, this._sync);
  final GitService _git;
  final WorkspaceSyncService _sync;

  /// Runs the pending Hive → disk mirror to completion, and throws when it
  /// could not be written (revoked sandbox grant, unmounted drive, ...).
  ///
  /// Every op that reads or mutates the working tree goes through this first:
  /// running git over a tree that is missing the user's last edits would both
  /// mis-report the state and, on a checkout, silently lose those edits.
  Future<void> _flushOrThrow() async {
    if (!await _sync.flushPending()) {
      throw GitException(
        'Could not write the workspace to disk — aborting so git does not '
        'run over a stale tree. Check the workspace folder is writable.',
      );
    }
  }

  @override
  Future<BranchStatus> status(String root) async {
    if (!await _git.isAvailable()) return BranchStatus.none;
    if (!await _git.isRepo(root)) return BranchStatus.none;
    final ab = await _git.aheadBehind(root);
    final stashes = await _git.stashList(root);
    return BranchStatus(
      isRepo: true,
      current: await _git.currentBranch(root),
      branches: await _git.branches(root),
      ahead: ab.ahead,
      behind: ab.behind,
      hasRemote: await _git.hasRemote(root),
      stashes: [
        for (final s in stashes) StashInfo(index: s.index, message: s.message),
      ],
    );
  }

  @override
  Future<bool> isDirty(String root) async {
    await _flushOrThrow();
    return (await _git.status(root)).isNotEmpty;
  }

  /// Flushes the pending mirror, then runs [action] with mirroring **gated
  /// off**. Order matters: the flush lands the write armed *before* the op (or
  /// aborts), and the suspension drops any edit made *during* it — whose
  /// debounce would otherwise fire after the checkout and mirror the old
  /// branch's tree onto the new one. The suspension is lifted even if git
  /// throws. Generic so callers that need the action's result (e.g. `pull`'s
  /// [PullOutcome]) don't need a second helper.
  Future<T> _runOnTree<T>(Future<T> Function() action) async {
    await _flushOrThrow();
    return _sync.withMirroringSuspended(action);
  }

  @override
  Future<void> switchTo(String root, String branch) =>
      _runOnTree(() => _git.switchBranch(root, branch));

  // No suspension here: `git switch -c` creates the branch at HEAD, it never
  // rewrites the working tree — an edit made mid-create belongs on disk (on
  // the branch just created) and must still be mirrored. Suspending would
  // *drop* it: suspension discards the pending forest, and no reload follows a
  // create (nothing on disk changed), so the edit would live on in Hive while
  // disk silently diverged — until the next switch reloaded over it.
  // No suspension here: `git switch -c` creates the branch at HEAD, it never
  // rewrites the working tree — an edit made mid-create belongs on disk (on
  // the branch just created) and must still be mirrored. Suspending would
  // *drop* it: suspension discards the pending forest, and no reload follows a
  // create (nothing on disk changed), so the edit would live on in Hive while
  // disk silently diverged — until the next switch reloaded over it.
  @override
  Future<void> create(String root, String branch) async {
    await _flushOrThrow();
    await _git.createBranch(root, branch);
  }

  @override
  Future<PullOutcome> pull(
    String root, {
    String? authorName,
    String? authorEmail,
  }) => _runOnTree(
    () => _git.pull(root, authorName: authorName, authorEmail: authorEmail),
  );

  // No suspension here: `git push` reads the working tree, it never rewrites
  // it — an edit made mid-push belongs on disk and must still be mirrored.
  @override
  Future<void> push(String root) async {
    await _flushOrThrow();
    await _git.push(root, setUpstream: !await _git.hasUpstream(root));
  }

  @override
  Future<void> stash(String root, String message) =>
      _runOnTree(() => _git.stashPush(root, message));

  @override
  Future<void> popStash(String root, int index) =>
      _runOnTree(() => _git.stashPop(root, index));

  // No flush here, deliberately: `git stash drop` only mutates the stash ref —
  // it never touches the working tree — so a pending mirror write cannot race
  // it. This omission is intentional; do not "fix" it by adding a flush.
  @override
  Future<void> dropStash(String root, int index) => _git.stashDrop(root, index);

  // No flush/suspension here, deliberately: `git fetch` only updates
  // remote-tracking refs — it never touches the working tree — so it cannot
  // race a pending mirror write.
  @override
  Future<void> fetch(String root) => _git.fetch(root);
}
