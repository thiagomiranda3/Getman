import 'package:equatable/equatable.dart';

/// A PR's lifecycle state (only `open` is listed in v1, but the mapping is
/// total so a created PR and future scopes are covered).
enum PrState { open, merged, closed }

/// Rolled-up CI verdict for a PR's head commit.
enum PrChecks { none, pending, passing, failing }

/// Whether the `gh` CLI can be used right now.
enum GhAvailability { available, notInstalled, notAuthenticated }

class PullRequestEntity extends Equatable {
  const PullRequestEntity({
    required this.number,
    required this.title,
    required this.state,
    required this.url,
    required this.isDraft,
    required this.checks,
  });

  final int number;
  final String title;
  final PrState state;
  final String url;
  final bool isDraft;
  final PrChecks checks;

  @override
  List<Object?> get props => [number, title, state, url, isDraft, checks];
}

/// The just-created PR — its number (parsed from the url) and url.
class PullRequestRef extends Equatable {
  const PullRequestRef({required this.number, required this.url});

  final int number;
  final String url;

  @override
  List<Object?> get props => [number, url];
}
