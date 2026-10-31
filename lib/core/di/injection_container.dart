// GetIt (`sl`) bootstrap: registers every feature's blocs/usecases/repos and
// data sources. initSettings opens only settings; initServices starts the
// feature-storage owner isolate after the first frame. init composes both for
// test harnesses and returns the SettingsEntity for main(). Hive adapters are
// registered idempotently by hive_adapters.dart in each owning isolate.
//
// Cookie hydration completes before NetworkService becomes usable.
// Script trust stays in a local primitive box; retired Rules data is untouched.
// reset() tears down get_it + closes boxes for E2E
// between-test isolation; registered adapters intentionally survive (Hive
// can't unregister them).

import 'package:get_it/get_it.dart';
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/core/git/git_service.dart';
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/cookie_interceptor.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/storage/background_repositories.dart';
import 'package:getman/core/storage/hive_adapters.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:getman/core/theme/motion/workspace_pulse_controller.dart';
import 'package:getman/features/collections/data/datasources/workspace_data_source_factory.dart';
import 'package:getman/features/collections/data/services/gh_pull_request_service.dart';
import 'package:getman/features/collections/data/services/git_branch_service.dart';
import 'package:getman/features/collections/data/services/git_conflict_service.dart';
import 'package:getman/features/collections/data/services/workspace_review_service.dart';
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
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/repositories/script_runtime_repository.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/settings/data/datasources/settings_local_data_source.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/data/repositories/tabs_repository_impl.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/logic/script_execution_registry.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/execute_request_use_case.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/body_field_dictionary_cubit.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/data/repositories/update_repository_impl.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

final GetIt sl = GetIt.instance;

/// Boots the dependency graph and returns the settings to launch with.
///
/// [storageDirectoryOverride] points Hive at a specific directory instead of
/// the platform app-support dir. Production passes nothing (uses
/// `initFlutter`); E2E/integration tests pass a throwaway temp dir so a test
/// run never reads or wipes the developer's real saved data. Pair with [reset]
/// between tests.
Future<SettingsEntity> init({String? storageDirectoryOverride}) async {
  final settings = await initSettings(
    storageDirectoryOverride: storageDirectoryOverride,
  );
  await initServices(settings);
  return settings;
}

/// Minimal first-frame dependency: only the saved appearance/settings record.
/// All larger stores and their migrations belong in [initServices].
Future<SettingsEntity> initSettings({String? storageDirectoryOverride}) async {
  if (storageDirectoryOverride != null) {
    Hive.init(storageDirectoryOverride);
  } else {
    await Hive.initFlutter();
  }

  registerHiveAdapters();

  final box = await Hive.openBox<SettingsModel>(HiveBoxes.settings);
  return box.get('current')?.toEntity() ?? const SettingsEntity();
}

