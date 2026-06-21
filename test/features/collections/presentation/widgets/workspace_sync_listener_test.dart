// Widget tests for WorkspaceSyncListener:
// - forwards to WorkspaceSyncService.scheduleMirror when collections change
//   and a workspace path is configured.
// - is a no-op when no workspace path is configured.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/widgets/workspace_sync_listener.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

class MockWorkspaceSyncService extends Mock implements WorkspaceSyncService {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

void main() {
  late MockCollectionsRepository collectionsRepo;
  late MockWorkspaceSyncService syncService;
  late MockSaveSettingsUseCase saveSettingsUseCase;

  setUpAll(() {
    registerFallbackValue(<CollectionNodeEntity>[]);
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    collectionsRepo = MockCollectionsRepository();
    when(
      () => collectionsRepo.getCollections(),
    ).thenAnswer((_) async => []);
    when(
      () => collectionsRepo.saveCollections(any()),
    ).thenAnswer((_) async {});

    syncService = MockWorkspaceSyncService();
    when(
      () => syncService.scheduleMirror(any(), any()),
    ).thenAnswer((_) async {});

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

  Widget host(CollectionsBloc collectionsBloc, SettingsBloc settingsBloc) {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: RepositoryProvider<WorkspaceSyncService>.value(
          value: syncService,
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: collectionsBloc),
              BlocProvider.value(value: settingsBloc),
            ],
            child: const WorkspaceSyncListener(
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'calls scheduleMirror when collections change and workspace is set',
    (tester) async {
      final collectionsBloc = buildCollectionsBloc();
      addTearDown(collectionsBloc.close);

      const workspacePath = '/tmp/workspace';
      final settingsBloc = buildSettingsBloc(
        const SettingsEntity(workspacePath: workspacePath),
      );
      addTearDown(settingsBloc.close);

      await tester.pumpWidget(host(collectionsBloc, settingsBloc));
      await tester.pump(const Duration(milliseconds: 50));

      // Trigger a collection change
      const node = CollectionNodeEntity(
        id: 'f1',
        name: 'Folder',
      );
      collectionsBloc.add(const ReplaceCollections([node]));
      await tester.pump(const Duration(milliseconds: 50));

      verify(
        () => syncService.scheduleMirror(workspacePath, any()),
      ).called(greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'does NOT call scheduleMirror when no workspace path is configured',
    (tester) async {
      final collectionsBloc = buildCollectionsBloc();
      addTearDown(collectionsBloc.close);

      // No workspace path (null)
      final settingsBloc = buildSettingsBloc(const SettingsEntity());
      addTearDown(settingsBloc.close);

      await tester.pumpWidget(host(collectionsBloc, settingsBloc));
      await tester.pump(const Duration(milliseconds: 50));

      const node = CollectionNodeEntity(id: 'f1', name: 'Folder');
      collectionsBloc.add(const ReplaceCollections([node]));
      await tester.pump(const Duration(milliseconds: 50));

      verifyNever(() => syncService.scheduleMirror(any(), any()));
    },
  );

  testWidgets('renders its child widget', (tester) async {
    final collectionsBloc = buildCollectionsBloc();
    addTearDown(collectionsBloc.close);
    final settingsBloc = buildSettingsBloc(const SettingsEntity());
    addTearDown(settingsBloc.close);

    await tester.pumpWidget(host(collectionsBloc, settingsBloc));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SizedBox), findsWidgets);
  });
}
