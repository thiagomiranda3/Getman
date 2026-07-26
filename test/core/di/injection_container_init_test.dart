import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/features/chaining/domain/repositories/request_rules_repository.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/conflict_service.dart';
import 'package:getman/features/collections/domain/pull_request_service.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/conflict_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/git_sync_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/pull_requests_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';

/// Boots the real dependency graph (`di.init`) against a throwaway Hive
/// directory and resolves every root registration. Lazy singletons only run
/// their factory bodies on first resolution, so a wiring mistake (wrong
/// dependency, missing registration, bad constructor argument) surfaces here
/// instead of at first use in the running app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_di_init_test');
  });

  tearDown(() async {
    await di.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'init boots the full graph and every root registration resolves',
    () async {
      final settings = await di.init(storageDirectoryOverride: tempDir.path);

      // A fresh directory boots with default settings.
      expect(settings, const SettingsEntity());

      // Blocs (closed below so no controllers leak past the test).
      final settingsBloc = di.sl<SettingsBloc>();
      final historyBloc = di.sl<HistoryBloc>();
      final collectionsBloc = di.sl<CollectionsBloc>();
      final rulesBloc = di.sl<RulesBloc>();
      final environmentsBloc = di.sl<EnvironmentsBloc>();
      final tabsBloc = di.sl<TabsBloc>();
      final realtimeBloc = di.sl<RealtimeBloc>();
      final mcpBloc = di.sl<McpBloc>();
      // Factory-registered git blocs: each resolution builds a new instance.
      final reviewBloc = di.sl<ReviewBloc>();
      final gitSyncBloc = di.sl<GitSyncBloc>();
      final pullRequestsBloc = di.sl<PullRequestsBloc>();
      final conflictBloc = di.sl<ConflictBloc>();

      // The bloc seeded from the freshly loaded settings starts on them.
      expect(settingsBloc.state.settings, settings);

      // Repositories resolve to their abstractions (BLoCs depend on these).
      expect(di.sl<SettingsRepository>(), isNotNull);
      expect(di.sl<HistoryRepository>(), isNotNull);
      expect(di.sl<CollectionsRepository>(), isNotNull);
      expect(di.sl<RequestRulesRepository>(), isNotNull);
      expect(di.sl<EnvironmentsRepository>(), isNotNull);
      expect(di.sl<TabsRepository>(), isNotNull);
      expect(di.sl<UpdateRepository>(), isNotNull);

      // Use cases + git/collab services + core singletons.
      expect(di.sl<GetSettingsUseCase>(), isNotNull);
      expect(di.sl<SaveSettingsUseCase>(), isNotNull);
      expect(di.sl<AddToHistoryUseCase>(), isNotNull);
      expect(di.sl<GetCollectionsUseCase>(), isNotNull);
      expect(di.sl<SaveCollectionsUseCase>(), isNotNull);
      expect(di.sl<GetRequestRulesUseCase>(), isNotNull);
      expect(di.sl<SaveRequestRulesUseCase>(), isNotNull);
      expect(di.sl<SendRequestUseCase>(), isNotNull);
      expect(di.sl<TabDirtyChecker>(), isNotNull);
      expect(di.sl<WorkspaceSyncService>(), isNotNull);
      expect(di.sl<GitService>(), isNotNull);
      expect(di.sl<GhService>(), isNotNull);
      expect(di.sl<ReviewService>(), isNotNull);
      expect(di.sl<BranchService>(), isNotNull);
      expect(di.sl<ConflictService>(), isNotNull);
      expect(di.sl<PullRequestService>(), isNotNull);
      expect(di.sl<CookieStore>(), isNotNull);
      expect(di.sl<NetworkService>(), isNotNull);
      expect(di.sl<RealtimeService>(), isNotNull);
      expect(di.sl<McpService>(), isNotNull);
      expect(di.sl<UpdateController>(), isNotNull);
      expect(di.sl<UrlFocusRegistry>(), isNotNull);
      expect(di.sl<RequestSectionIndex>(), isNotNull);
      expect(di.sl<WorkspacePulseController>(), isNotNull);
      expect(di.sl<AppRouter>(), isNotNull);

      await Future.wait([
        settingsBloc.close(),
        historyBloc.close(),
        collectionsBloc.close(),
        rulesBloc.close(),
        environmentsBloc.close(),
        tabsBloc.close(),
        realtimeBloc.close(),
        mcpBloc.close(),
        reviewBloc.close(),
        gitSyncBloc.close(),
        pullRequestsBloc.close(),
        conflictBloc.close(),
      ]);
    },
  );

  test('a warm boot returns the previously saved settings', () async {
    await di.init(storageDirectoryOverride: tempDir.path);
    await di.sl<SaveSettingsUseCase>()(
      const SettingsEntity(historyLimit: 42, isDarkMode: true),
    );
    await di.reset();

    // Second init in the same directory: the adapter guard must skip
    // re-registration and the saved settings must come back.
    final settings = await di.init(storageDirectoryOverride: tempDir.path);

    expect(settings.historyLimit, 42);
    expect(settings.isDarkMode, isTrue);
  });

  test(
    'init without a storage override boots via the platform documents dir',
    () async {
      // Production path: Hive.initFlutter resolves the app documents dir
      // through path_provider — mock its channel to point at the temp dir.
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMethodCallHandler(channel, (_) async => tempDir.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final settings = await di.init();

      expect(settings, const SettingsEntity());
      expect(
        Directory(tempDir.path).listSync(),
        isNotEmpty,
        reason: 'Hive must have created its boxes under the resolved dir',
      );
    },
  );
}