/// Completes startup after the themed first frame. Call once after
/// [initSettings]; consumers must wait for completion before accessing DI.
Future<void> initServices(SettingsEntity initialSettings) async {
  final storage = await openStorageConnection(
    Hive.box<SettingsModel>(HiveBoxes.settings).path,
  );
  sl.registerSingleton<StorageConnection>(
    storage,
    dispose: (connection) => connection.close(),
  );
  final environments = BackgroundEnvironmentsRepository(storage);
  final initialEnvironments = await environments.getEnvironments();
  final cookies = await storage.invoke<List<NetworkCookie>>(
    StorageOperation.cookiesGet,
  );
  final dictionary = await storage.invoke<List<BodyFieldEntry>>(
    StorageOperation.dictionaryGet,
  );

  sl
    // Features - Settings
    ..registerLazySingleton(
      () => SettingsBloc(
        saveSettingsUseCase: sl(),
        initialSettings: initialSettings,
      ),
    )
    ..registerLazySingleton(() => GetSettingsUseCase(sl()))
    ..registerLazySingleton(() => SaveSettingsUseCase(sl()))
    ..registerLazySingleton<SettingsRepository>(
      () => SettingsRepositoryImpl(sl()),
    )
    ..registerLazySingleton<SettingsLocalDataSource>(
      SettingsLocalDataSourceImpl.new,
    )
    // Features - History
    ..registerLazySingleton(
      () => HistoryBloc(
        watchHistoryUseCase: sl(),
        deleteHistoryEntryUseCase: sl(),
        clearHistoryUseCase: sl(),
        restoreHistoryEntriesUseCase: sl(),
      ),
    )
    ..registerLazySingleton(() => AddToHistoryUseCase(sl()))
    ..registerLazySingleton(() => WatchHistoryUseCase(sl()))
    ..registerLazySingleton(() => DeleteHistoryEntryUseCase(sl()))
    ..registerLazySingleton(() => ClearHistoryUseCase(sl()))
    ..registerLazySingleton(() => RestoreHistoryEntriesUseCase(sl()))
    ..registerLazySingleton<HistoryRepository>(
      () => BackgroundHistoryRepository(storage),
    )
    // Features - Collections
    ..registerLazySingleton(
      () => CollectionsBloc(
        getCollectionsUseCase: sl(),
        saveCollectionsUseCase: sl(),
      ),
    )
    ..registerLazySingleton(() => GetCollectionsUseCase(sl()))
    ..registerLazySingleton(() => SaveCollectionsUseCase(sl()))
    ..registerLazySingleton<CollectionsRepository>(
      () => BackgroundCollectionsRepository(storage),
    )
    ..registerLazySingleton(
      () => WorkspaceSyncService(createWorkspaceDataSource()),
    )
    ..registerLazySingleton<GitService>(createGitService)
    ..registerLazySingleton<ReviewService>(
      () => WorkspaceReviewService(sl(), sl()),
    )
    ..registerLazySingleton<BranchService>(() => GitBranchService(sl(), sl()))
    ..registerLazySingleton<ConflictService>(
      () => GitConflictService(sl(), sl()),
    )
    ..registerLazySingleton<GhService>(createGhService)
    ..registerLazySingleton<PullRequestService>(
      () => GhPullRequestService(sl(), sl()),
    )
    ..registerFactory(() => ReviewBloc(service: sl()))
    ..registerFactory(() => GitSyncBloc(service: sl()))
    ..registerFactory(() => PullRequestsBloc(service: sl()))
    ..registerFactory(() => ConflictBloc(service: sl()))
    // Features - Environments
    ..registerLazySingleton(
      () => EnvironmentsBloc(
        getEnvironmentsUseCase: sl(),
        saveEnvironmentsUseCase: sl(),
        putEnvironmentUseCase: sl(),
        deleteEnvironmentUseCase: sl(),
        initialEnvironments: initialEnvironments,
        watchEnvironmentsUseCase: sl(),
      ),
    )
    ..registerLazySingleton(() => WatchEnvironmentsUseCase(sl()))
    ..registerLazySingleton(() => GetEnvironmentsUseCase(sl()))
    ..registerLazySingleton(() => SaveEnvironmentsUseCase(sl()))
    ..registerLazySingleton(() => PutEnvironmentUseCase(sl()))
    ..registerLazySingleton(() => DeleteEnvironmentUseCase(sl()))
    ..registerLazySingleton<EnvironmentsRepository>(
      () => environments,
    )
    ..registerLazySingleton<ScriptRuntimeRepository>(
      ScriptRuntimeRepositoryImpl.new,
      dispose: (runtime) => runtime.close(),
    )
    ..registerLazySingleton<ScriptTrustRepository>(
      () => BackgroundScriptTrustRepository(storage),
    )
    ..registerLazySingleton(ScriptExecutionRegistry.new)
    ..registerLazySingleton(
      () => ExecuteRequestUseCase(
        sendRequest: sl(),
        runtime: sl(),
        environments: sl(),
        trust: sl(),
        registry: sl(),
      ),
    )
    // Features - Tabs
    ..registerLazySingleton<BodyFieldDictionaryRepository>(
      () =>
          BackgroundBodyFieldDictionary(storage, List.unmodifiable(dictionary)),
    )
    ..registerFactory(() => BodyFieldDictionaryCubit(sl()))
    ..registerLazySingleton(
      () => TabsBloc(
        repository: sl(),
        sendRequestUseCase: sl(),
        executeRequestUseCase: sl(),
      ),
    )
    ..registerLazySingleton(
      () => SendRequestUseCase(
        tabsRepository: sl(),
        addToHistoryUseCase: sl(),
        getSettingsUseCase: sl(),
      ),
    )
    ..registerLazySingleton<TabsRepository>(
      () => TabsRepositoryImpl(
        persistence: BackgroundTabsPersistence(storage),
        networkService: sl(),
      ),
    )
    // Features - Realtime (WebSocket / SSE). RealtimeService itself is
    // registered below, alongside NetworkService, once the cookie store and
    // initial NetworkConfig it needs (H2) are available.
    ..registerLazySingleton(() => RealtimeBloc(service: sl()))
    // Features - MCP (Model Context Protocol client over Streamable HTTP).
    // McpService itself is registered below, alongside NetworkService, once
    // the cookie store and initial NetworkConfig it needs are available.
    ..registerLazySingleton(() => McpBloc(service: sl()))
    // Features - Home
    ..registerLazySingleton(() => const TabDirtyChecker())
    // Features - Updates (GitHub release auto-update)
    ..registerLazySingleton(GithubReleaseDataSource.new)
    ..registerLazySingleton<UpdateRepository>(
      () => UpdateRepositoryImpl(sl<GithubReleaseDataSource>()),
    )
    ..registerLazySingleton(() => UpdateController(sl<UpdateRepository>()))
    // Lets the Cmd/Ctrl+L shortcut focus the active tab's URL field.
    ..registerLazySingleton(UrlFocusRegistry.new)
    // Session-global PARAMS/AUTH/HEADERS/BODY/SCRIPTS selection, shared across
    // every request tab's editor strip.
    ..registerLazySingleton(RequestSectionIndex.new)
    ..registerLazySingleton<WorkspacePulseController>(
      WorkspacePulseController.new,
    );

  // Core. The cookie snapshot came from the worker; hydrate the jar
  // before the network service can be used so the first send sees stored
  // cookies.
  final cookieStore = InMemoryCookieStore(
    persistence: BackgroundCookiePersistence(storage, cookies),
  )..hydrate();
  sl
    ..registerLazySingleton<CookieStore>(() => cookieStore)
    ..registerLazySingleton(
      () => NetworkService(
        dio: NetworkService.buildDio(
          initialSettings.toNetworkConfig(),
          CookieInterceptor(cookieStore),
        ),
      ),
    )
    // Wired like NetworkService: the same NetworkConfig (SSL verify/proxy/
    // mTLS) and cookie jar, so SSE respects network settings and sends
    // session cookies (H2) instead of a bare, unconfigured Dio.
    ..registerLazySingleton(
      () => RealtimeService(
        dio: RealtimeService.buildSseDio(
          initialSettings.toNetworkConfig(),
          CookieInterceptor(cookieStore),
        ),
      ),
    )
    // Same wiring for MCP: SSL verify/proxy/mTLS + cookie jar — a bare Dio
    // here silently ignored every network setting and stored cookie.
    ..registerLazySingleton(
      () => McpService(
        dio: McpService.buildMcpDio(
          initialSettings.toNetworkConfig(),
          CookieInterceptor(cookieStore),
        ),
      ),
    )
    ..registerLazySingleton(AppRouter.new);
}

/// Tears down the DI container and closes all Hive boxes so [init] can be
/// called again with a fresh storage directory. Used by the E2E harness
/// between flows; not part of the production boot path. Registered Hive
/// adapters intentionally survive (Hive cannot unregister them, and [init]
/// guards against re-adding them).
Future<void> reset() async {
  await sl.reset();
  await Hive.close();
}
