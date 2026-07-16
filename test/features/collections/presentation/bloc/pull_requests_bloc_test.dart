import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_event.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements PullRequestService {}

void main() {
  const root = '/ws';
  late _MockService service;

  setUp(() {
    service = _MockService();
    // _onLoad resolves the default base on the available path; give every test
    // a benign default (specific tests override it).
    when(() => service.defaultBase(root)).thenAnswer((_) async => 'main');
  });

  blocTest<PullRequestsBloc, PullRequestsState>(
    'LoadPullRequests: available → loads PRs',
    build: () {
      when(
        () => service.availability(root),
      ).thenAnswer((_) async => GhAvailability.available);
      when(() => service.list(root)).thenAnswer(
        (_) async => const [
          PullRequestEntity(
            number: 1,
            title: 't',
            state: PrState.open,
            url: 'u',
            isDraft: false,
            checks: PrChecks.passing,
          ),
        ],
      );
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>().having(
        (s) => s.status,
        'status',
        PrStatus.loading,
      ),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.ready)
          .having(
            (s) => s.availability,
            'availability',
            GhAvailability.available,
          )
          .having((s) => s.prs.length, 'prs', 1),
    ],
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'LoadPullRequests: notInstalled → ready with availability, no list call',
    build: () {
      when(
        () => service.availability(root),
      ).thenAnswer((_) async => GhAvailability.notInstalled);
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>().having(
        (s) => s.status,
        'status',
        PrStatus.loading,
      ),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.ready)
          .having(
            (s) => s.availability,
            'availability',
            GhAvailability.notInstalled,
          ),
    ],
    verify: (_) => verifyNever(() => service.list(any())),
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'CreatePullRequest: creates, then reloads the list',
    build: () {
      when(
        () => service.availability(root),
      ).thenAnswer((_) async => GhAvailability.available);
      when(
        () => service.create(
          root,
          base: any(named: 'base'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer(
        (_) async => const PullRequestRef(number: 9, url: 'u/pull/9'),
      );
      when(() => service.list(root)).thenAnswer((_) async => const []);
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(
      const CreatePullRequest(
        root,
        base: 'main',
        title: 't',
        body: 'b',
        draft: false,
      ),
    ),
    expect: () => [
      isA<PullRequestsState>().having(
        (s) => s.status,
        'status',
        PrStatus.creating,
      ),
      isA<PullRequestsState>()
          .having((s) => s.lastCreated?.number, 'lastCreated', 9)
          .having((s) => s.status, 'status', PrStatus.ready),
    ],
    verify: (_) {
      verify(
        () => service.create(
          root,
          base: 'main',
          title: 't',
          body: 'b',
          draft: false,
        ),
      ).called(1);
      verify(() => service.list(root)).called(1);
    },
  );

  test('a second load is dropped while the first is in flight', () async {
    // Non-vacuous: gate the first load open so it's still busy when the second
    // arrives. Removing the `_dropWhileBusy` guard makes availability() run
    // twice, which `.called(1)` catches (the duplicate emits alone would be
    // suppressed by Equatable, so the call-count is the real proof).
    final gate = Completer<void>();
    when(() => service.availability(root)).thenAnswer((_) async {
      await gate.future;
      return GhAvailability.available;
    });
    when(() => service.list(root)).thenAnswer((_) async => const []);
    final bloc = PullRequestsBloc(service: service);
    final statuses = <PrStatus>[];
    final sub = bloc.stream.listen((s) => statuses.add(s.status));

    bloc.add(const LoadPullRequests(root));
    await Future<void>.delayed(Duration.zero); // first handler emits loading
    bloc.add(const LoadPullRequests(root)); // dropped: state is busy
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    await bloc.close();

    expect(statuses, [PrStatus.loading, PrStatus.ready]);
    verify(() => service.availability(root)).called(1);
  });

  blocTest<PullRequestsBloc, PullRequestsState>(
    'a service failure surfaces as an error state',
    build: () {
      when(
        () => service.availability(root),
      ).thenAnswer((_) async => GhAvailability.available);
      when(() => service.list(root)).thenThrow(Exception('boom'));
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>().having(
        (s) => s.status,
        'status',
        PrStatus.loading,
      ),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', isNotNull),
    ],
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'LoadPullRequests resolves the default base for the create form',
    build: () {
      when(
        () => service.availability(root),
      ).thenAnswer((_) async => GhAvailability.available);
      when(() => service.list(root)).thenAnswer((_) async => const []);
      when(() => service.defaultBase(root)).thenAnswer((_) async => 'develop');
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(const LoadPullRequests(root)),
    expect: () => [
      isA<PullRequestsState>().having(
        (s) => s.status,
        'status',
        PrStatus.loading,
      ),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.ready)
          .having((s) => s.defaultBase, 'defaultBase', 'develop'),
    ],
  );

  blocTest<PullRequestsBloc, PullRequestsState>(
    'a created PR is surfaced even when the list refresh fails',
    build: () {
      when(
        () => service.create(
          root,
          base: any(named: 'base'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer(
        (_) async => const PullRequestRef(number: 3, url: 'u/pull/3'),
      );
      when(() => service.list(root)).thenThrow(Exception('list boom'));
      return PullRequestsBloc(service: service);
    },
    act: (b) => b.add(
      const CreatePullRequest(
        root,
        base: 'main',
        title: 't',
        body: '',
        draft: false,
      ),
    ),
    // Refresh failed, but the PR exists → ready + lastCreated, NOT an error.
    expect: () => [
      isA<PullRequestsState>().having(
        (s) => s.status,
        'status',
        PrStatus.creating,
      ),
      isA<PullRequestsState>()
          .having((s) => s.status, 'status', PrStatus.ready)
          .having((s) => s.lastCreated?.number, 'lastCreated', 3),
    ],
  );
}
