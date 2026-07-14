// Widget tests for BranchSyncListener:
// - a bumped GitSyncState.reloadToken re-reads the forest from disk and pushes
//   it into CollectionsBloc (git rewrote the files underneath the app).
// - an unchanged reloadToken does not touch the disk.
// - the reload does NOT bounce straight back out as a mirror write (the
//   reload → mirror → reload feedback loop), because the reload runs with
//   WorkspaceSyncService mirroring suspended.
// - an edit made *during* the reload's (slow) disk read is never mirrored: the
//   read runs inside the suspension, so the old branch's forest — still in
//   Hive until the read lands — can never be written onto the new branch.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_event.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_state.dart';
import 'package:getman/features/collections/presentation/widgets/branch_sync_listener.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockGitSyncBloc extends MockBloc<GitSyncEvent, GitSyncState>
    implements GitSyncBloc {}

class _MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _MockDataSource extends Mock implements WorkspaceCollectionsDataSource {}

class _MockCollectionsRepository extends Mock
    implements CollectionsRepository {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

void main() {
  const root = '/ws';
  const node = CollectionNodeEntity(
    id: 'n',
    name: 'From disk',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'n'),
  );

  late _MockDataSource ds;
  late _MockSaveSettingsUseCase saveSettings;

  setUpAll(() {
    registerFallbackValue(_FakeCollectionsEvent());
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    ds = _MockDataSource();
    saveSettings = _MockSaveSettingsUseCase();
    when(() => ds.read(root)).thenAnswer((_) async => const [node]);
    when(() => ds.write(any(), any())).thenAnswer((_) async {});
    when(() => saveSettings(any())).thenAnswer((_) async {});
  });

  SettingsBloc buildSettingsBloc({String? path = root}) => SettingsBloc(
    saveSettingsUseCase: saveSettings,
    initialSettings: SettingsEntity(workspacePath: path),
  );

  Widget host({
    required GitSyncBloc gitSync,
    required CollectionsBloc collections,
    required SettingsBloc settings,
    required WorkspaceSyncService sync,
    bool withMirroring = false,
  }) {
    const listener = BranchSyncListener(child: SizedBox());
    return MaterialApp(
      home: RepositoryProvider<WorkspaceSyncService>.value(
        value: sync,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<GitSyncBloc>.value(value: gitSync),
            BlocProvider<CollectionsBloc>.value(value: collections),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: withMirroring
              // The real mirroring listener sits above in main.dart — this is
              // the pairing that can loop reload → mirror → reload.
              ? const WorkspaceSyncListener(child: listener)
              : listener,
        ),
      ),
    );
  }

  testWidgets('a bumped reloadToken reloads the tree from disk', (
    tester,
  ) async {
    final gitSync = _MockGitSyncBloc();
    final collections = _MockCollectionsBloc();
    final settings = buildSettingsBloc();
    addTearDown(settings.close);
    final sync = WorkspaceSyncService(ds);
    addTearDown(sync.dispose);

    when(() => collections.state).thenReturn(CollectionsState());
    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.ready),
        const GitSyncState(status: GitSyncStatus.ready, reloadToken: 1),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      host(
        gitSync: gitSync,
        collections: collections,
        settings: settings,
        sync: sync,
      ),
    );
    await tester.pumpAndSettle();

    final captured = verify(
      () => collections.add(captureAny()),
    ).captured.whereType<ReplaceCollections>().toList();
    expect(captured, hasLength(1));
    expect(captured.single.rootNodes.single.name, 'From disk');
  });

  testWidgets('an unchanged reloadToken does not reload', (tester) async {
    final gitSync = _MockGitSyncBloc();
    final collections = _MockCollectionsBloc();
    final settings = buildSettingsBloc();
    addTearDown(settings.close);
    final sync = WorkspaceSyncService(ds);
    addTearDown(sync.dispose);

    when(() => collections.state).thenReturn(CollectionsState());
    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.busy),
        const GitSyncState(status: GitSyncStatus.ready),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      host(
        gitSync: gitSync,
        collections: collections,
        settings: settings,
        sync: sync,
      ),
    );
    await tester.pumpAndSettle();

    verifyNever(() => ds.read(any()));
  });

  testWidgets('no workspace path configured: no reload', (tester) async {
    final gitSync = _MockGitSyncBloc();
    final collections = _MockCollectionsBloc();
    final settings = buildSettingsBloc(path: null);
    addTearDown(settings.close);
    final sync = WorkspaceSyncService(ds);
    addTearDown(sync.dispose);

    when(() => collections.state).thenReturn(CollectionsState());
    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.ready, reloadToken: 1),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      host(
        gitSync: gitSync,
        collections: collections,
        settings: settings,
        sync: sync,
      ),
    );
    await tester.pumpAndSettle();

    verifyNever(() => ds.read(any()));
    verifyNever(() => collections.add(any()));
  });

  testWidgets('the reload does not mirror the forest it just read', (
    tester,
  ) async {
    final repo = _MockCollectionsRepository();
    when(repo.getCollections).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});

    final gitSync = _MockGitSyncBloc();
    final collections = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(repo),
      saveCollectionsUseCase: SaveCollectionsUseCase(repo),
      saveDebounce: const Duration(milliseconds: 5),
    );
    addTearDown(collections.close);
    final settings = buildSettingsBloc();
    addTearDown(settings.close);
    final sync = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(sync.dispose);

    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.ready, reloadToken: 1),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      host(
        gitSync: gitSync,
        collections: collections,
        settings: settings,
        sync: sync,
        withMirroring: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // The tree came *from* disk — mirroring it back would rewrite the files
    // git just checked out (and, worse, re-arm the loop).
    verifyNever(() => ds.write(any(), any()));
    expect(collections.state.collections.single.name, 'From disk');

    // ...and mirroring is live again afterwards: a genuine user edit still
    // reaches disk (the gate must not wedge mirroring off).
    collections.add(
      const ReplaceCollections([CollectionNodeEntity(id: 'f', name: 'Edited')]),
    );
    await tester.pump(const Duration(milliseconds: 200));

    verify(() => ds.write(root, any())).called(1);
  });

  testWidgets('an edit made DURING the reload read is never mirrored', (
    tester,
  ) async {
    // The window this closes: git has already rewritten the working tree, so
    // GitBranchService has resumed mirroring — but Hive still holds the OLD
    // branch's forest until the read lands. `read` walks the whole workspace
    // (slow on a big tree / cold FS), and an edit made while it runs would arm
    // a mirror of the old-branch forest that fires onto the NEW branch.
    // The read must therefore run INSIDE the suspension.
    final gate = Completer<void>();
    when(() => ds.read(root)).thenAnswer((_) async {
      await gate.future;
      return const [node];
    });
    // Recorded in the stub rather than via `captured`: mocktail's `verify`
    // fails outright on zero calls, which is exactly the passing case here.
    final written = <CollectionNodeEntity>[];
    when(() => ds.write(any(), any())).thenAnswer((invocation) async {
      written.addAll(
        invocation.positionalArguments[1] as List<CollectionNodeEntity>,
      );
    });

    final repo = _MockCollectionsRepository();
    when(repo.getCollections).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});

    final gitSync = _MockGitSyncBloc();
    final collections = CollectionsBloc(
      getCollectionsUseCase: GetCollectionsUseCase(repo),
      saveCollectionsUseCase: SaveCollectionsUseCase(repo),
      saveDebounce: const Duration(milliseconds: 5),
    );
    addTearDown(collections.close);
    final settings = buildSettingsBloc();
    addTearDown(settings.close);
    // Debounce well inside the read: the mirror would fire mid-read.
    final sync = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(sync.dispose);

    whenListen(
      gitSync,
      Stream<GitSyncState>.fromIterable([
        const GitSyncState(status: GitSyncStatus.ready, reloadToken: 1),
      ]),
      initialState: const GitSyncState(),
    );

    await tester.pumpWidget(
      host(
        gitSync: gitSync,
        collections: collections,
        settings: settings,
        sync: sync,
        withMirroring: true,
      ),
    );
    // The reload is now blocked on `ds.read`. The user edits a request.
    await tester.pump();
    collections.add(
      const ReplaceCollections([
        CollectionNodeEntity(id: 'old', name: 'Old branch edit'),
      ]),
    );
    // Long enough for the mirror debounce to fire, if it were armed at all.
    await tester.pump(const Duration(milliseconds: 100));

    gate.complete();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      written.map((n) => n.name),
      isNot(contains('Old branch edit')),
      reason: "the old branch's forest was mirrored onto the new branch",
    );
    expect(collections.state.collections.single.name, 'From disk');
  });
}
