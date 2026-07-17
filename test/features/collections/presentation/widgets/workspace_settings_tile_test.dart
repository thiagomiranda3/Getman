// Regression tests for WorkspaceSettingsTile's RELOAD FROM DISK action: a
// workspace read failure (e.g. one malformed .req.json) must surface an error
// and change nothing — treating it as an empty workspace dispatched
// ReplaceCollections(const []), wiping the in-app tree and (via the mirror)
// deleting the workspace files on disk.

import 'package:flutter/material.dart';
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
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:mocktail/mocktail.dart';

class MockWorkspaceSyncService extends Mock implements WorkspaceSyncService {}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeCollectionsEvent()));

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
}
