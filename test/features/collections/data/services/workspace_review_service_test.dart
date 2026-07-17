import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:mocktail/mocktail.dart';

class _MockGit extends Mock implements GitService {}

class _MockSync extends Mock implements WorkspaceSyncService {}

String reqJson(
  String name, {
  String method = 'GET',
  String url = 'https://a',
}) => jsonEncode({
  'id': 'id-$name',
  'name': name,
  'isFavorite': false,
  'request': {
    'id': 'id-$name',
    'method': method,
    'url': url,
    'headers': <String, dynamic>{},
    'body': '',
    'bodyType': 'raw',
    'auth': <String, dynamic>{},
  },
});

String folderJson(String name, {required List<String> childOrder}) =>
    jsonEncode({
      'id': 'id-$name',
      'name': name,
      'isFavorite': false,
      'childOrder': childOrder,
    });

void main() {
  late _MockGit git;
  late _MockSync sync;
  late WorkspaceReviewService service;
  const root = '/ws';

  setUp(() {
    git = _MockGit();
    sync = _MockSync();
    when(sync.flushPending).thenAnswer((_) async => true);
    service = WorkspaceReviewService(git, sync);
    when(() => git.isAvailable()).thenAnswer((_) async => true);
    when(() => git.isRepo(root)).thenAnswer((_) async => true);
    when(() => git.currentBranch(root)).thenAnswer((_) async => 'main');
  });

  test('review, stage and commit flush the pending mirror first', () async {
    when(() => git.status(root)).thenAnswer((_) async => const []);
    when(() => git.stage(root, ['a.req.json'])).thenAnswer((_) async {});
    when(
      () => git.commit(
        root,
        'msg',
        authorName: any(named: 'authorName'),
        authorEmail: any(named: 'authorEmail'),
      ),
    ).thenAnswer((_) async {});

    await service.review(root);
    await service.stage(root, ['a.req.json']);
    await service.commit(root, 'msg');
    verify(sync.flushPending).called(3);

    // A failed flush must abort instead of running git over a stale tree.
    when(sync.flushPending).thenAnswer((_) async => false);
    await expectLater(
      () => service.stage(root, ['a.req.json']),
      throwsA(isA<GitException>()),
    );
  });

  test('reports git unavailable', () async {
    when(() => git.isAvailable()).thenAnswer((_) async => false);
    final r = await service.review(root);
    expect(r.gitAvailable, isFalse);
    expect(r.entries, isEmpty);
  });

  test(
    'a modified request produces a request entry with a semantic diff',
    () async {
      when(() => git.status(root)).thenAnswer(
        (_) async => const [
          GitStatusEntry(
            indexStatus: ' ',
            worktreeStatus: 'M',
            path: 'get-user.req.json',
          ),
        ],
      );
      when(
        () => git.headContent(root, 'get-user.req.json'),
      ).thenAnswer((_) async => reqJson('Get User'));
      when(
        () => git.workingContent(root, 'get-user.req.json'),
      ).thenAnswer((_) async => reqJson('Get User', method: 'POST'));

      final r = await service.review(root);
      final entry = r.entries.single;
      expect(entry.nodeKind, NodeKind.request);
      expect(entry.changeType, ChangeType.modified);
      expect(entry.displayName, 'Get User');
      expect(entry.staged, isFalse);
      expect(entry.diff.changes.any((c) => c.field == 'method'), isTrue);
    },
  );

  test(
    'an untracked (added) request is changeType added and staged=false',
    () async {
      when(() => git.status(root)).thenAnswer(
        (_) async => const [
          GitStatusEntry(
            indexStatus: '?',
            worktreeStatus: '?',
            path: 'new.req.json',
          ),
        ],
      );
      when(
        () => git.headContent(root, 'new.req.json'),
      ).thenAnswer((_) async => null);
      when(
        () => git.workingContent(root, 'new.req.json'),
      ).thenAnswer((_) async => reqJson('New'));

      final entry = (await service.review(root)).entries.single;
      expect(entry.changeType, ChangeType.added);
      expect(entry.staged, isFalse);
    },
  );

  test(
    'a folder child reorder produces a non-empty child order diff',
    () async {
      when(() => git.status(root)).thenAnswer(
        (_) async => const [
          GitStatusEntry(
            indexStatus: ' ',
            worktreeStatus: 'M',
            path: 'folder/.folder.json',
          ),
        ],
      );
      when(
        () => git.headContent(root, 'folder/.folder.json'),
      ).thenAnswer((_) async => folderJson('Folder', childOrder: ['a', 'b']));
      when(
        () => git.workingContent(root, 'folder/.folder.json'),
      ).thenAnswer((_) async => folderJson('Folder', childOrder: ['b', 'a']));

      final entry = (await service.review(root)).entries.single;
      expect(entry.nodeKind, NodeKind.folder);
      expect(entry.changeType, ChangeType.modified);
      expect(entry.diff.changes, isNotEmpty);
      expect(
        entry.diff.changes.any((c) => c.field == 'child order'),
        isTrue,
      );
    },
  );

  test('the manifest maps to a workspaceOrder entry', () async {
    when(() => git.status(root)).thenAnswer(
      (_) async => const [
        GitStatusEntry(
          indexStatus: 'M',
          worktreeStatus: ' ',
          path: '.getman/workspace.json',
        ),
      ],
    );
    when(() => git.headContent(root, any())).thenAnswer((_) async => '{}');
    when(() => git.workingContent(root, any())).thenAnswer((_) async => '{}');

    final entry = (await service.review(root)).entries.single;
    expect(entry.nodeKind, NodeKind.workspaceOrder);
    expect(entry.staged, isTrue);
  });
}
