import 'package:equatable/equatable.dart';

abstract class PullRequestsEvent extends Equatable {
  const PullRequestsEvent();

  @override
  List<Object?> get props => [];
}

/// Check availability, then (if ready) load open PRs for [root].
class LoadPullRequests extends PullRequestsEvent {
  const LoadPullRequests(this.root);
  final String root;

  @override
  List<Object?> get props => [root];
}

class CreatePullRequest extends PullRequestsEvent {
  const CreatePullRequest(
    this.root, {
    required this.base,
    required this.title,
    required this.body,
    required this.draft,
  });

  final String root;
  final String base;
  final String title;
  final String body;
  final bool draft;

  @override
  List<Object?> get props => [root, base, title, body, draft];
}
