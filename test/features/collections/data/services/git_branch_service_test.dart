import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/git_branch_service.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/branch_status.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:mocktail/mocktail.dart';

class _MockGit extends Mock implements GitService {}

class _MockDataSource extends Mock implements WorkspaceCollectionsDataSource {}

void main() {
  const root = '/ws';
  late _MockGit git;
  late _MockDataSource ds;
  late WorkspaceSyncService sync;
  late GitBranchService service;

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  setUp(() {
    git = _MockGit();
    ds = _MockDataSource();
    when(() => ds.write(any(), any())).thenAnswer((_) async {});
    sync = WorkspaceSyncService(ds, debounce: const Duration(seconds: 30));
    service = GitBranchService(git, sync);

    when(() => git.isAvailable()).thenAnswer((_) async => true);
    when(() => git.isRepo(root)).thenAnswer((_) async => true);
    when(() => git.currentBranch(root)).thenAnswer((_) async => 'main');
    when(() => git.branches(root)).thenAnswer((_) async => ['main', 'feat/x']);
    when(() => git.hasRemote(root)).thenAnswer((_) async => true);
    when(
      () => git.aheadBehind(root),
    ).thenAnswer((_) async => const AheadBehind(ahead: 2, behind: 1));
    when(() => git.stashList(root)).thenAnswer(
      (_) async => const [StashEntry(index: 0, message: 'WIP on main')],
    );
    when(() => git.status(root)).thenAnswer((_) async => const []);
    when(() => git.switchBranch(root, any())).thenAnswer((_) async {});
    when(() => git.createBranch(root, any())).thenAnswer((_) async {});
    when(() => git.stashPush(root, any())).thenAnswer((_) async {});
    when(() => git.stashPop(root, any())).thenAnswer((_) async {});
    when(() => git.stashDrop(root, any())).thenAnswer((_) async {});
    when(() => git.pull(root)).thenAnswer((_) async {});
    when(
      () => git.push(root, setUpstream: any(named: 'setUpstream')),
    ).thenAnswer((_) async {});
    when(() => git.hasUpstream(root)).thenAnswer((_) async => true);
  });

  // NB: not `tearDown(sync.dispose)` — a tear-off would read the late `sync`
  // at registration time, before `setUp` has assigned it.
  tearDown(() => sync.dispose());

  /// Proves that [invoke] does not start its git call until the pending mirror
  /// write has actually **landed** — not merely been invoked.
  ///
  /// A plain `verifyInOrder([ds.write, git.<op>])` is vacuous here: the mirror
  /// calls `dataSource.write` synchronously up to its first suspension, so
  /// mocktail records the call even if the service never awaits the flush.
  /// Gating the write on a completer and flipping `writeLanded` only when it
  /// *finishes* is what makes the assertion real (an `unawaited(flushPending)`
  /// regression turns these red).
  Future<void> expectGitWaitsForMirror({
    required void Function(void Function() onGitOp) stubGitOp,
    required Future<void> Function() invoke,
  }) async {
    final gate = Completer<void>();
    var writeLanded = false;
    var gitOpRan = false;
    var gitOpRanWhileWriting = false;

    when(() => ds.write(any(), any())).thenAnswer((_) async {
      await gate.future;
      writeLanded = true;
    });
    stubGitOp(() {
      gitOpRan = true;
      if (!writeLanded) gitOpRanWhileWriting = true;
    });

    sync.scheduleMirror(root, const []);
    final op = invoke();

    // Give the service every chance to run ahead of the write.
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await op;

    expect(writeLanded, isTrue, reason: 'the pending mirror never landed');
    expect(gitOpRan, isTrue, reason: 'the git op never ran');
    expect(
      gitOpRanWhileWriting,
      isFalse,
      reason: 'the git op ran before the mirror write landed on disk',
    );
  }

  /// Makes the pending mirror write fail, so the flush cannot certify that
  /// what is on disk matches Hive.
  void failTheMirrorWrite() {
    when(() => ds.write(any(), any())).thenThrow(Exception('read-only fs'));
    sync.scheduleMirror(root, const []);
  }

  test('status maps git state into BranchStatus', () async {
    final s = await service.status(root);

    expect(s.current, 'main');
    expect(s.branches, ['main', 'feat/x']);
    expect(s.ahead, 2);
    expect(s.behind, 1);
    expect(s.hasRemote, isTrue);
    expect(s.isRepo, isTrue);
    expect(s.stashCount, 1);
    expect(s.stashes.single.message, 'WIP on main');
  });

  test('status on a non-repo reports isRepo false and no branch', () async {
    when(() => git.isRepo(root)).thenAnswer((_) async => false);

    final s = await service.status(root);

    expect(s.isRepo, isFalse);
    expect(s.current, isNull);
  });

  test('status returns none when git is unavailable', () async {
    when(() => git.isAvailable()).thenAnswer((_) async => false);

    expect(await service.status(root), BranchStatus.none);
    verifyNever(() => git.isRepo(root));
  });

  test('isDirty waits for the pending mirror to land before asking git', () {
    // The race: a mirror scheduled moments ago has not landed, so an unflushed
    // `git status` would wrongly report a clean tree.
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(() => git.status(root)).thenAnswer((_) async {
          onGitOp();
          return const [];
        });
      },
      invoke: () => service.isDirty(root),
    );
  });

  test('isDirty is true when git reports any entry', () async {
    when(() => git.status(root)).thenAnswer(
      (_) async => const [
        GitStatusEntry(
          indexStatus: ' ',
          worktreeStatus: 'M',
          path: 'a.req.json',
        ),
      ],
    );

    expect(await service.isDirty(root), isTrue);
  });

  test('isDirty is false when git reports a clean tree', () async {
    expect(await service.isDirty(root), isFalse);
  });

  test('switchTo delegates to git', () async {
    await service.switchTo(root, 'feat/x');
    verify(() => git.switchBranch(root, 'feat/x')).called(1);
  });

  test('switchTo waits for the pending mirror to land first', () {
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(
          () => git.switchBranch(root, any()),
        ).thenAnswer((_) async => onGitOp());
      },
      invoke: () => service.switchTo(root, 'feat/x'),
    );
  });

  test('create waits for the pending mirror to land first', () {
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(
          () => git.createBranch(root, any()),
        ).thenAnswer((_) async => onGitOp());
      },
      invoke: () => service.create(root, 'feat/y'),
    );
  });

  test('pull waits for the pending mirror to land first', () {
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(() => git.pull(root)).thenAnswer((_) async => onGitOp());
      },
      invoke: () => service.pull(root),
    );
  });

  test('push waits for the pending mirror to land first', () {
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(
          () => git.push(root, setUpstream: any(named: 'setUpstream')),
        ).thenAnswer((_) async => onGitOp());
      },
      invoke: () => service.push(root),
    );
  });

  test('push sets upstream only when the branch has none', () async {
    when(() => git.hasUpstream(root)).thenAnswer((_) async => false);
    await service.push(root);
    verify(() => git.push(root, setUpstream: true)).called(1);

    when(() => git.hasUpstream(root)).thenAnswer((_) async => true);
    await service.push(root);
    verify(() => git.push(root, setUpstream: false)).called(1);
  });

  test('stash waits for the pending mirror to land first', () {
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(
          () => git.stashPush(root, any()),
        ).thenAnswer((_) async => onGitOp());
      },
      invoke: () => service.stash(root, 'wip'),
    );
  });

  test('popStash waits for the pending mirror to land first', () {
    return expectGitWaitsForMirror(
      stubGitOp: (onGitOp) {
        when(
          () => git.stashPop(root, any()),
        ).thenAnswer((_) async => onGitOp());
      },
      invoke: () => service.popStash(root, 2),
    );
  });

  test('dropStash delegates to git', () async {
    await service.dropStash(root, 1);
    verify(() => git.stashDrop(root, 1)).called(1);
  });

  test('dropStash does not flush: it never touches the tree', () async {
    sync.scheduleMirror(root, const []);

    await service.dropStash(root, 1);

    verifyNever(() => ds.write(any(), any()));
    verify(() => git.stashDrop(root, 1)).called(1);
  });

  group(
    'a failed mirror write aborts the op (never git over a stale tree)',
    () {
      test('switchTo throws and never switches the branch', () async {
        failTheMirrorWrite();

        await expectLater(
          service.switchTo(root, 'feat/x'),
          throwsA(isA<GitException>()),
        );
        verifyNever(() => git.switchBranch(root, any()));
      });

      test('pull throws and never pulls', () async {
        failTheMirrorWrite();

        await expectLater(service.pull(root), throwsA(isA<GitException>()));
        verifyNever(() => git.pull(root));
      });

      test('isDirty throws and never asks git', () async {
        failTheMirrorWrite();

        await expectLater(service.isDirty(root), throwsA(isA<GitException>()));
        verifyNever(() => git.status(root));
      });

      test('stash throws and never stashes', () async {
        failTheMirrorWrite();

        await expectLater(
          service.stash(root, 'wip'),
          throwsA(isA<GitException>()),
        );
        verifyNever(() => git.stashPush(root, any()));
      });

      test('a later successful mirror clears the failure', () async {
        failTheMirrorWrite();
        await expectLater(
          service.switchTo(root, 'feat/x'),
          throwsA(isA<GitException>()),
        );

        when(() => ds.write(any(), any())).thenAnswer((_) async {});
        sync.scheduleMirror(root, const []);

        await service.switchTo(root, 'feat/x');
        verify(() => git.switchBranch(root, 'feat/x')).called(1);
      });
    },
  );
}
