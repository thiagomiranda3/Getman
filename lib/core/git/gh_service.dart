// Abstract GhService talking to GitHub through the `gh` CLI (PR list/create,
// auth status, default branch) — rides on the user's own `gh auth`, Getman
// stores no credentials. Conditional export picks gh_service_io.dart
// (dart:io, the sole `gh`-process boundary) or gh_service_stub.dart (web
// no-op). Also declares PullRequestInfo and GhException.
import 'package:getman/core/git/gh_service_stub.dart'
    if (dart.library.io) 'package:getman/core/git/gh_service_io.dart';

/// Talks to GitHub through the `gh` CLI. The single `dart:io` boundary for
/// `gh` lives in `gh_service_io.dart`; web builds get the stub. Rides on the
/// user's existing `gh auth` — Getman stores no credentials.
abstract class GhService {
  /// `gh --version` succeeds.
  Future<bool> isAvailable();

  /// `gh auth status` succeeds in [root] (a repo dir picks up its host).
  Future<bool> isAuthenticated(String root);

  /// Opens a PR for the current branch. Returns the PR URL printed by
  /// `gh pr create`. Throws [GhException] on any failure (incl. gh trying to
  /// prompt for a remote — we push first so it never should).
  Future<String> createPr(
    String root, {
    required String base,
    required String title,
    required String body,
    required bool draft,
  });

  /// Open PRs for the repo in [root], newest first as gh returns them.
  Future<List<PullRequestInfo>> listPrs(String root);

  /// The repo's default branch name (for the create form's base default), or
  /// null if it can't be determined.
  Future<String?> defaultBranch(String root);
}

GhService createGhService() => createGhServiceImpl();

/// One open pull request as reported by `gh pr list --json`. Primitive/string
/// fields only — the domain layer maps [state]/[checks] to its own enums.
class PullRequestInfo {
  const PullRequestInfo({
    required this.number,
    required this.title,
    required this.state,
    required this.url,
    required this.isDraft,
    required this.checks,
  });

  final int number;
  final String title;

  /// Raw gh state: `OPEN` / `MERGED` / `CLOSED`.
  final String state;
  final String url;
  final bool isDraft;

  /// Rolled-up check verdict: `none` / `pending` / `passing` / `failing`.
  final String checks;
}

class GhException implements Exception {
  GhException(this.message, {this.exitCode});
  final String message;
  final int? exitCode;

  @override
  String toString() => 'GhException($exitCode): $message';
}
