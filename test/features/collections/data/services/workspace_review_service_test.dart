import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
import 'package:getman/features/collections/domain/entities/review_entry.dart';
import 'package:mocktail/mocktail.dart';

class _MockGit extends Mock implements GitService {}

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
  late WorkspaceReviewService service;
  const root = '/ws';

  setUp(() {
    git = _MockGit();
    service = WorkspaceReviewService(git);
    when(() => git.isAvailable()).thenAnswer((_) async => true);
    when(() => git.isRepo(root)).thenAnswer((_) async => true);
    when(() => git.currentBranch(root)).thenAnswer((_) async => 'main');
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
