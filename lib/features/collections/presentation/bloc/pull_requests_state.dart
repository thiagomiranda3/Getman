// PullRequestsBloc state: status, gh-CLI availability, the loaded open-PR
// list, the just-created PR ref (lastCreated), and the repo's default base
// branch (defaultBase) used to prefill the create form.
import 'package:equatable/equatable.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';

enum PrStatus { initial, loading, ready, creating, error }

class PullRequestsState extends Equatable {
  const PullRequestsState({
    // `initial`, not `loading`: the load/create guard drops events while
    // `isBusy`, and a `loading` default would make it drop the very first load.
    this.status = PrStatus.initial,
    this.availability = GhAvailability.available,
    this.prs = const [],
    this.errorMessage,
    this.lastCreated,
    this.defaultBase,
  });

  final PrStatus status;
  final GhAvailability availability;
  final List<PullRequestEntity> prs;
  final String? errorMessage;
  final PullRequestRef? lastCreated;

  /// The repo's default branch (`gh repo view`), for the create form's base
  /// prefill. Null until resolved / when it can't be determined.
  final String? defaultBase;

  bool get isBusy => status == PrStatus.loading || status == PrStatus.creating;

  PullRequestsState copyWith({
    PrStatus? status,
    GhAvailability? availability,
    List<PullRequestEntity>? prs,
    String? errorMessage,
    PullRequestRef? lastCreated,
    String? defaultBase,
  }) {
    final next = status ?? this.status;
    return PullRequestsState(
      status: next,
      availability: availability ?? this.availability,
      prs: prs ?? this.prs,
      // Only an error state keeps a message; anything else clears it.
      errorMessage: next == PrStatus.error
          ? (errorMessage ?? this.errorMessage)
          : null,
      lastCreated: lastCreated ?? this.lastCreated,
      defaultBase: defaultBase ?? this.defaultBase,
    );
  }

  @override
  List<Object?> get props => [
    status,
    availability,
    prs,
    errorMessage,
    lastCreated,
    defaultBase,
  ];
}
