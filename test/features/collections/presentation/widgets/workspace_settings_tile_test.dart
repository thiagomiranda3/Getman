// Regression tests for WorkspaceSettingsTile's RELOAD FROM DISK action: a
// workspace read failure (e.g. one malformed .req.json) must surface an error
// and change nothing — treating it as an empty workspace dispatched
// ReplaceCollections(const []), wiping the in-app tree and (via the mirror)
// deleting the workspace files on disk. Plus the flush → suspended-read
// discipline (M8): both actions flush the pending mirror before reading
// (aborting when the write failed) and dispatch ReplaceCollections with
// mirroring suspended, so the reload is never mirrored straight back over
// hand-edited files.
//
// Plus behavior tests for the rest of the tile: DISCONNECT, the not-set and
// macOS needs-reconnect renders, and the CHOOSE FOLDER connect flows (the
// directory picker is driven through file_picker's mocked method channel).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/datasources/workspace_collections_data_source.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_settings_tile.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceDataSource extends Mock
    implements WorkspaceCollectionsDataSource {}

/// Recording fake over the REAL service: stubs the tile-facing disk I/O
/// ([flushPending]/[read]/[scheduleMirror]) and records the order the tile
/// calls it in, while inheriting the genuine `withMirroringSuspended` /
/// `isMirroringSuspended` gate semantics — which is exactly what the
/// suspension tests assert on (a hand-stubbed gate would only test itself).
class _FakeWorkspaceSyncService extends WorkspaceSyncService {
  _FakeWorkspaceSyncService() : super(_MockWorkspaceDataSource());

  /// Tile-facing calls in the order they were made ('flushPending', 'read').
  final calls = <String>[];
  bool flushResult = true;
  Exception? readError;
  List<CollectionNodeEntity> onDisk = const [];
  final scheduledMirrors = <(String, List<CollectionNodeEntity>)>[];

  @override
  Future<bool> flushPending() async {
    calls.add('flushPending');
    return flushResult;
  }

  @override
  Future<List<CollectionNodeEntity>> read(String root) async {
    calls.add('read');
    final error = readError;
    if (error != null) throw error;
    return onDisk;
  }

  @override
  void scheduleMirror(String root, List<CollectionNodeEntity> forest) {
    // Recorded instead of armed: the real debounce would leave a pending
    // timer at teardown, and no test here wants a disk write. Mirrors the
    // real gate: a mirror scheduled while suspended is dropped.
    if (isMirroringSuspended) return;
    scheduledMirrors.add((root, forest));
  }
}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

