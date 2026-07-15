import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/git_conflict_service.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/file_conflict.dart';
import 'package:mocktail/mocktail.dart';

class _MockGit extends Mock implements GitService {}

/// A real [WorkspaceSyncService] over a no-op data source: `resolve` and
/// `continueRebase` wrap their bodies in `withMirroringSuspended` (FIX I1),
/// whose real implementation just runs the action — no need to mock it, and
/// this exercises the actual suspend/resume pairing instead of stubbing it
/// away.
class _NoopWorkspaceDataSource implements WorkspaceCollectionsDataSource {
  @override
  Future<List<CollectionNodeEntity>> read(String root) async => const [];
  @override
  Future<void> write(String root, List<CollectionNodeEntity> forest) async {}
}

CollectionNodeEntity _leaf({
  String id = 'r1',
  String name = 'Req',
  bool isFavorite = false,
  String method = 'GET',
  String url = '',
  Map<String, String> headers = const {},
  String body = '',
  Map<String, String> auth = const {},
}) => CollectionNodeEntity(
  id: id,
  name: name,
  isFolder: false,
  isFavorite: isFavorite,
  config: HttpRequestConfigEntity(
    id: id,
    method: method,
    url: url,
    headers: headers,
    body: body,
    auth: auth,
  ),
);

CollectionNodeEntity _folder({
  String id = 'f1',
  String name = 'Folder',
  bool isFavorite = false,
  Map<String, String> variables = const {},
  Set<String> secretKeys = const {},
}) => CollectionNodeEntity(
  id: id,
  name: name,
  isFavorite: isFavorite,
  variables: variables,
  secretKeys: secretKeys,
);

String _reqStage(CollectionNodeEntity leaf) =>
    jsonEncode(WorkspaceCollectionSerializer.requestToJson(leaf));

String _folderStage(CollectionNodeEntity folder, List<String> order) =>
    jsonEncode(WorkspaceCollectionSerializer.folderToJson(folder, order));

