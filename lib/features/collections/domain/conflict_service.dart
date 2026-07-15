import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';

/// Orchestrates `git pull --rebase` conflict resolution: field-level 3-way
/// merge where possible, whole-file resolution otherwise. Implementations
/// live in the data layer (they shell out to git via [GitService]); this
/// abstraction is what `ConflictBloc` depends on.
abstract class ConflictService {
  /// Runs `git pull --rebase` and reports whether it landed clean or halted
  /// with conflicts to resolve.
  Future<PullOutcome> pullOrConflict(String root);

  /// The conflicted files of an in-progress rebase, classified and — where
  /// possible — pre-merged field-by-field.
  Future<List<FileConflict>> currentConflicts(String root);

  /// Applies the user's [resolutions] to the working tree and stages them.
  Future<void> resolve(String root, List<FileResolution> resolutions);

  /// Continues an in-progress rebase after conflicts are staged.
  /// [authorName]/[authorEmail] are the Getman-owned commit identity from
  /// Settings (see `GitService.commit`) — threaded through so the commit
  /// `rebase --continue` creates still succeeds without a configured OS git
  /// identity.
  Future<RebaseStep> continueRebase(
    String root, {
    String? authorName,
    String? authorEmail,
  });

  /// Aborts an in-progress rebase, restoring the pre-pull state.
  Future<void> abort(String root);

  /// Fetches from the remote without merging (manual FETCH action + the
  /// auto-fetch background loop).
  Future<void> fetch(String root);
}