class _FakeSettingsEvent extends Fake implements SettingsEvent {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeCollectionsEvent());
    registerFallbackValue(_FakeSettingsEvent());
    registerFallbackValue(const <CollectionNodeEntity>[]);
  });

  late _FakeWorkspaceSyncService sync;
  late MockCollectionsBloc collectionsBloc;
  late MockSettingsBloc settingsBloc;

  setUp(() {
    sync = _FakeWorkspaceSyncService();
    collectionsBloc = MockCollectionsBloc();
    when(() => collectionsBloc.state).thenReturn(CollectionsState());
    when(() => collectionsBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => collectionsBloc.add(any())).thenReturn(null);
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.state).thenReturn(
      const SettingsState(
        settings: SettingsEntity(workspacePath: '/tmp/ws'),
      ),
    );
    when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsBloc.add(any())).thenReturn(null);
  });

  tearDown(() => sync.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: RepositoryProvider<WorkspaceSyncService>.value(
            value: sync,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
                BlocProvider<SettingsBloc>.value(value: settingsBloc),
              ],
              child: const SingleChildScrollView(
                child: WorkspaceSettingsTile(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Answers file_picker's `dir` (directory picker) channel call with [path]
  /// — `null` means the user canceled the panel.
  void mockDirectoryPicker(WidgetTester tester, String? path) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
      (call) async => call.method == 'dir' ? path : null,
    );
  }

  testWidgets(
    'a failed workspace read on RELOAD FROM DISK replaces nothing '
    'and shows an error',
    (tester) async {
      sync.readError = const FormatException('conflict markers in a.req.json');

      await pump(tester);
      await tester.tap(find.text('RELOAD FROM DISK'));
      await tester.pumpAndSettle();

      verifyNever(() => collectionsBloc.add(any()));
      expect(find.textContaining('Could not read the workspace'), findsOne);
    },
  );

  testWidgets('a successful read replaces the collections', (tester) async {
    final onDisk = [const CollectionNodeEntity(id: 'n1', name: 'A')];
    sync.onDisk = onDisk;

    await pump(tester);
    await tester.tap(find.text('RELOAD FROM DISK'));
    await tester.pumpAndSettle();

    final event =
        verify(() => collectionsBloc.add(captureAny())).captured.single
            as ReplaceCollections;
    expect(event.rootNodes, onDisk);
    expect(find.text('Reloaded 1 item(s) from disk'), findsOneWidget);
  });

  // M8: without the flush, a debounced/in-flight mirror write races the
  // reload's directory walk — the read imports a mixed old/new forest and
  // the next mirror writes it back over the user's newest edit.
  testWidgets('RELOAD FROM DISK flushes the pending mirror before reading', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('RELOAD FROM DISK'));
    await tester.pumpAndSettle();

    expect(sync.calls, ['flushPending', 'read']);
  });

  testWidgets(
    'RELOAD FROM DISK dispatches ReplaceCollections with mirroring '
    'suspended, and releases the gate afterwards',
    (tester) async {
      bool? suspendedAtDispatch;
      when(() => collectionsBloc.add(any())).thenAnswer((_) {
        suspendedAtDispatch = sync.isMirroringSuspended;
      });

      await pump(tester);
      await tester.tap(find.text('RELOAD FROM DISK'));
      await tester.pumpAndSettle();

      // Suspended at dispatch: the state change must not be mirrored back
      // over the files just read. Released after: a leaked gate would
      // silently stop mirroring for the rest of the session.
      expect(suspendedAtDispatch, isTrue);
      expect(sync.isMirroringSuspended, isFalse);
    },
  );

  testWidgets(
    'a failed mirror flush aborts RELOAD FROM DISK — nothing read, '
    'nothing replaced',
    (tester) async {
      sync.flushResult = false;

      await pump(tester);
      await tester.tap(find.text('RELOAD FROM DISK'));
      await tester.pumpAndSettle();

      expect(sync.calls, ['flushPending']);
      verifyNever(() => collectionsBloc.add(any()));
      expect(
        find.textContaining('Could not write the workspace'),
        findsOne,
      );
    },
  );

  testWidgets('DISCONNECT clears the workspace path', (tester) async {
    await pump(tester);
    await tester.tap(find.text('DISCONNECT'));
    await tester.pump();

    verify(
      () => settingsBloc.add(const UpdateWorkspacePath(null)),
    ).called(1);
  });

  testWidgets('without a workspace only CHOOSE FOLDER is offered', (
    tester,
  ) async {
    when(() => settingsBloc.state).thenReturn(
      const SettingsState(settings: SettingsEntity()),
    );

    await pump(tester);

    expect(
      find.text('Not set — collections live only in-app.'),
      findsOneWidget,
    );
    expect(find.text('CHOOSE FOLDER'), findsOneWidget);
    expect(find.text('RELOAD FROM DISK'), findsNothing);
    expect(find.text('DISCONNECT'), findsNothing);
  });

  group('macOS security-scoped bookmark', () {
    // WorkspaceBookmarks.supported keys off defaultTargetPlatform — the
    // variant sets (and restores) the macOS override around each run.
    final onMacOS = TargetPlatformVariant.only(TargetPlatform.macOS);

    testWidgets(
      'a connected path with no stored bookmark asks for a reconnect',
      (tester) async {
        await pump(tester);

        expect(
          find.textContaining('Reconnect this folder'),
          findsOneWidget,
        );
      },
      variant: onMacOS,
    );

    testWidgets(
      'no reconnect warning once a bookmark is stored',
      (tester) async {
        when(() => settingsBloc.state).thenReturn(
          const SettingsState(
            settings: SettingsEntity(
              workspacePath: '/tmp/ws',
              workspaceBookmark: 'bm==',
            ),
          ),
        );

        await pump(tester);

        expect(find.textContaining('Reconnect this folder'), findsNothing);
      },
      variant: onMacOS,
    );
  });

  group('CHOOSE FOLDER', () {
    testWidgets(
      'a folder with content asks before importing, then replaces and '
      'connects',
      (tester) async {
        mockDirectoryPicker(tester, '/picked/ws');
        final onDisk = [const CollectionNodeEntity(id: 'n1', name: 'A')];
        sync.onDisk = onDisk;

        await pump(tester);
        await tester.tap(find.text('CHOOSE FOLDER'));
        await tester.pumpAndSettle();

        // The pending mirror is flushed before the picked folder is read
        // (same M8 discipline as RELOAD FROM DISK).
        expect(sync.calls, ['flushPending', 'read']);
        expect(find.text('IMPORT WORKSPACE'), findsOneWidget);
        expect(find.textContaining('1 item(s)'), findsOneWidget);

        await tester.tap(find.text('IMPORT'));
        await tester.pumpAndSettle();

        final event =
            verify(() => collectionsBloc.add(captureAny())).captured.single
                as ReplaceCollections;
        expect(event.rootNodes, onDisk);
        verify(
          () => settingsBloc.add(const UpdateWorkspacePath('/picked/ws')),
        ).called(1);
        expect(find.text('Workspace connected'), findsOneWidget);
      },
    );

    testWidgets(
      'the import confirm dispatches ReplaceCollections with mirroring '
      'suspended, and releases the gate afterwards',
      (tester) async {
        mockDirectoryPicker(tester, '/picked/ws');
        sync.onDisk = [const CollectionNodeEntity(id: 'n1', name: 'A')];
        bool? suspendedAtDispatch;
        when(() => collectionsBloc.add(any())).thenAnswer((_) {
          suspendedAtDispatch = sync.isMirroringSuspended;
        });

        await pump(tester);
        await tester.tap(find.text('CHOOSE FOLDER'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('IMPORT'));
        await tester.pumpAndSettle();

        expect(suspendedAtDispatch, isTrue);
        expect(sync.isMirroringSuspended, isFalse);
      },
    );

    testWidgets(
      'a failed mirror flush aborts CHOOSE FOLDER when re-picking the '
      'CURRENT folder — nothing read, nothing connected',
      (tester) async {
        // Same path as the connected workspace ('/tmp/ws' in setUp): a
        // half-written tree there is exactly what the read must not walk.
        mockDirectoryPicker(tester, '/tmp/ws');
        sync.flushResult = false;

        await pump(tester);
        await tester.tap(find.text('CHOOSE FOLDER'));
        await tester.pumpAndSettle();

        expect(sync.calls, ['flushPending']);
        verifyNever(() => settingsBloc.add(any()));
        verifyNever(() => collectionsBloc.add(any()));
        expect(
          find.textContaining('Could not write the workspace'),
          findsOne,
        );
      },
    );

    testWidgets(
      'a failed flush does NOT veto choosing a DIFFERENT folder — the '
      'failure only poisons the old root, and blocking here would wedge '
      'the user on an unwritable workspace',
      (tester) async {
        mockDirectoryPicker(tester, '/picked/ws');
        sync.flushResult = false;

        await pump(tester);
        await tester.tap(find.text('CHOOSE FOLDER'));
        await tester.pumpAndSettle();

        // Empty on-disk folder → export + connect, exactly as with a
        // healthy flush.
        expect(sync.calls, ['flushPending', 'read']);
        verify(
          () => settingsBloc.add(const UpdateWorkspacePath('/picked/ws')),
        ).called(1);
        expect(find.text('Workspace connected'), findsOneWidget);
      },
    );

    testWidgets('an empty folder exports the current collections into it', (
      tester,
    ) async {
      mockDirectoryPicker(tester, '/picked/ws');

      await pump(tester);
      await tester.tap(find.text('CHOOSE FOLDER'));
      await tester.pumpAndSettle();

      // No confirm dialog on an empty folder — straight to mirror + connect.
      expect(find.text('IMPORT WORKSPACE'), findsNothing);
      expect(sync.scheduledMirrors, hasLength(1));
      expect(sync.scheduledMirrors.single.$1, '/picked/ws');
      verifyNever(() => collectionsBloc.add(any()));
      verify(
        () => settingsBloc.add(const UpdateWorkspacePath('/picked/ws')),
      ).called(1);
      expect(find.text('Workspace connected'), findsOneWidget);
    });

    testWidgets('a failed read never connects the workspace', (tester) async {
      mockDirectoryPicker(tester, '/picked/ws');
      sync.readError = const FormatException('broken .req.json');

      await pump(tester);
      await tester.tap(find.text('CHOOSE FOLDER'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not read that folder'),
        findsOneWidget,
      );
      // The failed read must also not leak the suspension gate.
      expect(sync.isMirroringSuspended, isFalse);
      verifyNever(() => settingsBloc.add(any()));
      verifyNever(() => collectionsBloc.add(any()));
    });

    testWidgets('canceling the picker changes nothing', (tester) async {
      mockDirectoryPicker(tester, null);

      await pump(tester);
      await tester.tap(find.text('CHOOSE FOLDER'));
      await tester.pumpAndSettle();

      expect(sync.calls, isEmpty);
      verifyNever(() => settingsBloc.add(any()));
    });
  });
}
