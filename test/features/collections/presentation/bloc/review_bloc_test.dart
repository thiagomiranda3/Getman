import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
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

  setUpAll(() => registerFallbackValue(<String>[]));

  setUp(() {
    service = _MockService();
    when(() => service.review(root)).thenAnswer((_) async => result);
    when(() => service.stage(root, any())).thenAnswer((_) async {});
    when(() => service.unstage(root, any())).thenAnswer((_) async {});
    when(() => service.commit(root, any())).thenAnswer((_) async {});
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
      verify(() => service.commit(root, 'msg')).called(1);
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
