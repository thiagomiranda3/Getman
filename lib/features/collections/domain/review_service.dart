import 'package:getman/features/collections/domain/entities/review_entry.dart';

/// Abstraction the review bloc depends on. Implemented in the data layer by
/// WorkspaceReviewService.
abstract class ReviewService {
  Future<ReviewResult> review(String root);
  Future<void> stage(String root, String path);
  Future<void> unstage(String root, String path);
  Future<void> commit(String root, String message);
  Future<void> init(String root);
}
