// ReviewService: abstract gateway for the workspace review/stage/commit
// flow; implemented by WorkspaceReviewService in data/services.
import 'package:getman/features/collections/domain/entities/review_entry.dart';

/// Abstraction the review bloc depends on. Implemented in the data layer by
/// WorkspaceReviewService.
abstract class ReviewService {
  Future<ReviewResult> review(String root);

  /// Stage/unstage takes a list so a select-all is a single git call rather
  /// than one subprocess per entry.
  Future<void> stage(String root, List<String> paths);
  Future<void> unstage(String root, List<String> paths);

  /// [authorName]/[authorEmail] are the Getman-owned commit identity from
  /// Settings (see `GitService.commit`) — passed through so a commit
  /// succeeds even without a configured OS git identity.
  Future<void> commit(
    String root,
    String message, {
    String? authorName,
    String? authorEmail,
  });
  Future<void> init(String root);
}
