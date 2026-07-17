// BranchService: abstract gateway for git branch/stash/remote/sync
// operations; implemented by GitBranchService in data/services.
import 'package:getman/core/git/git_service.dart' show PullOutcome;
import 'package:getman/features/collections/domain/entities/branch_status.dart';

/// Branch + sync operations over the git workspace. The bloc depends on this
/// abstraction, never on the concrete data-layer implementation.
abstract class BranchService {
  Future<BranchStatus> status(String root);

  /// Whether the workspace has uncommitted changes. Flushes any pending
  /// mirror write first, so the answer reflects what is really on disk.
  Future<bool> isDirty(String root);

  Future<void> switchTo(String root, String branch);
  Future<void> create(String root, String branch);

  /// Adds a remote (`git remote add <name> <url>`) — used when the user
  /// supplies a URL from the add-remote prompt to enable pull/push/fetch on a
  /// repo that has none yet.
  Future<void> addRemote(String root, String name, String url);

  /// `git pull --rebase`. Returns [PullOutcome.conflicted] when the rebase
  /// halted on a true conflict — the working tree is left mid-rebase for the
  /// conflict-resolution flow, not rolled back. [authorName]/[authorEmail]
  /// are the Getman-owned commit identity from Settings (see
  /// `GitService.commit`) — threaded through so a rebase that needs to
  /// create a commit still succeeds without a configured OS git identity.
  Future<PullOutcome> pull(
    String root, {
    String? authorName,
    String? authorEmail,
  });
  Future<void> push(String root);
  Future<void> stash(String root, String message);
  Future<void> popStash(String root, int index);
  Future<void> dropStash(String root, int index);

  /// `git fetch` — updates remote-tracking refs without touching the working
  /// tree (manual FETCH action + the auto-fetch background loop).
  Future<void> fetch(String root);
}
