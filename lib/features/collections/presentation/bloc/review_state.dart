import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';

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
    String? selectedPath,
    String? errorMessage,
  }) => ReviewState(
    status: status ?? this.status,
    gitAvailable: gitAvailable ?? this.gitAvailable,
    repoExists: repoExists ?? this.repoExists,
    branch: branch ?? this.branch,
    entries: entries ?? this.entries,
    selectedPath: selectedPath ?? this.selectedPath,
    errorMessage: errorMessage,
  );

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
