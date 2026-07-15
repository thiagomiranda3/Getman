import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/domain/conflict_service.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_event.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements ConflictService {}

void main() {
  const root = '/ws';
  late _MockService service;

  const conflictA = FileConflict(
    path: 'a.req.json',
    kind: ConflictKind.request,
  );
  const conflictB = FileConflict(
    path: 'b.req.json',
    kind: ConflictKind.request,
  );
  const resolutions = [
    FileResolution(path: 'a.req.json', wholeFile: FileSide.yours),
  ];

  setUpAll(() {
    registerFallbackValue(<FileResolution>[]);
  });

  setUp(() {
    service = _MockService();
  });

  blocTest<ConflictBloc, ConflictState>(
    'LoadConflicts populates the batch as ready',
    build: () {
      when(
        () => service.currentConflicts(root),
      ).thenAnswer((_) async => const [conflictA, conflictB]);
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const LoadConflicts(root)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.loading,
      ),
      isA<ConflictState>()
          .having((s) => s.status, 'status', ConflictStatus.ready)
          .having((s) => s.conflicts, 'conflicts', [conflictA, conflictB])
          .having((s) => s.batch, 'batch', 0),
    ],
  );

  blocTest<ConflictBloc, ConflictState>(
    'LoadConflicts with nothing conflicted emits done',
    build: () {
      when(() => service.currentConflicts(root)).thenAnswer((_) async => []);
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const LoadConflicts(root)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.loading,
      ),
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.done,
      ),
    ],
  );

  blocTest<ConflictBloc, ConflictState>(
    'ResolveAndContinue: rebase finishes cleanly → done',
    build: () {
      when(() => service.resolve(root, any())).thenAnswer((_) async {});
      when(
        () => service.continueRebase(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) async => RebaseStep.done);
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const ResolveAndContinue(root, resolutions)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.resolving,
      ),
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.done,
      ),
    ],
    verify: (_) {
      verify(() => service.resolve(root, resolutions)).called(1);
      verifyNever(() => service.currentConflicts(root));
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'ResolveAndContinue: more conflicts → loads the next batch',
    build: () {
      when(() => service.resolve(root, any())).thenAnswer((_) async {});
      when(
        () => service.continueRebase(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) async => RebaseStep.moreConflicts);
      when(
        () => service.currentConflicts(root),
      ).thenAnswer((_) async => const [conflictB]);
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const ResolveAndContinue(root, resolutions)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.resolving,
      ),
      isA<ConflictState>()
          .having((s) => s.status, 'status', ConflictStatus.ready)
          .having((s) => s.conflicts, 'conflicts', [conflictB])
          .having((s) => s.batch, 'batch', 1),
    ],
  );

  blocTest<ConflictBloc, ConflictState>(
    'ResolveAndContinue: more conflicts but the reload is empty → done',
    build: () {
      when(() => service.resolve(root, any())).thenAnswer((_) async {});
      when(
        () => service.continueRebase(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) async => RebaseStep.moreConflicts);
      when(() => service.currentConflicts(root)).thenAnswer((_) async => []);
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const ResolveAndContinue(root, resolutions)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.resolving,
      ),
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.done,
      ),
    ],
  );

  test(
    'ResolveAndContinue only reads the next batch after continueRebase '
    'completes',
    () async {
      // Non-vacuous: gate continueRebase open so currentConflicts must not
      // have run yet while it's pending. Removing the await-order in the
      // handler (e.g. firing both calls concurrently) would let
      // currentConflicts run before the gate completes, which the
      // verifyNever below catches.
      final gate = Completer<RebaseStep>();
      when(() => service.resolve(root, any())).thenAnswer((_) async {});
      when(
        () => service.continueRebase(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) => gate.future);
      when(
        () => service.currentConflicts(root),
      ).thenAnswer((_) async => const [conflictB]);
      final bloc = ConflictBloc(service: service)
        ..add(const ResolveAndContinue(root, resolutions));
      await Future<void>.delayed(Duration.zero);
      // continueRebase is in flight — currentConflicts must not have run.
      verifyNever(() => service.currentConflicts(root));

      gate.complete(RebaseStep.moreConflicts);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      verify(() => service.currentConflicts(root)).called(1);
      expect(bloc.state.status, ConflictStatus.ready);
      expect(bloc.state.batch, 1);
      await bloc.close();
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'AbortRebase aborts and emits done',
    build: () {
      when(() => service.abort(root)).thenAnswer((_) async {});
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const AbortRebase(root)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.resolving,
      ),
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.done,
      ),
    ],
    verify: (_) => verify(() => service.abort(root)).called(1),
  );

  blocTest<ConflictBloc, ConflictState>(
    'AbortRebase surfaces a service failure as error',
    build: () {
      when(() => service.abort(root)).thenThrow(GitException('abort failed'));
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const AbortRebase(root)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.resolving,
      ),
      isA<ConflictState>()
          .having((s) => s.status, 'status', ConflictStatus.error)
          .having(
            (s) => s.errorMessage,
            'errorMessage',
            contains('abort failed'),
          ),
    ],
  );

  blocTest<ConflictBloc, ConflictState>(
    'a resolve failure surfaces as error and leaves the rebase alone',
    build: () {
      when(() => service.resolve(root, any())).thenThrow(Exception('boom'));
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const ResolveAndContinue(root, resolutions)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.resolving,
      ),
      isA<ConflictState>()
          .having((s) => s.status, 'status', ConflictStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', isNotNull),
    ],
    verify: (_) {
      verifyNever(() => service.abort(root));
      verifyNever(
        () => service.continueRebase(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      );
    },
  );

  blocTest<ConflictBloc, ConflictState>(
    'a load failure surfaces as error',
    build: () {
      when(() => service.currentConflicts(root)).thenThrow(Exception('boom'));
      return ConflictBloc(service: service);
    },
    act: (b) => b.add(const LoadConflicts(root)),
    expect: () => [
      isA<ConflictState>().having(
        (s) => s.status,
        'status',
        ConflictStatus.loading,
      ),
      isA<ConflictState>()
          .having((s) => s.status, 'status', ConflictStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', isNotNull),
    ],
  );

  test('a second op is dropped while the first is in flight', () async {
    final gate = Completer<List<FileConflict>>();
    when(() => service.currentConflicts(root)).thenAnswer((_) => gate.future);
    final bloc = ConflictBloc(service: service)..add(const LoadConflicts(root));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const AbortRebase(root)); // dropped: bloc is busy
    gate.complete(const [conflictA]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await bloc.close();

    verifyNever(() => service.abort(root));
  });
}
