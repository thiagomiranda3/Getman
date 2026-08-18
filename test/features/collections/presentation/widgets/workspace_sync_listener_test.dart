// Widget tests for WorkspaceSyncListener (mirror + boot-import coordinator):
// - M3 boot sequence: with a workspace connected at boot, the on-disk forest
//   is imported into Hive BEFORE any mirror write can touch the workspace —
//   launching the app must never destroy changes git made while it was
//   closed. App-only data (saved examples) survives the merge, which also
//   proves the import waited for the LOADED collections state (an import
//   racing LoadCollections would overlay onto an empty tree and drop it).
// - an in-app edit AFTER the boot import mirrors to disk as before.
// - a failed boot read wipes nothing, surfaces a snackbar, and leaves
//   mirroring sticky-blocked for the root (WorkspaceSyncService.read's gate).
// - a workspace connected mid-session (the settings-tile flow, which imports
//   before connecting) is NOT gated: its changes mirror with no boot read.
// - no workspace path -> no disk traffic; the child is always rendered.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockWorkspaceDataSource extends Mock
    implements WorkspaceCollectionsDataSource {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

void main() {
  const root = '/ws';

  // Disk (what git left in the workspace while the app was closed).
  const sharedOnDisk = CollectionNodeEntity(
    id: 'shared',
    name: 'Shared',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'shared'),
  );
  const pulledByGit = CollectionNodeEntity(
    id: 'from-git',
    name: 'From git',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'from-git'),
  );
  const diskForest = [sharedOnDisk, pulledByGit];

  // Hive (last session's tree): same shared node but carrying an app-only
  // saved example, plus a node that no longer exists on disk.
  final sharedInHive = sharedOnDisk.copyWith(
    examples: [
      SavedExampleEntity(
        id: 'ex1',
        name: 'Example',
        capturedAt: DateTime.utc(2026),
        config: const HttpRequestConfigEntity(id: 'shared'),
      ),
    ],
  );
  const onlyInHive = CollectionNodeEntity(
    id: 'only-hive',
    name: 'Only in Hive',
    isFolder: false,
    config: HttpRequestConfigEntity(id: 'only-hive'),
  );

  late MockCollectionsRepository collectionsRepo;
  late MockWorkspaceDataSource ds;
  late MockSaveSettingsUseCase saveSettingsUseCase;
  late List<List<CollectionNodeEntity>> written;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    collectionsRepo = MockCollectionsRepository();
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => [sharedInHive, onlyInHive]);
    when(
      () => collectionsRepo.saveCollections(any()),
    ).thenAnswer((_) async {});

    ds = MockWorkspaceDataSource();
    when(() => ds.read(root)).thenAnswer((_) async => diskForest);
    // Recorded in the stub rather than via `captured`: mocktail's `verify`
    // fails outright on zero calls, which is exactly the passing case for
    // the no-write assertions below.
    written = [];
    when(() => ds.write(any(), any())).thenAnswer((invocation) async {
      written.add(
        List.of(
          invocation.positionalArguments[1] as List<CollectionNodeEntity>,
        ),
      );
    });

    saveSettingsUseCase = MockSaveSettingsUseCase();
    when(() => saveSettingsUseCase(any())).thenAnswer((_) async {});
  });

  CollectionsBloc buildCollectionsBloc() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(collectionsRepo),
    saveCollectionsUseCase: SaveCollectionsUseCase(collectionsRepo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  SettingsBloc buildSettingsBloc(SettingsEntity settings) => SettingsBloc(
    saveSettingsUseCase: saveSettingsUseCase,
    initialSettings: settings,
  );

  Widget host(
    CollectionsBloc collectionsBloc,
    SettingsBloc settingsBloc,
    WorkspaceSyncService sync, {
    Widget child = const SizedBox.expand(),
  }) {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: RepositoryProvider<WorkspaceSyncService>.value(
          value: sync,
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: collectionsBloc),
              BlocProvider.value(value: settingsBloc),
            ],
            child: WorkspaceSyncListener(child: child),
          ),
        ),
      ),
    );
  }

  /// Mounts the listener with [root] connected (as at app boot) and drives the
  /// boot sequence: LoadCollections, its emissions, the boot import, and
  /// enough time for the 20ms mirror debounce to have fired if it were armed.
  Future<(CollectionsBloc, WorkspaceSyncService)> pumpBoot(
    WidgetTester tester,
  ) async {
    final collectionsBloc = buildCollectionsBloc();
    addTearDown(collectionsBloc.close);
    final settingsBloc = buildSettingsBloc(
      const SettingsEntity(workspacePath: root),
    );
    addTearDown(settingsBloc.close);
    final sync = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(sync.dispose);

    await tester.pumpWidget(host(collectionsBloc, settingsBloc, sync));
    // main.dart dispatches LoadCollections at bloc creation; its emissions
    // land after the listener has subscribed, same as here.
    collectionsBloc.add(const LoadCollections());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    return (collectionsBloc, sync);
  }

  testWidgets(
    'boot imports the on-disk workspace into the tree BEFORE any mirror '
    'write can touch it (M3)',
    (tester) async {
      final (collectionsBloc, _) = await pumpBoot(tester);

      // The disk forest reached the tree...
      expect(verify(() => ds.read(root)).callCount, 1);
      final names = collectionsBloc.state.collections.map((n) => n.name);
      expect(names, containsAll(['Shared', 'From git']));
      // ...with disk as the winner for tree structure: a node only in Hive is
      // dropped, exactly like every other reload path (BranchSyncListener,
      // the settings tile) — deliberate M3 design, disk is authoritative
      // after external git activity.
      expect(names, isNot(contains('Only in Hive')));
      // App-only data survived the merge — which also proves the import ran
      // against the LOADED tree: overlaying onto the pre-load empty tree
      // would have dropped the example.
      final shared = collectionsBloc.state.collections.firstWhere(
        (n) => n.id == 'shared',
      );
      expect(shared.examples, hasLength(1));

      // And the workspace was NEVER written during boot: the old behavior
      // (mirror ~1s after LoadCollections, no read first) reconciled the
      // teammate's new file into oblivion.
      expect(written, isEmpty);
    },
  );

  testWidgets('an in-app edit after the boot import DOES mirror', (
    tester,
  ) async {
    final (collectionsBloc, _) = await pumpBoot(tester);
    expect(written, isEmpty);

    const edited = CollectionNodeEntity(id: 'new', name: 'Edited');
    collectionsBloc.add(
      const ReplaceCollections([sharedOnDisk, pulledByGit, edited]),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(written, hasLength(1));
    expect(written.single.map((n) => n.name), contains('Edited'));
    // The mirrored forest still carries the node git pulled in — the boot
    // import is what keeps the first post-boot mirror from deleting it.
    expect(written.single.map((n) => n.name), contains('From git'));
    verify(() => ds.write(root, any())).called(1);
  });

  testWidgets(
    'a failed boot read wipes nothing and leaves mirroring blocked',
    (tester) async {
      when(() => ds.read(root)).thenThrow(StateError('malformed .req.json'));

      final (collectionsBloc, sync) = await pumpBoot(tester);

      // The in-app tree is exactly what Hive loaded — no ReplaceCollections
      // wipe, examples intact.
      final names = collectionsBloc.state.collections.map((n) => n.name);
      expect(names, containsAll(['Shared', 'Only in Hive']));
      final shared = collectionsBloc.state.collections.firstWhere(
        (n) => n.id == 'shared',
      );
      expect(shared.examples, hasLength(1));

      // The failure is surfaced, not silent (the harness hosts the listener
      // under a Scaffold; in production the log fallback fires instead).
      expect(find.byType(SnackBar), findsOneWidget);

      // sync.read sticky-blocked the root: a later edit must NOT reach disk —
      // Hive no longer matches disk, and a resumed mirror would overwrite the
      // files git changed.
      expect(sync.isReloadBlocked(root), isTrue);
      collectionsBloc.add(
        const ReplaceCollections([CollectionNodeEntity(id: 'e', name: 'E')]),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(written, isEmpty);

      // Drain the snackbar's one-shot timer so the binding tears down clean.
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'a workspace connected mid-session mirrors immediately with no boot read '
    '(the settings tile already imported it)',
    (tester) async {
      final collectionsBloc = buildCollectionsBloc();
      addTearDown(collectionsBloc.close);
      // Boot with NO workspace — the tile connects one later.
      final settingsBloc = buildSettingsBloc(const SettingsEntity());
      addTearDown(settingsBloc.close);
      final sync = WorkspaceSyncService(
        ds,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(sync.dispose);

      await tester.pumpWidget(host(collectionsBloc, settingsBloc, sync));
      collectionsBloc.add(const LoadCollections());
      await tester.pump(const Duration(milliseconds: 100));

      // The tile flow: it reads the folder + dispatches ReplaceCollections
      // itself, then connects the path.
      settingsBloc.add(const UpdateWorkspacePath(root));
      await tester.pump(const Duration(milliseconds: 50));
      collectionsBloc.add(const ReplaceCollections(diskForest));
      await tester.pump(const Duration(milliseconds: 200));

      // Mirrored straight away — the boot gate must not apply to a root
      // connected mid-session (its ReplaceCollections must still mirror)...
      expect(written, hasLength(1));
      // ...and the listener never second-guessed the tile with its own read.
      verifyNever(() => ds.read(any()));
    },
  );

  testWidgets('does nothing when no workspace path is configured', (
    tester,
  ) async {
    final collectionsBloc = buildCollectionsBloc();
    addTearDown(collectionsBloc.close);
    final settingsBloc = buildSettingsBloc(const SettingsEntity());
    addTearDown(settingsBloc.close);
    final sync = WorkspaceSyncService(
      ds,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(sync.dispose);

    await tester.pumpWidget(host(collectionsBloc, settingsBloc, sync));
    collectionsBloc.add(const LoadCollections());
    await tester.pump(const Duration(milliseconds: 100));
    collectionsBloc.add(
      const ReplaceCollections([CollectionNodeEntity(id: 'f1', name: 'F')]),
    );
    await tester.pump(const Duration(milliseconds: 200));

    verifyNever(() => ds.read(any()));
    expect(written, isEmpty);
  });

  testWidgets('renders its child widget', (tester) async {
    final collectionsBloc = buildCollectionsBloc();
    addTearDown(collectionsBloc.close);
    final settingsBloc = buildSettingsBloc(const SettingsEntity());
    addTearDown(settingsBloc.close);
    final sync = WorkspaceSyncService(ds);
    addTearDown(sync.dispose);

    const childKey = ValueKey('sync_listener_child');
    await tester.pumpWidget(
      host(
        collectionsBloc,
        settingsBloc,
        sync,
        child: const SizedBox.expand(key: childKey),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(childKey), findsOneWidget);
  });
}
