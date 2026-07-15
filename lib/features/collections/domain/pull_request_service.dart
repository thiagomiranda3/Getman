import 'package:getman/features/collections/domain/entities/pull_request.dart';

/// Domain gateway for GitHub pull-request operations. The data layer backs this
/// with the `gh` CLI; the bloc depends only on this abstraction.
abstract class PullRequestService {
  /// Whether `gh` is installed and authenticated for [root].
  Future<GhAvailability> availability(String root);

  /// Open PRs for the repo in [root].
  Future<List<PullRequestEntity>> list(String root);

  /// Pushes the current branch (setting upstream on first push) and opens a PR.
  Future<PullRequestRef> create(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  });

  /// The default base branch to preselect in the create form, or null.
  Future<String?> defaultBase(String root);
}
