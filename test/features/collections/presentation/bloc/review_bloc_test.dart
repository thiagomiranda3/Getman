import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart' show GitException;
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements ReviewService {}

void main() {
  late _MockService service;
  const root = '/ws';
  const entry = ReviewEntry(
    path: 'a.req.json',
    nodeKind: NodeKind.request,
    changeType: ChangeType.modified,
    displayName: 'A',
    staged: false,
    diff: SemanticDiff([
      FieldChange(
        field: 'method',
        kind: ChangeKind.changed,
        before: 'GET',
        after: 'POST',
      ),
    ]),
  );
  const staged = ReviewEntry(
    path: 'b.req.json',
    nodeKind: NodeKind.request,
    changeType: ChangeType.added,
    displayName: 'B',
    staged: true,
    diff: SemanticDiff([]),
  );
  const result = ReviewResult(
    gitAvailable: true,
    repoExists: true,
    branch: 'main',
    entries: [entry],
  );
  const mixed = ReviewResult(
    gitAvailable: true,
    repoExists: true,
    branch: 'main',
    entries: [entry, staged],
  );
  const empty = ReviewResult(
    gitAvailable: true,
    repoExists: true,
    branch: 'main',
    entries: [],
  );
  // A distinguishable "newer" snapshot for the out-of-order-load test.
  const newer = ReviewResult(
    gitAvailable: true,
    repoExists: true,
    branch: 'feature',
    entries: [entry, staged],
  );

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    service = _MockService();
    when(() => service.review(root)).thenAnswer((_) async => result);
    when(() => service.stage(root, any())).thenAnswer((_) async {});
    when(() => service.unstage(root, any())).thenAnswer((_) async {});
    when(
      () => service.commit(
        root,
        any(),
        authorName: any(named: 'authorName'),
        authorEmail: any(named: 'authorEmail'),
      ),
    ).thenAnswer((_) async {});
  });

  blocTest<ReviewBloc, ReviewState>(
    'LoadReview → ready with entries',
    build: () => ReviewBloc(service: service),
    act: (b) => b.add(const LoadReview(root)),
    verify: (b) {
      expect(b.state.status, ReviewStatus.ready);
      expect(b.state.entries.single.displayName, 'A');
      expect(b.state.branch, 'main');
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'StageNode stages then reloads',
    build: () => ReviewBloc(service: service),
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const StageNode(root, 'a.req.json'));
    },
    verify: (b) {
      verify(() => service.stage(root, ['a.req.json'])).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'StageAll stages every unstaged entry in one call',
    build: () {
      when(() => service.review(root)).thenAnswer((_) async => mixed);
      return ReviewBloc(service: service);
    },
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const StageAll(root));
    },
    verify: (b) {
      // Only the unstaged one — b.req.json is already in the index.
      verify(() => service.stage(root, ['a.req.json'])).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'UnstageAll unstages every staged entry in one call',
    build: () {
      when(() => service.review(root)).thenAnswer((_) async => mixed);
      return ReviewBloc(service: service);
    },
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const UnstageAll(root));
    },
    verify: (b) {
      verify(() => service.unstage(root, ['b.req.json'])).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'StageAll with nothing to stage does not call the service',
    build: () => ReviewBloc(service: service),
    act: (b) => b.add(const StageAll(root)),
    verify: (b) {
      verifyNever(() => service.stage(root, any()));
      verifyNever(() => service.review(root));
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'Commit calls the service and reloads',
    build: () => ReviewBloc(service: service),
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const Commit(root, 'msg'));
    },
    verify: (b) {
      verify(
        () => service.commit(
          root,
          'msg',
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'Commit failing with a missing-identity GitException → needsIdentity',
    build: () {
      when(
        () => service.commit(
          root,
          any(),
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenThrow(
        GitException(
          '*** Please tell me who you are.\n\nRun git config...',
        ),
      );
      return ReviewBloc(service: service);
    },
    act: (b) => b.add(const Commit(root, 'msg')),
    expect: () => [
      isA<ReviewState>().having(
        (s) => s.status,
        'status',
        ReviewStatus.committing,
      ),
      isA<ReviewState>().having(
        (s) => s.status,
        'status',
        ReviewStatus.needsIdentity,
      ),
    ],
  );

  blocTest<ReviewBloc, ReviewState>(
    'Commit failing with a non-identity GitException → error, not '
    'needsIdentity',
    build: () {
      when(
        () => service.commit(
          root,
          any(),
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenThrow(GitException('some other git failure'));
      return ReviewBloc(service: service);
    },
    act: (b) => b.add(const Commit(root, 'msg')),
    expect: () => [
      isA<ReviewState>().having(
        (s) => s.status,
        'status',
        ReviewStatus.committing,
      ),
      isA<ReviewState>().having((s) => s.status, 'status', ReviewStatus.error),
    ],
    verify: (b) {
      expect(b.state.errorMessage, contains('some other git failure'));
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'review failure → error status',
    build: () {
      when(() => service.review(root)).thenThrow(Exception('boom'));
      return ReviewBloc(service: service);
    },
    act: (b) => b.add(const LoadReview(root)),
    verify: (b) => expect(b.state.status, ReviewStatus.error),
  );

  test(
    'a second StageNode while the first is in flight is serialized — '
    'queued behind it, never raced on .git/index.lock, never dropped',
    () async {
      final firstStage = Completer<void>();
      var stageCalls = 0;
      when(() => service.stage(root, any())).thenAnswer((_) async {
        stageCalls++;
        if (stageCalls == 1) await firstStage.future;
      });
      final bloc = ReviewBloc(service: service);
      addTearDown(() async {
        if (!firstStage.isCompleted) firstStage.complete();
        await bloc.close();
      });
      bloc.add(const LoadReview(root));
      await pumpEventQueue();
      bloc
        ..add(const StageNode(root, 'a.req.json'))
        ..add(const StageNode(root, 'b.req.json'));
      await pumpEventQueue();
      // The second `git add` must not start while the first holds
      // .git/index.lock — run concurrently it fails on the lock and the
      // user's click silently does nothing.
      expect(stageCalls, 1);
      firstStage.complete();
      await pumpEventQueue();
      // …and it must not be dropped either: it runs after the first lands.
      expect(stageCalls, 2);
      verify(() => service.stage(root, ['a.req.json'])).called(1);
      verify(() => service.stage(root, ['b.req.json'])).called(1);
    },
  );

  test(
    'out-of-order review() completions cannot leave the older snapshot '
    'as the final state — the latest load wins',
    () async {
      final slowFirst = Completer<ReviewResult>();
      var reviewCalls = 0;
      when(() => service.review(root)).thenAnswer((_) {
        reviewCalls++;
        return reviewCalls == 1 ? slowFirst.future : Future.value(newer);
      });
      final bloc = ReviewBloc(service: service);
      addTearDown(() async {
        if (!slowFirst.isCompleted) slowFirst.complete(result);
        await bloc.close();
      });
      bloc
        ..add(const LoadReview(root))
        ..add(const LoadReview(root));
      await pumpEventQueue();
      // The newer (second) load has already landed; the older one now
      // resolves LATE — its stale snapshot must be discarded.
      slowFirst.complete(result);
      await pumpEventQueue();
      expect(bloc.state.status, ReviewStatus.ready);
      expect(bloc.state.branch, 'feature');
      expect(bloc.state.entries, hasLength(2));
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'StageNode failure surfaces an error state instead of silently '
    'reloading',
    build: () {
      when(
        () => service.stage(root, any()),
      ).thenThrow(GitException('.git/index.lock: File exists'));
      return ReviewBloc(service: service);
    },
    act: (b) => b.add(const StageNode(root, 'a.req.json')),
    verify: (b) {
      expect(b.state.status, ReviewStatus.error);
      expect(b.state.errorMessage, contains('index.lock'));
      // No reload on a failed stage: the index didn't change, and the
      // reload's `ready` emission would wipe the error banner.
      verifyNever(() => service.review(root));
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'UnstageAll failure surfaces an error state instead of silently '
    'reloading',
    build: () {
      when(() => service.review(root)).thenAnswer((_) async => mixed);
      when(() => service.unstage(root, any())).thenThrow(GitException('boom'));
      return ReviewBloc(service: service);
    },
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const UnstageAll(root));
    },
    verify: (b) {
      expect(b.state.status, ReviewStatus.error);
      expect(b.state.errorMessage, contains('boom'));
      // Only the initial load — no reload after the failed unstage.
      verify(() => service.review(root)).called(1);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'SelectEntry while status is error keeps the error banner (CW3)',
    build: () {
      when(() => service.review(root)).thenThrow(Exception('boom'));
      return ReviewBloc(service: service);
    },
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      expect(b.state.status, ReviewStatus.error);
      b.add(const SelectEntry('a.req.json'));
    },
    verify: (b) {
      expect(b.state.status, ReviewStatus.error);
      expect(b.state.errorMessage, contains('boom'));
      expect(b.state.selectedPath, 'a.req.json');
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'successful reload after an error clears the errorMessage',
    build: () {
      when(() => service.review(root)).thenThrow(Exception('boom'));
      return ReviewBloc(service: service);
    },
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      expect(b.state.errorMessage, contains('boom'));
      when(() => service.review(root)).thenAnswer((_) async => result);
      b.add(const LoadReview(root));
    },
    verify: (b) {
      expect(b.state.status, ReviewStatus.ready);
      expect(b.state.errorMessage, isNull);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'reloading into an empty review clears selectedPath',
    build: () => ReviewBloc(service: service),
    act: (b) async {
      b.add(const LoadReview(root));
      await Future<void>.delayed(Duration.zero);
      expect(b.state.selectedPath, 'a.req.json');
      when(() => service.review(root)).thenAnswer((_) async => empty);
      b.add(const LoadReview(root));
    },
    verify: (b) {
      expect(b.state.status, ReviewStatus.ready);
      expect(b.state.selectedPath, isNull);
    },
  );

  blocTest<ReviewBloc, ReviewState>(
    'InitRepo failure → error status, no reload',
    build: () {
      when(
        () => service.init(root),
      ).thenThrow(Exception('Please tell me who you are'));
      return ReviewBloc(service: service);
    },
    act: (b) => b.add(const InitRepo(root)),
    verify: (b) {
      expect(b.state.status, ReviewStatus.error);
      expect(b.state.errorMessage, contains('Please tell me who you are'));
      verifyNever(() => service.review(root));
    },
  );
}
