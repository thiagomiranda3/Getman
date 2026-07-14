import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements BranchService {}

void main() {
  const root = '/ws';
  late _MockService service;
  late Completer<void> pullGate;

  const status = BranchStatus(
    isRepo: true,
    current: 'main',
    branches: ['main', 'feat/x'],
    ahead: 2,
    hasRemote: true,
    stashes: [StashInfo(index: 0, message: 'wip')],
  );

  // The workspace mirror could not be flushed to disk: every working-tree op
  // on BranchService throws this instead of running git over a stale tree.
  GitException flushFailure() => GitException(
    'Could not write the workspace to disk — aborting so git does not run '
    'over a stale tree. Check the workspace folder is writable.',
  );

  setUp(() {
    service = _MockService();
    when(() => service.status(root)).thenAnswer((_) async => status);
    when(() => service.isDirty(root)).thenAnswer((_) async => false);
    when(() => service.switchTo(root, any())).thenAnswer((_) async {});
    when(() => service.create(root, any())).thenAnswer((_) async {});
    when(() => service.pull(root)).thenAnswer((_) async {});
    when(() => service.push(root)).thenAnswer((_) async {});
    when(() => service.stash(root, any())).thenAnswer((_) async {});
    when(() => service.popStash(root, any())).thenAnswer((_) async {});
    when(() => service.dropStash(root, any())).thenAnswer((_) async {});
  });

  blocTest<GitSyncBloc, GitSyncState>(
    'LoadBranchStatus → ready with the branch status',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const LoadBranchStatus(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.branch.current, 'main');
      expect(b.state.branch.ahead, 2);
      expect(b.state.branch.stashCount, 1);
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'LoadBranchStatus surfaces a status failure as error',
    build: () {
      when(() => service.status(root)).thenThrow(GitException('git missing'));
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const LoadBranchStatus(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('git missing'));
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'SwitchBranch on a clean tree switches and bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      verify(() => service.switchTo(root, 'feat/x')).called(1);
      expect(b.state.reloadToken, 1);
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.errorMessage, isNull);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'SwitchBranch on a dirty tree is refused without touching git',
    build: () {
      when(() => service.isDirty(root)).thenAnswer((_) async => true);
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      verifyNever(() => service.switchTo(root, any()));
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('uncommitted changes'));
      expect(b.state.reloadToken, 0); // nothing changed on disk
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'SwitchBranch surfaces a failed mirror flush from isDirty',
    build: () {
      when(() => service.isDirty(root)).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      verifyNever(() => service.switchTo(root, any()));
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'SwitchBranch surfaces a failed mirror flush from switchTo',
    build: () {
      when(() => service.switchTo(root, any())).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PullChanges surfaces the git error and does not bump reloadToken',
    build: () {
      when(() => service.pull(root)).thenThrow(Exception('CONFLICT in a.json'));
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const PullChanges(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('CONFLICT'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PullChanges surfaces a failed mirror flush',
    build: () {
      when(() => service.pull(root)).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const PullChanges(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PullChanges success bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const PullChanges(root)),
    verify: (b) => expect(b.state.reloadToken, 1),
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PushChanges does not bump reloadToken (disk is unchanged)',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const PushChanges(root)),
    verify: (b) {
      verify(() => service.push(root)).called(1);
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PushChanges surfaces a failed mirror flush',
    build: () {
      when(() => service.push(root)).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const PushChanges(root)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'StashChanges stashes and bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const StashChanges(root, 'wip')),
    verify: (b) {
      verify(() => service.stash(root, 'wip')).called(1);
      expect(b.state.reloadToken, 1);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'StashChanges surfaces a failed mirror flush',
    build: () {
      when(() => service.stash(root, any())).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const StashChanges(root, 'wip')),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PopStash pops and bumps reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const PopStash(root, 1)),
    verify: (b) {
      verify(() => service.popStash(root, 1)).called(1);
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.reloadToken, 1);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'PopStash surfaces a failed mirror flush',
    build: () {
      when(() => service.popStash(root, any())).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const PopStash(root, 0)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'DropStash drops without bumping reloadToken',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const DropStash(root, 0)),
    verify: (b) {
      verify(() => service.dropStash(root, 0)).called(1);
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'DropStash surfaces the git error',
    build: () {
      when(() => service.dropStash(root, any())).thenThrow(
        GitException('no stash entries'),
      );
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const DropStash(root, 3)),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('no stash entries'));
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'CreateBranch creates and reloads status',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const CreateBranch(root, 'feat/y')),
    verify: (b) {
      verify(() => service.create(root, 'feat/y')).called(1);
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.reloadToken, 0);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'CreateBranch surfaces a failed mirror flush',
    build: () {
      when(() => service.create(root, any())).thenThrow(flushFailure());
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const CreateBranch(root, 'feat/y')),
    verify: (b) {
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('writable'));
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'a later success clears the stale error message',
    build: () {
      when(() => service.pull(root)).thenThrow(GitException('boom'));
      return GitSyncBloc(service: service);
    },
    act: (b) async {
      b.add(const PullChanges(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const LoadBranchStatus(root));
    },
    verify: (b) {
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.errorMessage, isNull);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'an operation goes through a busy state',
    build: () => GitSyncBloc(service: service),
    act: (b) => b.add(const PullChanges(root)),
    verify: (b) => expect(b.state.isBusy, isFalse),
    expect: () => [
      const GitSyncState(status: GitSyncStatus.busy),
      // The disk changed: the token is bumped before the status() read, so a
      // failing read cannot swallow the reload.
      const GitSyncState(status: GitSyncStatus.busy, reloadToken: 1),
      const GitSyncState(
        status: GitSyncStatus.ready,
        branch: status,
        reloadToken: 1,
      ),
    ],
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'a successful switch whose status() read fails still bumps reloadToken',
    build: () {
      when(() => service.status(root)).thenThrow(GitException('index.lock'));
      return GitSyncBloc(service: service);
    },
    act: (b) => b.add(const SwitchBranch(root, 'feat/x')),
    verify: (b) {
      verify(() => service.switchTo(root, 'feat/x')).called(1);
      // The branch really did change on disk — the tree must still reload.
      expect(b.state.status, GitSyncStatus.error);
      expect(b.state.errorMessage, contains('index.lock'));
      expect(b.state.reloadToken, 1);
    },
  );

  blocTest<GitSyncBloc, GitSyncState>(
    'an event dispatched while an op is in flight is dropped',
    build: () {
      pullGate = Completer<void>();
      when(() => service.pull(root)).thenAnswer((_) => pullGate.future);
      return GitSyncBloc(service: service);
    },
    act: (b) async {
      b.add(const PullChanges(root));
      await Future<void>.delayed(Duration.zero);
      b.add(const SwitchBranch(root, 'feat/x')); // dropped: bloc is busy
      await Future<void>.delayed(Duration.zero);
      pullGate.complete();
      await Future<void>.delayed(Duration.zero);
    },
    verify: (b) {
      verifyNever(() => service.isDirty(root));
      verifyNever(() => service.switchTo(root, any()));
      expect(b.state.status, GitSyncStatus.ready);
      expect(b.state.reloadToken, 1); // only the pull bumped
    },
    expect: () => [
      const GitSyncState(status: GitSyncStatus.busy),
      const GitSyncState(status: GitSyncStatus.busy, reloadToken: 1),
      const GitSyncState(
        status: GitSyncStatus.ready,
        branch: status,
        reloadToken: 1,
      ),
    ],
  );

  group('GitSyncState.copyWith', () {
    const errorState = GitSyncState(
      status: GitSyncStatus.error,
      errorMessage: 'boom',
    );

    test('an error state copied without a status keeps status + message', () {
      final next = errorState.copyWith(reloadToken: 3);
      expect(next.status, GitSyncStatus.error);
      expect(next.errorMessage, 'boom');
      expect(next.reloadToken, 3);
    });

    test('a non-error status clears the message', () {
      expect(
        errorState.copyWith(status: GitSyncStatus.ready).errorMessage,
        isNull,
      );
      expect(
        errorState.copyWith(status: GitSyncStatus.busy).errorMessage,
        isNull,
      );
    });
  });
}
