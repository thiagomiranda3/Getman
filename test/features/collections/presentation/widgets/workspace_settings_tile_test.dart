// Regression tests for WorkspaceSettingsTile's RELOAD FROM DISK action: a
// workspace read failure (e.g. one malformed .req.json) must surface an error
// and change nothing — treating it as an empty workspace dispatched
// ReplaceCollections(const []), wiping the in-app tree and (via the mirror)
// deleting the workspace files on disk.
//
// Plus behavior tests for the rest of the tile: DISCONNECT, the not-set and
// macOS needs-reconnect renders, and the CHOOSE FOLDER connect flows (the
// directory picker is driven through file_picker's mocked method channel).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
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

class MockWorkspaceSyncService extends Mock implements WorkspaceSyncService {}

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

  late MockWorkspaceSyncService sync;
  late MockCollectionsBloc collectionsBloc;
  late MockSettingsBloc settingsBloc;

  setUp(() {
    sync = MockWorkspaceSyncService();
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
      when(
        () => sync.read(any()),
      ).thenThrow(const FormatException('conflict markers in a.req.json'));

      await pump(tester);
      await tester.tap(find.text('RELOAD FROM DISK'));
      await tester.pumpAndSettle();

      verifyNever(() => collectionsBloc.add(any()));
      expect(find.textContaining('Could not read the workspace'), findsOne);
    },
  );

  testWidgets('a successful read replaces the collections', (tester) async {
    final onDisk = [const CollectionNodeEntity(id: 'n1', name: 'A')];
    when(() => sync.read(any())).thenAnswer((_) async => onDisk);

    await pump(tester);
    await tester.tap(find.text('RELOAD FROM DISK'));
    await tester.pumpAndSettle();

    final event =
        verify(() => collectionsBloc.add(captureAny())).captured.single
            as ReplaceCollections;
    expect(event.rootNodes, onDisk);
  });

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
        when(() => sync.read('/picked/ws')).thenAnswer((_) async => onDisk);

        await pump(tester);
        await tester.tap(find.text('CHOOSE FOLDER'));
        await tester.pumpAndSettle();

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

    testWidgets('an empty folder exports the current collections into it', (
      tester,
    ) async {
      mockDirectoryPicker(tester, '/picked/ws');
      when(() => sync.read('/picked/ws')).thenAnswer((_) async => []);
      when(() => sync.scheduleMirror(any(), any())).thenReturn(null);

      await pump(tester);
      await tester.tap(find.text('CHOOSE FOLDER'));
      await tester.pumpAndSettle();

      // No confirm dialog on an empty folder — straight to mirror + connect.
      expect(find.text('IMPORT WORKSPACE'), findsNothing);
      verify(() => sync.scheduleMirror('/picked/ws', any())).called(1);
      verifyNever(() => collectionsBloc.add(any()));
      verify(
        () => settingsBloc.add(const UpdateWorkspacePath('/picked/ws')),
      ).called(1);
      expect(find.text('Workspace connected'), findsOneWidget);
    });

    testWidgets('a failed read never connects the workspace', (tester) async {
      mockDirectoryPicker(tester, '/picked/ws');
      when(
        () => sync.read('/picked/ws'),
      ).thenThrow(const FormatException('broken .req.json'));

      await pump(tester);
      await tester.tap(find.text('CHOOSE FOLDER'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not read that folder'),
        findsOneWidget,
      );
      verifyNever(() => settingsBloc.add(any()));
      verifyNever(() => collectionsBloc.add(any()));
    });

    testWidgets('canceling the picker changes nothing', (tester) async {
      mockDirectoryPicker(tester, null);

      await pump(tester);
      await tester.tap(find.text('CHOOSE FOLDER'));
      await tester.pumpAndSettle();

      verifyNever(() => sync.read(any()));
      verifyNever(() => settingsBloc.add(any()));
    });
  });
}