void main() {
  const root = '/ws';
  late _MockGit git;
  late GitConflictService service;

  setUp(() {
    git = _MockGit();
    service = GitConflictService(
      git,
      WorkspaceSyncService(_NoopWorkspaceDataSource()),
    );
  });

  group('currentConflicts / classify', () {
    test('a .req.json changed on both sides classifies as request', () async {
      when(() => git.conflictedPaths(root)).thenAnswer(
        (_) async => [
          'a.req.json',
        ],
      );
      when(
        () => git.showStage(root, 'a.req.json', 1),
      ).thenAnswer((_) async => _reqStage(_leaf(url: 'https://a')));
      when(
        () => git.showStage(root, 'a.req.json', 2),
      ).thenAnswer((_) async => _reqStage(_leaf(url: 'https://b')));
      when(
        () => git.showStage(root, 'a.req.json', 3),
      ).thenAnswer((_) async => _reqStage(_leaf(url: 'https://c')));

      final conflicts = await service.currentConflicts(root);

      expect(conflicts, hasLength(1));
      final c = conflicts.single;
      expect(c.path, 'a.req.json');
      expect(c.kind, ConflictKind.request);
      expect(c.node, isNotNull);
      expect(c.node!.conflicts.map((f) => f.field), contains('url'));
    });

    test(
      'a .req.json missing the incoming stage is deleteModify with '
      'deletedSide=incoming (upstream deleted)',
      () async {
        when(() => git.conflictedPaths(root)).thenAnswer(
          (_) async => [
            'a.req.json',
          ],
        );
        when(
          () => git.showStage(root, 'a.req.json', 1),
        ).thenAnswer((_) async => _reqStage(_leaf()));
        when(
          () => git.showStage(root, 'a.req.json', 2),
        ).thenAnswer((_) async => null);
        when(
          () => git.showStage(root, 'a.req.json', 3),
        ).thenAnswer((_) async => _reqStage(_leaf()));

        final conflicts = await service.currentConflicts(root);

        expect(conflicts.single.kind, ConflictKind.deleteModify);
        expect(conflicts.single.node, isNull);
        expect(conflicts.single.deletedSide, FileSide.incoming);
      },
    );

    test(
      'a .req.json missing the yours stage is deleteModify with '
      'deletedSide=yours (you deleted it)',
      () async {
        when(() => git.conflictedPaths(root)).thenAnswer(
          (_) async => [
            'a.req.json',
          ],
        );
        when(
          () => git.showStage(root, 'a.req.json', 1),
        ).thenAnswer((_) async => _reqStage(_leaf()));
        when(
          () => git.showStage(root, 'a.req.json', 2),
        ).thenAnswer((_) async => _reqStage(_leaf()));
        when(
          () => git.showStage(root, 'a.req.json', 3),
        ).thenAnswer((_) async => null);

        final conflicts = await service.currentConflicts(root);

        expect(conflicts.single.kind, ConflictKind.deleteModify);
        expect(conflicts.single.deletedSide, FileSide.yours);
      },
    );

    test(
      'a .folder.json missing the yours stage is deleteModify with '
      'deletedSide=yours (you deleted the folder)',
      () async {
        when(() => git.conflictedPaths(root)).thenAnswer(
          (_) async => [
            'x/.folder.json',
          ],
        );
        when(
          () => git.showStage(root, 'x/.folder.json', 1),
        ).thenAnswer((_) async => _folderStage(_folder(), ['a']));
        when(
          () => git.showStage(root, 'x/.folder.json', 2),
        ).thenAnswer((_) async => _folderStage(_folder(), ['a']));
        when(
          () => git.showStage(root, 'x/.folder.json', 3),
        ).thenAnswer((_) async => null);

        final conflicts = await service.currentConflicts(root);

        expect(conflicts.single.kind, ConflictKind.deleteModify);
        expect(conflicts.single.deletedSide, FileSide.yours);
      },
    );

    test('a .req.json with no base stage (add/add) is addAdd', () async {
      when(() => git.conflictedPaths(root)).thenAnswer(
        (_) async => [
          'a.req.json',
        ],
      );
      when(
        () => git.showStage(root, 'a.req.json', 1),
      ).thenAnswer((_) async => null);
      when(
        () => git.showStage(root, 'a.req.json', 2),
      ).thenAnswer((_) async => _reqStage(_leaf(name: 'Incoming')));
      when(
        () => git.showStage(root, 'a.req.json', 3),
      ).thenAnswer((_) async => _reqStage(_leaf(name: 'Yours')));

      final conflicts = await service.currentConflicts(root);

      expect(conflicts.single.kind, ConflictKind.addAdd);
      expect(conflicts.single.node, isNotNull);
    });

    test('a .req.json with unparseable content is structural', () async {
      when(() => git.conflictedPaths(root)).thenAnswer(
        (_) async => [
          'a.req.json',
        ],
      );
      when(
        () => git.showStage(root, 'a.req.json', 1),
      ).thenAnswer((_) async => null);
      when(
        () => git.showStage(root, 'a.req.json', 2),
      ).thenAnswer((_) async => 'not json');
      when(
        () => git.showStage(root, 'a.req.json', 3),
      ).thenAnswer((_) async => _reqStage(_leaf()));

      final conflicts = await service.currentConflicts(root);

      expect(conflicts.single.kind, ConflictKind.structural);
      expect(conflicts.single.node, isNull);
    });

    test('a .folder.json changed on both sides classifies as folder', () async {
      when(() => git.conflictedPaths(root)).thenAnswer(
        (_) async => [
          'x/.folder.json',
        ],
      );
      when(() => git.showStage(root, 'x/.folder.json', 1)).thenAnswer(
        (_) async => _folderStage(_folder(variables: {'k': 'base'}), ['a']),
      );
      when(() => git.showStage(root, 'x/.folder.json', 2)).thenAnswer(
        (_) async =>
            _folderStage(_folder(variables: {'k': 'incoming'}), ['a', 'b']),
      );
      when(() => git.showStage(root, 'x/.folder.json', 3)).thenAnswer(
        (_) async =>
            _folderStage(_folder(variables: {'k': 'yours'}), ['a', 'c']),
      );

      final conflicts = await service.currentConflicts(root);

      final c = conflicts.single;
      expect(c.path, 'x/.folder.json');
      expect(c.kind, ConflictKind.folder);
      expect(c.node, isNotNull);
      expect(c.node!.conflicts.map((f) => f.field), contains("variable 'k'"));
    });

    test('workspace.json (neither req nor folder) is structural', () async {
      when(() => git.conflictedPaths(root)).thenAnswer(
        (_) async => [
          '.getman/workspace.json',
        ],
      );

      final conflicts = await service.currentConflicts(root);

      expect(conflicts.single.kind, ConflictKind.structural);
      expect(conflicts.single.node, isNull);
      verifyNever(() => git.showStage(root, '.getman/workspace.json', any()));
    });
  });

  group('resolve', () {
    test(
      'coarse wholeFile: incoming writes stage-2 content and stages it',
      () async {
        when(
          () => git.showStage(root, 'a.req.json', 2),
        ).thenAnswer((_) async => 'INCOMING CONTENT');
        when(
          () => git.writeWorkingFile(root, 'a.req.json', any()),
        ).thenAnswer((_) async {});
        when(() => git.add(root, 'a.req.json')).thenAnswer((_) async {});

        await service.resolve(root, const [
          FileResolution(path: 'a.req.json', wholeFile: FileSide.incoming),
        ]);

        verify(
          () => git.writeWorkingFile(root, 'a.req.json', 'INCOMING CONTENT'),
        ).called(1);
        verify(() => git.add(root, 'a.req.json')).called(1);
        verifyNever(() => git.showStage(root, 'a.req.json', 3));
      },
    );

    test(
      'coarse wholeFile: keeping the deleting side removes the file, not '
      'an empty write',
      () async {
        // Delete/modify: incoming deleted the file (stage 2 absent), yours
        // kept editing it (stage 3 present). The user picks "incoming"
        // (i.e. keep the deletion).
        when(
          () => git.showStage(root, 'a.req.json', 2),
        ).thenAnswer((_) async => null);
        when(() => git.removeFile(root, 'a.req.json')).thenAnswer(
          (
            _,
          ) async {},
        );

        await service.resolve(root, const [
          FileResolution(path: 'a.req.json', wholeFile: FileSide.incoming),
        ]);

        verify(() => git.removeFile(root, 'a.req.json')).called(1);
        verifyNever(() => git.writeWorkingFile(root, 'a.req.json', any()));
        verifyNever(() => git.add(root, 'a.req.json'));
      },
    );

    test(
      'coarse wholeFile: keeping the modified side writes its content and '
      'stages it',
      () async {
        // Same delete/modify conflict, but the user picks "yours" (the
        // side that still has content) — content is written + staged.
        when(
          () => git.showStage(root, 'a.req.json', 3),
        ).thenAnswer((_) async => 'YOURS CONTENT');
        when(
          () => git.writeWorkingFile(root, 'a.req.json', any()),
        ).thenAnswer((_) async {});
        when(() => git.add(root, 'a.req.json')).thenAnswer((_) async {});

        await service.resolve(root, const [
          FileResolution(path: 'a.req.json', wholeFile: FileSide.yours),
        ]);

        verify(
          () => git.writeWorkingFile(root, 'a.req.json', 'YOURS CONTENT'),
        ).called(1);
        verify(() => git.add(root, 'a.req.json')).called(1);
        verifyNever(() => git.removeFile(root, 'a.req.json'));
      },
    );

    test('coarse wholeFile: yours writes stage-3 content', () async {
      when(
        () => git.showStage(root, 'a.req.json', 3),
      ).thenAnswer((_) async => 'YOURS CONTENT');
      when(
        () => git.writeWorkingFile(root, 'a.req.json', any()),
      ).thenAnswer((_) async {});
      when(() => git.add(root, 'a.req.json')).thenAnswer((_) async {});

      await service.resolve(root, const [
        FileResolution(path: 'a.req.json', wholeFile: FileSide.yours),
      ]);

      verify(
        () => git.writeWorkingFile(root, 'a.req.json', 'YOURS CONTENT'),
      ).called(1);
    });

    test(
      'field-level resolution writes the merged node with picks applied',
      () async {
        when(
          () => git.showStage(root, 'a.req.json', 1),
        ).thenAnswer((_) async => _reqStage(_leaf(url: 'https://a')));
        when(
          () => git.showStage(root, 'a.req.json', 2),
        ).thenAnswer((_) async => _reqStage(_leaf(url: 'https://b')));
        when(
          () => git.showStage(root, 'a.req.json', 3),
        ).thenAnswer((_) async => _reqStage(_leaf(url: 'https://c')));
        String? written;
        when(() => git.writeWorkingFile(root, 'a.req.json', any())).thenAnswer((
          i,
        ) async {
          written = i.positionalArguments[2] as String;
        });
        when(() => git.add(root, 'a.req.json')).thenAnswer((_) async {});

        await service.resolve(root, const [
          FileResolution(
            path: 'a.req.json',
            fieldChoices: {'url': 'https://mine'},
          ),
        ]);

        expect(written, isNotNull);
        final decoded = jsonDecode(written!) as Map<String, dynamic>;
        final node = WorkspaceCollectionSerializer.requestFromJson(decoded);
        expect(node.config!.url, 'https://mine');
        verify(() => git.add(root, 'a.req.json')).called(1);
      },
    );

    test(
      'an opaque field pick (authentication) takes the whole side',
      () async {
        when(() => git.showStage(root, 'a.req.json', 1)).thenAnswer(
          (_) async => _reqStage(_leaf(auth: const {'type': 'none'})),
        );
        when(() => git.showStage(root, 'a.req.json', 2)).thenAnswer(
          (_) async => _reqStage(
            _leaf(auth: const {'type': 'bearer', 'token': 'incoming-token'}),
          ),
        );
        when(() => git.showStage(root, 'a.req.json', 3)).thenAnswer(
          (_) async => _reqStage(
            _leaf(auth: const {'type': 'bearer', 'token': 'yours-token'}),
          ),
        );
        String? written;
        when(() => git.writeWorkingFile(root, 'a.req.json', any())).thenAnswer((
          i,
        ) async {
          written = i.positionalArguments[2] as String;
        });
        when(() => git.add(root, 'a.req.json')).thenAnswer((_) async {});

        await service.resolve(root, const [
          FileResolution(
            path: 'a.req.json',
            fieldChoices: {'authentication': 'yours'},
          ),
        ]);

        final node = WorkspaceCollectionSerializer.requestFromJson(
          jsonDecode(written!) as Map<String, dynamic>,
        );
        expect(node.config!.auth['token'], 'yours-token');
      },
    );

    test('a folder field-level resolution merges variables', () async {
      when(() => git.showStage(root, 'x/.folder.json', 1)).thenAnswer(
        (_) async => _folderStage(_folder(variables: {'k': 'base'}), ['a']),
      );
      when(() => git.showStage(root, 'x/.folder.json', 2)).thenAnswer(
        (_) async => _folderStage(_folder(variables: {'k': 'incoming'}), ['a']),
      );
      when(() => git.showStage(root, 'x/.folder.json', 3)).thenAnswer(
        (_) async => _folderStage(_folder(variables: {'k': 'yours'}), ['a']),
      );
      String? written;
      when(
        () => git.writeWorkingFile(root, 'x/.folder.json', any()),
      ).thenAnswer((i) async {
        written = i.positionalArguments[2] as String;
      });
      when(() => git.add(root, 'x/.folder.json')).thenAnswer((_) async {});

      await service.resolve(root, const [
        FileResolution(
          path: 'x/.folder.json',
          fieldChoices: {"variable 'k'": 'picked-value'},
        ),
      ]);

      final decoded = jsonDecode(written!) as Map<String, dynamic>;
      expect((decoded['variables'] as Map)['k'], 'picked-value');
      verify(() => git.add(root, 'x/.folder.json')).called(1);
    });

    test(
      'a folder "child order" pick round-trips the chosen side\'s order',
      () async {
        when(() => git.showStage(root, 'x/.folder.json', 1)).thenAnswer(
          (_) async => _folderStage(_folder(), ['a']),
        );
        when(() => git.showStage(root, 'x/.folder.json', 2)).thenAnswer(
          (_) async => _folderStage(_folder(), ['a', 'b']),
        );
        when(() => git.showStage(root, 'x/.folder.json', 3)).thenAnswer(
          (_) async => _folderStage(_folder(), ['a', 'c']),
        );
        String? written;
        when(
          () => git.writeWorkingFile(root, 'x/.folder.json', any()),
        ).thenAnswer((i) async {
          written = i.positionalArguments[2] as String;
        });
        when(() => git.add(root, 'x/.folder.json')).thenAnswer((_) async {});

        // The user picks yours' order, rendered by ThreeWayMerge as the
        // comma-joined string "a, c".
        await service.resolve(root, const [
          FileResolution(
            path: 'x/.folder.json',
            fieldChoices: {'child order': 'a, c'},
          ),
        ]);

        final decoded = jsonDecode(written!) as Map<String, dynamic>;
        expect(
          WorkspaceCollectionSerializer.childOrder(decoded),
          ['a', 'c'],
        );
      },
    );

    // FIX I1: the mirror-suspension gate must be held while resolve() writes
    // to the working tree, so a debounced Hive→disk mirror can't fire mid-way
    // and clobber the resolution.
    test('holds mirroring suspended for its whole duration', () async {
      final sync = WorkspaceSyncService(_NoopWorkspaceDataSource());
      final svc = GitConflictService(git, sync);
      when(
        () => git.showStage(root, 'a.req.json', 2),
      ).thenAnswer((_) async => 'INCOMING CONTENT');
      when(
        () => git.writeWorkingFile(root, 'a.req.json', any()),
      ).thenAnswer((_) async {
        expect(sync.isMirroringSuspended, isTrue);
      });
      when(() => git.add(root, 'a.req.json')).thenAnswer((_) async {
        expect(sync.isMirroringSuspended, isTrue);
      });

      expect(sync.isMirroringSuspended, isFalse);
      await svc.resolve(root, const [
        FileResolution(path: 'a.req.json', wholeFile: FileSide.incoming),
      ]);
      expect(sync.isMirroringSuspended, isFalse);
    });
  });

  group('continueRebase', () {
    test('maps a still-in-progress rebase to moreConflicts', () async {
      when(
        () => git.rebaseContinue(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) async {});
      when(() => git.isRebaseInProgress(root)).thenAnswer((_) async => true);

      expect(await service.continueRebase(root), RebaseStep.moreConflicts);
      verify(
        () => git.rebaseContinue(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).called(1);
    });

    test('maps a finished rebase to done', () async {
      when(
        () => git.rebaseContinue(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) async {});
      when(() => git.isRebaseInProgress(root)).thenAnswer((_) async => false);

      expect(await service.continueRebase(root), RebaseStep.done);
    });

    // FIX I1: same gate must be held across `rebase --continue`.
    test('holds mirroring suspended for its whole duration', () async {
      final sync = WorkspaceSyncService(_NoopWorkspaceDataSource());
      final svc = GitConflictService(git, sync);
      when(
        () => git.rebaseContinue(
          root,
          authorName: any(named: 'authorName'),
          authorEmail: any(named: 'authorEmail'),
        ),
      ).thenAnswer((_) async {
        expect(sync.isMirroringSuspended, isTrue);
      });
      when(() => git.isRebaseInProgress(root)).thenAnswer((_) async => false);

      expect(sync.isMirroringSuspended, isFalse);
      await svc.continueRebase(root);
      expect(sync.isMirroringSuspended, isFalse);
    });
  });

  test('abort delegates to git.rebaseAbort', () async {
    when(() => git.rebaseAbort(root)).thenAnswer((_) async {});
    await service.abort(root);
    verify(() => git.rebaseAbort(root)).called(1);
  });

  test('fetch delegates to git.fetch', () async {
    when(() => git.fetch(root)).thenAnswer((_) async {});
    await service.fetch(root);
    verify(() => git.fetch(root)).called(1);
  });

  test('pullOrConflict delegates to git.pull', () async {
    when(() => git.pull(root)).thenAnswer((_) async => PullOutcome.conflicted);
    expect(await service.pullOrConflict(root), PullOutcome.conflicted);
    verify(() => git.pull(root)).called(1);
  });
}
