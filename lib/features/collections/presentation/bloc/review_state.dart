// ReviewBloc state: git availability/repo existence, current branch, the
// reviewable ReviewEntry list, the selected entry's path, and status
// (including needsIdentity — a commit failed for want of a configured git
// author; the widget prompts, saves it, and re-dispatches Commit).
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';

/// copyWith sentinel: distinguishes "leave [ReviewState.selectedPath] alone"
/// (omitted) from "explicitly clear it" (passed null — empty review).
const Object _unset = Object();

enum ReviewStatus {
  initial,
  loading,
  ready,
  committing,
  error,

  /// A commit failed because neither Getman's stored identity nor the OS
  /// git config has a commit author — the widget layer prompts for a
  /// name/email, saves it to Settings, and re-dispatches `Commit`.
  needsIdentity,
}

class ReviewState extends Equatable {
  const ReviewState({
    this.status = ReviewStatus.initial,
    this.gitAvailable = true,
    this.repoExists = true,
    this.branch,
    this.entries = const [],
    this.selectedPath,
    this.errorMessage,
  });

  final ReviewStatus status;
  final bool gitAvailable;
  final bool repoExists;
  final String? branch;
  final List<ReviewEntry> entries;
  final String? selectedPath;
  final String? errorMessage;

  int get stagedCount => entries.where((e) => e.staged).length;

  ReviewState copyWith({
    ReviewStatus? status,
    bool? gitAvailable,
    bool? repoExists,
    String? branch,
    List<ReviewEntry>? entries,
    Object? selectedPath = _unset,
    String? errorMessage,
  }) {
    final next = status ?? this.status;
    return ReviewState(
      status: next,
      gitAvailable: gitAvailable ?? this.gitAvailable,
      repoExists: repoExists ?? this.repoExists,
      branch: branch ?? this.branch,
      entries: entries ?? this.entries,
      selectedPath: identical(selectedPath, _unset)
          ? this.selectedPath
          : selectedPath as String?,
      // Gated on the *resolved* status, not the parameter (sibling-state
      // rule: git_sync_state, pull_requests_state): an error state copied
      // without a status (e.g. SelectEntry's copyWith(selectedPath: …))
      // must keep its message; every non-error emission clears it.
      errorMessage: next == ReviewStatus.error
          ? (errorMessage ?? this.errorMessage)
          : null,
    );
  }

  @override
  List<Object?> get props => [
    status,
    gitAvailable,
    repoExists,
    branch,
    entries,
    selectedPath,
    errorMessage,
  ];
}
